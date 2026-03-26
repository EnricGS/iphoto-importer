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

    // MARK: - Grid State

    var photos: [PhotoItem] = []
    var filteredPhotos: [PhotoItem] {
        switch mediaFilter {
        case .all: return photos
        case .photos: return photos.filter { $0.isImage }
        case .videos: return photos.filter { $0.isVideo }
        }
    }
    var selectedPhotos: Set<PhotoItem> = []
    var thumbnailSize: CGFloat = 150
    var mediaFilter: MediaFilter = .all
    var lastClickedIndex: Int?

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

    // MARK: - Destination Folder

    var destinationFolder: String?
    var hasDestinationFolder: Bool { destinationFolder != nil && !destinationFolder!.isEmpty }

    // MARK: - Scroll Request (for split mode sync)

    var scrollToIndex: Int?

    // MARK: - Folder Operations

    func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select an image folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await loadFolder(at: url.path)
        }
    }

    func loadFolder(at path: String) async {
        // Cancel previous operations
        thumbnailTask?.cancel()
        prefetchTask?.cancel()

        isLoading = true
        hasError = false
        statusMessage = "Scanning folder..."
        currentFolderPath = path

        // Close viewer if open
        closeViewer()

        photos.removeAll()
        selectedPhotos.removeAll()

        do {
            let items = try await fileService.scanFolder(at: path) { [weak self] scanned, found, file in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Scanning... \(found) images found — \(file)"
                }
            }

            // Sort by date (newest first)
            let sorted = items.sorted { a, b in
                (b.dateTaken ?? .distantPast) < (a.dateTaken ?? .distantPast)
            }

            photos = sorted

            let folderName = (path as NSString).lastPathComponent
            statusMessage = "\(photos.count) image(s) found in \(folderName)"

            // Load thumbnails in background
            loadThumbnails()
        } catch {
            hasError = true
            statusMessage = "Error scanning folder: \(error.localizedDescription)"
        }

        isLoading = false
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
        guard let index = filteredPhotos.firstIndex(of: item) else { return }

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
        let items = filteredPhotos
        guard !items.isEmpty else { return }
        let newIndex = (viewerIndex + 1) % items.count
        navigateViewer(to: newIndex)
    }

    func viewerPrevious() {
        let items = filteredPhotos
        guard !items.isEmpty else { return }
        let newIndex = (viewerIndex - 1 + items.count) % items.count
        navigateViewer(to: newIndex)
    }

    private func navigateViewer(to index: Int) {
        let items = filteredPhotos
        guard index >= 0 && index < items.count else { return }

        // Remove previous highlight
        viewerCurrentItem?.isHighlighted = false

        viewerIndex = index
        viewerZoom = 1.0
        viewerOffsetX = 0
        viewerOffsetY = 0

        loadViewerImage(for: items[index])

        // In split mode, request scroll to the active thumbnail
        if isSplitMode {
            scrollToIndex = index
        }
    }

    private func loadViewerImage(for item: PhotoItem) {
        viewerCurrentItem = item
        item.isHighlighted = true

        if item.isVideo {
            isViewingVideo = true
            viewerVideoURL = URL(fileURLWithPath: item.fullPath)
            viewerImage = item.thumbnail
            updateViewerInfo(for: item)
            return
        }

        isViewingVideo = false
        viewerVideoURL = nil

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
        let items = filteredPhotos
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
        let items = filteredPhotos
        var parts: [String] = [
            "\(viewerIndex + 1) / \(items.count)",
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
        for photo in filteredPhotos {
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

    /// Handles grid click with modifier keys (Cmd+click, Shift+click).
    func handleGridClick(item: PhotoItem, isCommandPressed: Bool, isShiftPressed: Bool) {
        let items = filteredPhotos

        if isCommandPressed {
            // Cmd+click: toggle individual selection
            toggleSelection(for: item)
            lastClickedIndex = items.firstIndex(of: item)
        } else if isShiftPressed, let lastIndex = lastClickedIndex {
            // Shift+click: range selection
            guard let clickedIndex = items.firstIndex(of: item) else { return }

            let start = min(lastIndex, clickedIndex)
            let end = max(lastIndex, clickedIndex)
            for i in start...end {
                items[i].isSelected = true
                selectedPhotos.insert(items[i])
            }
        } else {
            // Simple click: open in viewer
            lastClickedIndex = items.firstIndex(of: item)
            openViewer(for: item)
        }
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
                photos.removeAll { $0 == item }
                selectedPhotos.remove(item)
            }

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
                photos.removeAll { $0 == item }
                selectedPhotos.remove(item)
            }

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

    func importFromDevice() async {
        let panel = NSOpenPanel()
        panel.title = "Select destination for import"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let imported = try await deviceService.importPhotos(to: url.path) { current, total, fileName in
                // Progress reporting
            }

            let alert = NSAlert()
            alert.messageText = "Import Complete"
            alert.informativeText = "\(imported) photo(s) imported to:\n\(url.path)\n\nOpen folder in viewer?"
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Close")

            if alert.runModal() == .alertFirstButtonReturn {
                isImportPanelOpen = false
                await loadFolder(at: url.path)
            }
        } catch {
            deviceService.statusMessage = "Import error: \(error.localizedDescription)"
        }
    }
}
