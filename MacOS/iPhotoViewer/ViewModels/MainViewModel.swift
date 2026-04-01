import Foundation
import AppKit
import SwiftUI
import Combine
import CoreLocation

/// Main ViewModel for the application. Manages the image viewer,
/// thumbnail grid, and file management operations.
@MainActor
@Observable
final class MainViewModel {

    // MARK: - Services

    private let fileService = FileService()
    private let thumbnailCache = ThumbnailCacheService()
    private let imageCache = ImageCacheService(maxSize: 20)
    let deviceService = DeviceImportService()

    init() {
        loadPersistedSettings()
    }

    // MARK: - Cancellation

    private var thumbnailTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var viewerDownloadTask: Task<Void, Never>?

    // MARK: - General State

    var statusMessage: String = "Open a folder to start viewing images."
    var hasError: Bool = false
    var isLoading: Bool = false
    var isCopying: Bool = false
    var copyProgress: Double = 0
    var currentFolderPath: String?

    // MARK: - Multi-Folder Support

    /// Folders that scan recursively (per-folder setting)
    var recursiveFolders: Set<String> = []

    /// List of open folders
    var openFolders: [String] = []

    /// Number of open folders (for binding)
    var openFolderCount: Int { openFolders.count }

    // MARK: - Grid State

    /// All photos (unfiltered master list)
    private var allPhotos: [PhotoItem] = []

    /// Filtered photos shown in the grid
    var photos: [PhotoItem] = []
    var selectedPhotos: Set<PhotoItem> = []
    var thumbnailSize: CGFloat = 150
    var lastClickedIndex: Int?

    /// Filter toggles (both active by default, like Windows)
    var filterPhotos: Bool = true {
        didSet {
            // If both off, force the other one on
            if !filterPhotos && !filterVideos {
                filterVideos = true
                return
            }
            applyFilter()
        }
    }

    var filterVideos: Bool = true {
        didSet {
            if !filterVideos && !filterPhotos {
                filterPhotos = true
                return
            }
            applyFilter()
        }
    }

    /// Sort order: false = newest first, true = oldest first
    var sortAscending: Bool = false

    /// Timeline vs grid mode
    var isTimelineMode: Bool = false

    /// Timeline grouping level
    var timelineGrouping: TimelineGrouping = .month

    /// Collapsed group keys
    var collapsedGroups: Set<String> = []

    /// Grouped photos for timeline display
    var groupedPhotos: [(key: String, photos: [PhotoItem])] = []

    /// Counts by type (for filter toggle labels)
    var photoCount: Int = 0
    var videoCount: Int = 0

    var selectedPhotosCount: Int { selectedPhotos.count }
    var totalSelectedSizeMB: Double {
        let bytes = selectedPhotos.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return Double(bytes) / (1024.0 * 1024.0)
    }
    var showActionBar: Bool { !selectedPhotos.isEmpty }

    // MARK: - Viewer State

    var isViewerOpen: Bool = false
    var viewerCurrentItem: PhotoItem?
    var viewerImage: NSImage?
    var viewerIndex: Int = 0
    var viewerZoom: CGFloat = 1.0
    var viewerOffsetX: CGFloat = 0
    var viewerOffsetY: CGFloat = 0
    var viewerInfoText: String = ""
    var isViewingVideo: Bool = false
    var viewerVideoURL: URL?
    var viewerVideoRotation: Int = 0

    var hasViewerImage: Bool { isViewerOpen && viewerImage != nil }

    // MARK: - View Mode

    var viewMode: ViewMode = .toggle

    var isSplitMode: Bool { viewMode == .split }

    var isSplitViewerVisible: Bool {
        viewMode == .split && viewerCurrentItem != nil
    }

    var isOverlayViewerVisible: Bool {
        viewMode == .toggle && isViewerOpen
    }

    // MARK: - Photo Scan (find folders with photos on disk)

    var isScanningDisk: Bool = false
    var diskScanResults: [String] = []  // Folder paths with photos
    var diskScanProgress: String = ""
    var diskScanDeep: Bool = false  // false = typical locations, true = full disk
    var showScanResults: Bool = false
    private var diskScanTask: Task<Void, Never>?

    /// Typical photo locations to scan
    private static let typicalPhotoLocations: [String] = {
        let home = NSHomeDirectory()
        var paths = [
            home + "/Pictures",
            home + "/Desktop",
            home + "/Downloads",
            home + "/Documents",
            home + "/Photos",
        ]
        // Add external volumes
        if let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") {
            for vol in volumes where vol != "Macintosh HD" {
                paths.append("/Volumes/\(vol)")
            }
        }
        return paths
    }()

    func startDiskScan() {
        diskScanTask?.cancel()
        diskScanResults = []
        isScanningDisk = true
        showScanResults = true

        let searchRoots = diskScanDeep
            ? [NSHomeDirectory()] + ((try? FileManager.default.contentsOfDirectory(atPath: "/Volumes").filter { $0 != "Macintosh HD" }.map { "/Volumes/\($0)" }) ?? [])
            : Self.typicalPhotoLocations

        diskScanTask = Task {
            let fm = FileManager.default
            var foundFolders = Set<String>()

            for root in searchRoots {
                guard !Task.isCancelled else { break }
                guard fm.fileExists(atPath: root) else { continue }

                diskScanProgress = "Cercant a \((root as NSString).lastPathComponent)..."

                guard let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    guard !Task.isCancelled else { break }

                    let ext = fileURL.pathExtension.lowercased()
                    if PhotoItem.allExtensions.contains(ext) {
                        let folder = fileURL.deletingLastPathComponent().path
                        if !foundFolders.contains(folder) {
                            foundFolders.insert(folder)
                            diskScanResults.append(folder)
                            diskScanProgress = "Trobades \(foundFolders.count) carpetes..."
                        }
                    }
                }
            }

            diskScanProgress = "\(foundFolders.count) carpetes amb fotos trobades."
            isScanningDisk = false
        }
    }

    func cancelDiskScan() {
        diskScanTask?.cancel()
        isScanningDisk = false
    }

    func addScanResults(_ folders: [String]) async {
        showScanResults = false
        for folder in folders {
            await addFolder(at: folder)
        }
    }

    // MARK: - Import Panel

    var isImportPanelOpen: Bool = false

    // MARK: - Device Browse Mode

    var isDeviceBrowseMode: Bool = false
    private var savedLocalPhotos: [PhotoItem] = []
    private var savedOpenFolders: [String] = []
    private var savedCurrentFolder: String?

    // MARK: - Destination Folder (persistent via UserDefaults)

    var destinationFolder: String? {
        didSet { UserDefaults.standard.set(destinationFolder, forKey: "destinationFolder") }
    }
    var hasDestinationFolder: Bool { destinationFolder != nil && !destinationFolder!.isEmpty }

    private func loadPersistedSettings() {
        destinationFolder = UserDefaults.standard.string(forKey: "destinationFolder")
    }

    // MARK: - Scroll Request (for split mode sync)

    var scrollToIndex: Int?

    // MARK: - Sort

    /// Toggles sort order between newest-first and oldest-first, then re-applies.
    func toggleSortOrder() {
        sortAscending.toggle()
        applyFilter()
    }

    func toggleTimelineMode() {
        isTimelineMode.toggle()
    }

    func setTimelineGrouping(_ grouping: TimelineGrouping) {
        timelineGrouping = grouping
        collapsedGroups.removeAll()
        rebuildGroups()
    }

    func toggleGroupCollapse(_ key: String) {
        print("[Timeline] Toggle collapse: \(key), was collapsed: \(collapsedGroups.contains(key))")
        if collapsedGroups.contains(key) {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    private static let catalanMonths = [
        "Gener", "Febrer", "Març", "Abril", "Maig", "Juny",
        "Juliol", "Agost", "Setembre", "Octubre", "Novembre", "Desembre"
    ]

    private func groupKey(for date: Date?) -> String {
        guard let date else { return "Sense data" }
        let cal = Calendar.current
        switch timelineGrouping {
        case .year:
            return "\(cal.component(.year, from: date))"
        case .month:
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return "\(Self.catalanMonths[m - 1]) \(y)"
        case .day:
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return "\(d) \(Self.catalanMonths[m - 1]) \(y)"
        }
    }

    private static func logLocation(_ msg: String) {
        let path = NSHomeDirectory() + "/iphoto_import.log"
        let line = "\(Date()): [Location] \(msg)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Formats a placemark into "Localitat, País" with Catalan rules.
    /// Catalunya → shows "Catalunya" instead of "Espanya".
    static func formatLocation(from placemark: CLPlacemark) -> String? {
        let locality = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        guard let locality else { return placemark.country }

        let region = placemark.administrativeArea ?? ""
        let isoCountry = placemark.isoCountryCode ?? ""

        // Catalunya: províncies catalanes
        let catalanProvinces = ["Barcelona", "Girona", "Lleida", "Tarragona"]
        if isoCountry == "ES" {
            if catalanProvinces.contains(where: { region.localizedCaseInsensitiveContains($0) }) {
                return "\(locality), Catalunya"
            }
            return "\(locality), Espanya"
        }

        if let country = placemark.country {
            return "\(locality), \(country)"
        }
        return locality
    }

    private func rebuildGroups() {
        var dict: [String: [PhotoItem]] = [:]
        var order: [String] = []
        for photo in photos {
            let key = groupKey(for: photo.dateTaken)
            if dict[key] == nil {
                order.append(key)
                dict[key] = []
            }
            dict[key]!.append(photo)
        }
        groupedPhotos = order.map { (key: $0, photos: dict[$0]!) }
    }

    // MARK: - Filter

    /// Applies the photo/video filter toggles to the photos collection.
    private func applyFilter() {
        photos.removeAll()
        selectedPhotos.removeAll()

        let filtered: [PhotoItem]
        switch (filterPhotos, filterVideos) {
        case (true, true):
            filtered = allPhotos
        case (true, false):
            filtered = allPhotos.filter { !$0.isVideo }
        case (false, true):
            filtered = allPhotos.filter { $0.isVideo }
        default:
            filtered = allPhotos
        }

        let sorted = filtered.sorted { a, b in
            let dateA = a.dateTaken ?? .distantPast
            let dateB = b.dateTaken ?? .distantPast
            return sortAscending ? dateA < dateB : dateA > dateB
        }

        for item in sorted {
            item.isSelected = false
            photos.append(item)
        }

        // In device browse mode, restart thumbnail loading for items
        // that don't have thumbnails yet (handles reorder/filter changes)
        if isDeviceBrowseMode {
            loadDeviceThumbnails()
        }

        rebuildGroups()
        updateStatusMessage()
    }

    // MARK: - Folder Operations

    func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select an image folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await addFolder(at: url.path)
        }
    }

    /// Adds a folder to the viewer, accumulating photos with existing ones.
    func addFolder(at path: String) async {
        // If folder is already open, skip
        if openFolders.contains(path) {
            let folderName = (path as NSString).lastPathComponent
            statusMessage = "Folder already open: \(folderName)"
            return
        }

        // Cancel previous thumbnail operations
        thumbnailTask?.cancel()
        prefetchTask?.cancel()

        isLoading = true
        hasError = false
        statusMessage = "Scanning folder..."
        currentFolderPath = path

        // Close viewer if open
        closeViewer()

        do {
            let items = try await fileService.scanFolder(at: path, recursive: recursiveFolders.contains(path)) { [weak self] scanned, found, file in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Scanning... \(found) images found — \(file)"
                }
            }

            // Add the folder to the list
            openFolders.append(path)

            // Add new photos
            allPhotos.append(contentsOf: items)

            // Sort all by date (newest first)
            allPhotos.sort { a, b in
                (a.dateTaken ?? .distantPast) > (b.dateTaken ?? .distantPast)
            }

            // Update counts
            photoCount = allPhotos.filter { !$0.isVideo }.count
            videoCount = allPhotos.filter { $0.isVideo }.count

            // Apply current filter
            applyFilter()

            updateStatusMessage()

            // Load thumbnails in background
            loadThumbnails()

            // Load GPS locations in background (after thumbnails start)
            loadLocations()
        } catch {
            hasError = true
            statusMessage = "Error scanning folder: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Loads images from a folder (replaces all, for import compatibility).
    func loadFolder(at path: String) async {
        clearAllFolders()
        await addFolder(at: path)
    }

    /// Removes a folder and its photos from the view.
    /// Toggle recursive scan for a folder and rescan it.
    func toggleRecursive(for folderPath: String) {
        if recursiveFolders.contains(folderPath) {
            recursiveFolders.remove(folderPath)
        } else {
            recursiveFolders.insert(folderPath)
        }
        // Rescan this folder
        allPhotos.removeAll { $0.fullPath.hasPrefix(folderPath) }
        openFolders.removeAll { $0 == folderPath }
        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        applyFilter()
        Task { await addFolder(at: folderPath) }
    }

    func removeFolder(_ folderPath: String) {
        guard openFolders.contains(folderPath) else { return }

        closeViewer()

        // Remove photos from this folder
        allPhotos.removeAll { $0.fullPath.hasPrefix(folderPath) }

        // Remove the folder
        openFolders.removeAll { $0 == folderPath }

        // Update current folder path
        currentFolderPath = openFolders.last

        // Update counts
        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count

        // Re-apply filter
        applyFilter()
        updateStatusMessage()
    }

    /// Clears all folders and photos.
    func clearAllFolders() {
        thumbnailTask?.cancel()
        prefetchTask?.cancel()

        closeViewer()

        openFolders.removeAll()
        allPhotos.removeAll()
        photos.removeAll()
        selectedPhotos.removeAll()
        currentFolderPath = nil
        photoCount = 0
        videoCount = 0

        statusMessage = "Open a folder to start viewing images."
    }

    /// Updates the status message with folder and image counts.
    private func updateStatusMessage() {
        if openFolders.isEmpty {
            statusMessage = "Open a folder to start viewing images."
        } else if openFolders.count == 1 {
            let folderName = (openFolders[0] as NSString).lastPathComponent
            statusMessage = "\(allPhotos.count) image(s) from \(folderName)"
        } else {
            statusMessage = "\(allPhotos.count) image(s) from \(openFolders.count) folders"
        }
    }

    // MARK: - Thumbnail Loading

    private func loadThumbnails() {
        thumbnailTask?.cancel()

        let photosCopy = photos
        thumbnailTask = Task {
            let batchSize = 4

            for batchStart in stride(from: 0, to: photosCopy.count, by: batchSize) {
                guard !Task.isCancelled else { return }

                let batchEnd = min(batchStart + batchSize, photosCopy.count)
                let batch = Array(photosCopy[batchStart..<batchEnd])

                await withTaskGroup(of: (Int, NSImage?).self) { group in
                    for (offset, photo) in batch.enumerated() {
                        guard photo.thumbnail == nil else { continue }
                        let index = batchStart + offset
                        let path = photo.fullPath

                        group.addTask { [thumbnailCache] in
                            let thumb = await thumbnailCache.getThumbnail(for: path)
                            return (index, thumb)
                        }
                    }

                    for await (index, thumb) in group {
                        guard !Task.isCancelled else { return }
                        if let thumb, index < photosCopy.count {
                            photosCopy[index].thumbnail = thumb
                        }
                    }
                }
            }
        }
    }

    // MARK: - Location Loading

    private var locationTask: Task<Void, Never>?

    /// Reverse-geocodes GPS coordinates for local photos that have EXIF GPS data.
    private func loadLocations() {
        locationTask?.cancel()
        let photosCopy = photos.filter { $0.isLocal && $0.location == nil && !$0.isVideo }
        let geocoder = CLGeocoder()
        let catalanLocale = Locale(identifier: "ca_ES")
        Self.logLocation("Starting location loading for \(photosCopy.count) photos")

        locationTask = Task {
            // Cache: rounded coords → location string (avoid geocoding same place repeatedly)
            var locationCache: [String: String] = [:]

            for photo in photosCopy {
                guard !Task.isCancelled else { return }

                guard let coords = FileService.extractGPSLocation(at: photo.fullPath) else { continue }

                // Round to ~100m precision for cache key
                let cacheKey = "\(Int(coords.latitude * 1000)),\(Int(coords.longitude * 1000))"

                if let cached = locationCache[cacheKey] {
                    photo.location = cached
                    if viewerCurrentItem == photo { updateViewerInfo(for: photo) }
                    continue
                }

                let location = CLLocation(latitude: coords.latitude, longitude: coords.longitude)
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: catalanLocale)
                    if let placemark = placemarks.first {
                        let loc = Self.formatLocation(from: placemark)
                        Self.logLocation("Geocoded \(photo.fileName): \(loc ?? "nil") [admin=\(placemark.administrativeArea ?? "?")]")
                        photo.location = loc
                        if let loc { locationCache[cacheKey] = loc }
                        if viewerCurrentItem == photo { updateViewerInfo(for: photo) }
                    }
                } catch {
                    Self.logLocation("Geocoding FAILED for \(photo.fileName): \(error.localizedDescription)")
                }

                // Rate limit only for actual geocoding calls
                try? await Task.sleep(for: .milliseconds(300))
            }
            Self.logLocation("Location loading complete. Cache: \(locationCache.count) unique locations")
        }
    }

    // MARK: - Viewer

    func openViewer(for item: PhotoItem) {
        guard !photos.isEmpty else { return }
        guard let index = photos.firstIndex(of: item) else { return }

        viewerIndex = index

        if isSplitMode {
            loadViewerImage(for: item)
        } else {
            isViewerOpen = true
            isImportPanelOpen = false  // Auto-collapse panel when viewing a photo
            loadViewerImage(for: item)
        }
    }

    func closeViewer() {
        prefetchTask?.cancel()
        viewerDownloadTask?.cancel()
        viewerDownloadTask = nil
        isViewerOpen = false
        viewerImage = nil
        viewerCurrentItem = nil
        isViewingVideo = false
        viewerVideoURL = nil
        viewerVideoRotation = 0
        viewerZoom = 1.0
        viewerOffsetX = 0
        viewerOffsetY = 0
        viewerInfoText = ""

        // Remove highlight from all items
        for photo in photos {
            photo.isHighlighted = false
        }
    }

    func viewerNext() {
        guard !photos.isEmpty else { return }
        let newIndex = (viewerIndex + 1) % photos.count
        navigateViewer(to: newIndex)
    }

    func viewerPrevious() {
        guard !photos.isEmpty else { return }
        let newIndex = (viewerIndex - 1 + photos.count) % photos.count
        navigateViewer(to: newIndex)
    }

    private func navigateViewer(to index: Int) {
        guard index >= 0 && index < photos.count else { return }

        // Remove previous highlight
        viewerCurrentItem?.isHighlighted = false

        viewerIndex = index
        viewerZoom = 1.0
        viewerOffsetX = 0
        viewerOffsetY = 0

        loadViewerImage(for: photos[index])

        // In split mode, request scroll to the active thumbnail
        if isSplitMode {
            scrollToIndex = index
        }
    }

    private func loadViewerImage(for item: PhotoItem) {
        viewerCurrentItem = item
        item.isHighlighted = true

        // Cancel any previous device download task
        viewerDownloadTask?.cancel()
        viewerDownloadTask = nil

        // Device items: show thumbnail first, then download full-res
        if !item.isLocal {
            isViewingVideo = false
            viewerVideoURL = nil
            // Show thumbnail if available; keep previous image as fallback
            // so there's visual feedback during navigation
            if let thumb = item.thumbnail {
                viewerImage = thumb
            }
            updateViewerInfo(for: item)

            if let cameraFile = item.cameraFile {
                viewerDownloadTask = Task {
                    guard !Task.isCancelled else { return }
                    if let localPath = await deviceService.downloadTempFile(cameraFile) {
                        guard !Task.isCancelled, viewerCurrentItem == item else { return }
                        let image = await Task.detached(priority: .userInitiated) { [fileService] in
                            fileService.loadFullImage(at: localPath)
                        }.value
                        if let image, !Task.isCancelled, viewerCurrentItem == item {
                            viewerImage = image
                            if item.pixelWidth == 0 {
                                let rep = image.representations.first
                                item.pixelWidth = rep?.pixelsWide ?? Int(image.size.width)
                                item.pixelHeight = rep?.pixelsHigh ?? Int(image.size.height)
                            }
                            updateViewerInfo(for: item)
                        }
                    }
                }
            }
            return
        }

        if item.isVideo {
            isViewingVideo = true
            // Read rotation if not yet set
            if item.videoRotation == 0 {
                item.videoRotation = FileService.getVideoRotation(filePath: item.fullPath)
            }
            viewerVideoRotation = item.videoRotation
            viewerVideoURL = URL(fileURLWithPath: item.fullPath)
            viewerImage = item.thumbnail
            updateViewerInfo(for: item)
            return
        }

        isViewingVideo = false
        viewerVideoURL = nil
        viewerVideoRotation = 0

        // Geocode on-demand if no location yet
        if item.location == nil && item.isLocal {
            Task { await geocodeViewerItem(item) }
        }

        // 1. Show thumbnail immediately (progressive rendering)
        if let thumb = item.thumbnail {
            viewerImage = thumb
        }

        // 2. Check LRU cache
        if let cached = imageCache.get(item.fullPath) {
            viewerImage = cached
            updateViewerInfo(for: item)
            prefetchNeighbors()
            return
        }

        // 3. Load full resolution in background
        Task {
            await loadFullImage(for: item)
        }
    }

    private func loadFullImage(for item: PhotoItem) async {
        let path = item.fullPath

        let image = await Task.detached(priority: .userInitiated) { [fileService] in
            fileService.loadFullImage(at: path)
        }.value

        guard let image, viewerCurrentItem == item else { return }

        imageCache.put(path, image: image)
        viewerImage = image

        // Update pixel dimensions if not yet set
        if item.pixelWidth == 0 {
            let rep = image.representations.first
            item.pixelWidth = rep?.pixelsWide ?? Int(image.size.width)
            item.pixelHeight = rep?.pixelsHigh ?? Int(image.size.height)
        }

        updateViewerInfo(for: item)
        prefetchNeighbors()
    }

    /// Geocodes a single item for immediate display in the viewer.
    private func geocodeViewerItem(_ item: PhotoItem) async {
        guard let coords = FileService.extractGPSLocation(at: item.fullPath) else {
            Self.logLocation("[Viewer] No GPS for \(item.fileName)")
            return
        }
        Self.logLocation("[Viewer] Geocoding \(item.fileName)...")
        let geocoder = CLGeocoder()
        let catalanLocale = Locale(identifier: "ca_ES")
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coords.latitude, longitude: coords.longitude),
                preferredLocale: catalanLocale
            )
            if let placemark = placemarks.first {
                let loc = Self.formatLocation(from: placemark)
                Self.logLocation("[Viewer] Got: \(loc ?? "nil"), isCurrent: \(viewerCurrentItem == item)")
                item.location = loc
                // Always update — don't check equality (same object reference)
                updateViewerInfo(for: item)
            }
        } catch {
            Self.logLocation("[Viewer] FAILED: \(error.localizedDescription)")
        }
    }

    /// Prefetches neighbor images (N +/- 2) for fast navigation.
    private func prefetchNeighbors() {
        prefetchTask?.cancel()
        let items = photos
        let currentIndex = viewerIndex

        prefetchTask = Task {
            let offsets = [1, -1, 2, -2]

            for offset in offsets {
                guard !Task.isCancelled else { return }

                let idx = (currentIndex + offset + items.count) % items.count
                guard idx != currentIndex else { continue }

                let photo = items[idx]
                guard !imageCache.contains(photo.fullPath), !photo.isVideo else { continue }

                let path = photo.fullPath
                let image = await Task.detached(priority: .utility) { [fileService] in
                    fileService.loadFullImage(at: path)
                }.value

                if let image {
                    imageCache.put(path, image: image)
                }
            }
        }
    }

    private func updateViewerInfo(for item: PhotoItem) {
        var parts: [String] = [
            "\(viewerIndex + 1) / \(photos.count)",
            item.fileName
        ]

        if let date = item.dateTaken {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            parts.append(formatter.string(from: date))
        }

        if let location = item.location {
            parts.append(location)
        }

        if item.pixelWidth > 0 {
            parts.append("\(item.pixelWidth) x \(item.pixelHeight)")
        }

        if item.sizeBytes > 0 {
            parts.append(item.fileSizeFormatted)
        }

        viewerInfoText = parts.joined(separator: "  |  ")
    }

    // MARK: - Zoom & Pan

    func viewerZoomIn() {
        viewerZoom = min(viewerZoom * 1.25, 10.0)
    }

    func viewerZoomOut() {
        viewerZoom = max(viewerZoom / 1.25, 0.1)
    }

    /// Smooth zoom towards a cursor position within a container.
    /// `cursorX`/`cursorY` are relative to the center of the container.
    func viewerSmoothZoom(delta: CGFloat, cursorX: CGFloat, cursorY: CGFloat) {
        let sensitivity: CGFloat = 0.02
        let factor = 1.0 + (-delta * sensitivity)
        let newZoom = max(0.1, min(viewerZoom * factor, 10.0))

        // Adjust offset to zoom towards cursor position
        let scale = newZoom / viewerZoom
        viewerOffsetX = cursorX - scale * (cursorX - viewerOffsetX)
        viewerOffsetY = cursorY - scale * (cursorY - viewerOffsetY)

        viewerZoom = newZoom
    }

    func viewerZoomReset() {
        viewerZoom = 1.0
        viewerOffsetX = 0
        viewerOffsetY = 0
    }

    func viewerFitToScreen() {
        viewerZoom = 1.0
        viewerOffsetX = 0
        viewerOffsetY = 0
    }

    // MARK: - Selection

    func toggleSelection(for item: PhotoItem) {
        item.isSelected.toggle()
        if item.isSelected {
            selectedPhotos.insert(item)
        } else {
            selectedPhotos.remove(item)
        }
    }

    func selectAll() {
        for photo in photos {
            photo.isSelected = true
            selectedPhotos.insert(photo)
        }
    }

    func deselectAll() {
        for photo in photos {
            photo.isSelected = false
        }
        selectedPhotos.removeAll()
    }

    /// Selects a specific set of photos (used by rubber band selection).
    func selectItems(_ items: Set<PhotoItem>) {
        deselectAll()
        for item in items {
            item.isSelected = true
            selectedPhotos.insert(item)
        }
    }

    /// Returns file URLs for all selected photos (for drag & drop).
    func selectedFileURLs() -> [URL] {
        selectedPhotos.compactMap { URL(fileURLWithPath: $0.fullPath) }
    }

    /// Handles click on the image area (opens viewer).
    func handleGridClick(item: PhotoItem) {
        lastClickedIndex = photos.firstIndex(of: item)
        openViewer(for: item)
    }

    /// Handles click on the checkbox (toggles selection, supports Shift for range).
    func handleCheckboxClick(item: PhotoItem, isShiftPressed: Bool) {
        if isShiftPressed, let lastIndex = lastClickedIndex {
            guard let clickedIndex = photos.firstIndex(of: item) else { return }
            let start = min(lastIndex, clickedIndex)
            let end = max(lastIndex, clickedIndex)
            for i in start...end {
                photos[i].isSelected = true
                selectedPhotos.insert(photos[i])
            }
            // Ensure the clicked item itself is always selected
            item.isSelected = true
            selectedPhotos.insert(item)
        } else {
            toggleSelection(for: item)
        }
        lastClickedIndex = photos.firstIndex(of: item)
    }

    // MARK: - View Mode

    func toggleViewMode() {
        if viewMode == .split {
            viewMode = .toggle
            // Switch to toggle: if there's an image in the split viewer, open overlay
            if viewerCurrentItem != nil {
                isViewerOpen = true
            }
        } else {
            viewMode = .split
            // Switch to split: if overlay was open, close it but keep the image in split panel
            if isViewerOpen {
                isViewerOpen = false
            }
        }
    }

    // MARK: - File Actions

    func setDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select default destination folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            destinationFolder = url.path
            statusMessage = "Destination folder: \(url.path)"
        }
    }

    func clearDestinationFolder() {
        destinationFolder = nil
        statusMessage = "Destination folder cleared."
    }

    /// Resolves the destination folder: returns the pre-set one if available,
    /// otherwise opens a folder picker. Returns nil if user cancels.
    private func resolveDestinationFolder(title: String = "Select destination folder") -> String? {
        if let dest = destinationFolder, !dest.isEmpty {
            return dest
        }

        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    func copySelected() async {
        guard !selectedPhotos.isEmpty else { return }

        guard let dest = resolveDestinationFolder(title: "Select destination for copy") else { return }

        await copyFiles(Array(selectedPhotos), to: dest)
    }

    func copyCurrentPhoto() async {
        guard let item = viewerCurrentItem else { return }

        guard let dest = resolveDestinationFolder(title: "Select destination for copy") else { return }

        await copyFiles([item], to: dest)
    }

    private func copyFiles(_ files: [PhotoItem], to destination: String) async {
        isLoading = true
        isCopying = true
        hasError = false
        copyProgress = 0

        do {
            let copied = try await fileService.copyFiles(files, to: destination) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.copyProgress = Double(current) / Double(total) * 100
                    self?.statusMessage = "Copying \(current)/\(total): \(fileName)"
                }
            }
            copyProgress = 100
            statusMessage = "\(copied) file(s) copied to \(destination)"
        } catch {
            hasError = true
            statusMessage = "Error copying: \(error.localizedDescription)"
        }

        isCopying = false
        isLoading = false
    }

    func moveSelected() async {
        guard !selectedPhotos.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.title = "Select destination for move"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Confirm with the user
        let alert = NSAlert()
        alert.messageText = "Confirm Move"
        alert.informativeText = "Move \(selectedPhotos.count) file(s) to:\n\(url.path)\n\nThis action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isLoading = true
        isCopying = true
        hasError = false
        copyProgress = 0

        let filesToMove = Array(selectedPhotos)

        do {
            let moved = try await fileService.moveFiles(filesToMove, to: url.path) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.copyProgress = Double(current) / Double(total) * 100
                    self?.statusMessage = "Moving \(current)/\(total): \(fileName)"
                }
            }
            copyProgress = 100

            // Remove moved items from the list
            for item in filesToMove {
                allPhotos.removeAll { $0 == item }
                photos.removeAll { $0 == item }
                selectedPhotos.remove(item)
            }

            photoCount = allPhotos.filter { !$0.isVideo }.count
            videoCount = allPhotos.filter { $0.isVideo }.count

            statusMessage = "\(moved) file(s) moved to \(url.path)"
        } catch {
            hasError = true
            statusMessage = "Error moving: \(error.localizedDescription)"
        }

        isCopying = false
        isLoading = false
    }

    func deleteSelected() async {
        guard !selectedPhotos.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Confirm Delete"
        alert.informativeText = "Move \(selectedPhotos.count) file(s) to Trash?\n\nYou can restore them from Trash if needed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isLoading = true
        hasError = false

        let filesToDelete = Array(selectedPhotos)

        do {
            let deleted = try await fileService.deleteFiles(filesToDelete) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Deleting \(current)/\(total): \(fileName)"
                }
            }

            for item in filesToDelete {
                allPhotos.removeAll { $0 == item }
                photos.removeAll { $0 == item }
                selectedPhotos.remove(item)
            }

            photoCount = allPhotos.filter { !$0.isVideo }.count
            videoCount = allPhotos.filter { $0.isVideo }.count

            statusMessage = "\(deleted) file(s) moved to Trash."
        } catch {
            hasError = true
            statusMessage = "Error deleting: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Import Panel

    func toggleImportPanel() {
        if isDeviceBrowseMode {
            exitDeviceBrowseMode()
            return
        }
        isImportPanelOpen.toggle()
        if isImportPanelOpen {
            // Auto-detect devices
            Task { await autoConnectDevice() }
        }
    }

    func detectDevices() async {
        await deviceService.detectDevices()
    }

    /// Auto flow: detect → select single device → browse automatically
    private func autoConnectDevice() async {
        await deviceService.detectDevices()

        if deviceService.devices.count == 1 {
            // Auto-select the only device and browse
            deviceService.selectedDevice = deviceService.devices[0]
            await browseDevice()
        }
        // Si 0 o >1 dispositius, el panell d'import queda obert per selecció manual
    }

    // MARK: - Device Browse

    func browseDevice() async {
        do {
            let items = try await deviceService.browseDevice()
            guard !items.isEmpty else { return }

            // Save current local state
            savedLocalPhotos = allPhotos
            savedOpenFolders = openFolders
            savedCurrentFolder = currentFolderPath

            // Enter browse mode (keep import panel open for status)
            isDeviceBrowseMode = true
            closeViewer()

            // Set device photos in the grid (sorted by date)
            allPhotos = items.sorted { a, b in
                let dateA = a.dateTaken ?? .distantPast
                let dateB = b.dateTaken ?? .distantPast
                return sortAscending ? dateA < dateB : dateA > dateB
            }
            photoCount = allPhotos.filter { !$0.isVideo }.count
            videoCount = allPhotos.filter { $0.isVideo }.count
            applyFilter()

            // Register disconnect callback
            deviceService.onDeviceDisconnected = { [weak self] in
                self?.exitDeviceBrowseMode()
            }

            // Load thumbnails from device in background (no location in browse — too slow)
            loadDeviceThumbnails()
        } catch {
            deviceService.statusMessage = "Error de navegació: \(error.localizedDescription)"
        }
    }

    private func loadDeviceThumbnails() {
        thumbnailTask?.cancel()
        let photosCopy = photos
        thumbnailTask = Task {
            for photo in photosCopy {
                guard !Task.isCancelled, let cameraFile = photo.cameraFile else { continue }
                guard photo.thumbnail == nil else { continue }
                if let thumb = await deviceService.requestThumbnail(for: cameraFile) {
                    photo.thumbnail = thumb
                }
            }
        }
    }

    private var deviceLocationTask: Task<Void, Never>?

    private func loadDeviceLocations() {
        deviceLocationTask?.cancel()
        let photosCopy = photos.filter { !$0.isLocal && $0.location == nil && $0.gpsLatitude != nil }
        let geocoder = CLGeocoder()
        let catalanLocale = Locale(identifier: "ca_ES")

        deviceLocationTask = Task {
            for photo in photosCopy {
                guard !Task.isCancelled,
                      let lat = photo.gpsLatitude,
                      let lon = photo.gpsLongitude else { continue }

                let location = CLLocation(latitude: lat, longitude: lon)
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(location, preferredLocale: catalanLocale)
                    if let placemark = placemarks.first {
                        photo.location = Self.formatLocation(from: placemark)
                    }
                } catch {
                    // Geocoding failed — skip
                }

                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func importSelectedFromDevice() async {
        let selected = Array(selectedPhotos)
        let files = selected.compactMap { $0.cameraFile }
        guard !files.isEmpty else { return }

        guard let dest = resolveDestinationFolder(title: "Select destination for import") else { return }

        let imported = await deviceService.importSelectedFiles(files, to: dest) { [weak self] current, total, fileName in
            Task { @MainActor [weak self] in
                self?.statusMessage = "Importing \(current)/\(total): \(fileName)"
            }
        }

        // Stay in device browse mode — just deselect imported items
        deselectAll()
        statusMessage = "\(imported) fitxer(s) importat(s) a \(dest). \(allPhotos.count) fitxers al dispositiu."
    }

    func deleteSelectedFromDevice() async {
        let selected = Array(selectedPhotos)
        let files = selected.compactMap { $0.cameraFile }
        guard !files.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Eliminar del dispositiu"
        alert.informativeText = "Eliminar permanentment \(files.count) fitxer(s) de \(deviceService.selectedDevice?.name ?? "dispositiu")?\n\nAquesta acció no es pot desfer."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancel·lar")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        await deviceService.deleteFiles(files)

        // Remove deleted items from the master list and re-apply filter (which re-sorts)
        for item in selected {
            allPhotos.removeAll { $0 == item }
            selectedPhotos.remove(item)
        }
        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        applyFilter()
        statusMessage = "\(files.count) fitxer(s) eliminat(s). \(allPhotos.count) restants al dispositiu."
    }

    func exitDeviceBrowseMode() {
        guard isDeviceBrowseMode else { return }

        thumbnailTask?.cancel()
        deviceLocationTask?.cancel()
        closeViewer()
        deviceService.closeSession()
        deviceService.onDeviceDisconnected = nil
        deviceService.selectedDevice = nil
        deviceService.devices = []
        deviceService.statusMessage = "Connecta un iPhone o càmera per USB."
        isImportPanelOpen = false

        // Restore local state
        allPhotos = savedLocalPhotos
        openFolders = savedOpenFolders
        currentFolderPath = savedCurrentFolder
        savedLocalPhotos = []
        savedOpenFolders = []
        savedCurrentFolder = nil

        isDeviceBrowseMode = false

        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        applyFilter()
        updateStatusMessage()
    }
}
