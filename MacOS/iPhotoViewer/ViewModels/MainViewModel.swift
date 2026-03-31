import Foundation
import AppKit
import SwiftUI
import Combine

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

    // MARK: - General State

    var statusMessage: String = "Open a folder to start viewing images."
    var hasError: Bool = false
    var isLoading: Bool = false
    var isCopying: Bool = false
    var copyProgress: Double = 0
    var currentFolderPath: String?

    // MARK: - Multi-Folder Support

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

        for item in filtered {
            item.isSelected = false
            photos.append(item)
        }

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
            let items = try await fileService.scanFolder(at: path) { [weak self] scanned, found, file in
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

    // MARK: - Viewer

    func openViewer(for item: PhotoItem) {
        guard !photos.isEmpty else { return }
        guard let index = photos.firstIndex(of: item) else { return }

        viewerIndex = index

        if isSplitMode {
            loadViewerImage(for: item)
        } else {
            isViewerOpen = true
            loadViewerImage(for: item)
        }
    }

    func closeViewer() {
        prefetchTask?.cancel()
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

        // Device items: show thumbnail only, no full-res available
        if !item.isLocal {
            isViewingVideo = false
            viewerVideoURL = nil
            viewerImage = item.thumbnail
            updateViewerInfo(for: item)
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

        if item.pixelWidth > 0 {
            parts.append("\(item.pixelWidth) x \(item.pixelHeight)")
        }

        if let date = item.dateTaken {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy HH:mm"
            parts.append(formatter.string(from: date))
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
        isImportPanelOpen.toggle()
        if isImportPanelOpen {
            deviceService.statusMessage = "Import panel open. Press 'Detect' to scan for devices."
        }
    }

    func detectDevices() async {
        await deviceService.detectDevices()
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

            // Enter browse mode
            isDeviceBrowseMode = true
            closeViewer()
            isImportPanelOpen = false

            // Set device photos in the grid
            allPhotos = items
            photoCount = items.filter { !$0.isVideo }.count
            videoCount = items.filter { $0.isVideo }.count
            applyFilter()

            // Register disconnect callback
            deviceService.onDeviceDisconnected = { [weak self] in
                self?.exitDeviceBrowseMode()
            }

            // Load thumbnails from device in background
            loadDeviceThumbnails()
        } catch {
            deviceService.statusMessage = "Browse error: \(error.localizedDescription)"
        }
    }

    private func loadDeviceThumbnails() {
        thumbnailTask?.cancel()
        let photosCopy = photos
        thumbnailTask = Task {
            for photo in photosCopy {
                guard !Task.isCancelled, let cameraFile = photo.cameraFile else { continue }
                if let thumb = await deviceService.requestThumbnail(for: cameraFile) {
                    photo.thumbnail = thumb
                }
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
        statusMessage = "\(imported) file(s) imported to \(dest). \(allPhotos.count) files on device."
    }

    func deleteSelectedFromDevice() async {
        let selected = Array(selectedPhotos)
        let files = selected.compactMap { $0.cameraFile }
        guard !files.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Delete from Device"
        alert.informativeText = "Permanently delete \(files.count) file(s) from \(deviceService.selectedDevice?.name ?? "device")?\n\nThis cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        await deviceService.deleteFiles(files)

        // Remove deleted items from the grid
        for item in selected {
            allPhotos.removeAll { $0 == item }
            photos.removeAll { $0 == item }
            selectedPhotos.remove(item)
        }
        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        statusMessage = "\(files.count) file(s) deleted. \(allPhotos.count) remaining on device."
    }

    func exitDeviceBrowseMode() {
        guard isDeviceBrowseMode else { return }

        thumbnailTask?.cancel()
        closeViewer()
        deviceService.closeSession()
        deviceService.onDeviceDisconnected = nil

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
