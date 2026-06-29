import Foundation
import AppKit
import SwiftUI
import Combine
import CoreLocation

private func logDebug(_ msg: String) {
    let path = "/tmp/iphoto_debug.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

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
    private let miratStore = MiratDestinationStore()

    init() {
        loadPersistedSettings()
    }

    // MARK: - Cancellation

    private var thumbnailTask: Task<Void, Never>?
    /// Ids de fotos amb el thumbnail en curs (dedup entre la càrrega mandrosa per
    /// cel·la i la de fons, perquè no es demani dues vegades).
    private var loadingThumbIds = Set<String>()
    private var prefetchTask: Task<Void, Never>?
    private var viewerDownloadTask: Task<Void, Never>?

    // MARK: - General State

    var statusMessage: String = "Obre una carpeta per veure imatges."
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

    /// Estat d'undo per a l'última operació d'eliminació (1 nivell)
    private var lastDeletedItems: [PhotoItem] = []
    private var lastDeletedTrashPairs: [(originalPath: String, trashURL: URL)] = []
    var canUndoDelete: Bool { !lastDeletedItems.isEmpty }

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

    /// Deduplication
    var filterExactDuplicates: Bool = false {
        didSet { applyFilter(); scanDeviceDuplicatesIfNeeded() }
    }
    var filterSimilarDuplicates: Bool = false {
        didSet { applyFilter(); scanDeviceDuplicatesIfNeeded() }
    }
    var exactDuplicateCount: Int = 0
    var similarDuplicateCount: Int = 0
    /// Si ja s'ha escanejat duplicats en aquesta sessió de browse del dispositiu
    /// (l'escaneig és SOTA DEMANDA: s'activa amb el filtre, no en navegar).
    private var hasScannedDeviceDuplicates = false
    var isScanningExact: Bool = false
    var isScanningSimilar: Bool = false
    private var duplicateScanTask: Task<Void, Never>?

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

    // MARK: - Destins Mirat (API externa a https://www.miratfotos.com o self-hosted)

    /// Llista de destins Mirat configurats, carregada de disc a l'inici.
    var miratDestinations: [MiratDestination] = []

    /// Destí Mirat actualment seleccionat al toolbar. Nil = no hi ha cap actiu.
    var activeMiratDestination: MiratDestination?

    var hasActiveMiratDestination: Bool { activeMiratDestination != nil }
    var activeMiratLabel: String { activeMiratDestination?.displayLabel ?? "Sense destí Mirat" }

    /// Estat de progrés mentre s'està pujant a Mirat.
    var isUploadingToMirat: Bool = false
    var miratUploadProgress: Double = 0

    private func loadPersistedSettings() {
        destinationFolder = UserDefaults.standard.string(forKey: "destinationFolder")
        miratDestinations = miratStore.load()
    }

    // MARK: - Gestió de destins Mirat

    /// Afegeix (o actualitza si ja existeix el mateix Id) un destí Mirat i el persisteix.
    func addOrUpdateMiratDestination(_ dest: MiratDestination) {
        if let idx = miratDestinations.firstIndex(where: { $0.id == dest.id }) {
            miratDestinations[idx] = dest
            // Si era l'actiu, refresca també la seleccio activa
            if activeMiratDestination?.id == dest.id {
                activeMiratDestination = dest
            }
        } else {
            miratDestinations.append(dest)
        }
        miratStore.save(miratDestinations)
    }

    func removeMiratDestination(_ dest: MiratDestination) {
        miratDestinations.removeAll { $0.id == dest.id }
        if activeMiratDestination?.id == dest.id {
            activeMiratDestination = nil
        }
        miratStore.save(miratDestinations)
    }

    /// Activa/desactiva destí Mirat. Passa nil per desactivar i tornar a usar carpeta local.
    func selectMiratDestination(_ dest: MiratDestination?) {
        activeMiratDestination = dest
        if let dest {
            statusMessage = "Destí Mirat actiu: \(dest.displayLabel)"
        } else {
            statusMessage = "Destí Mirat desactivat."
        }
    }

    /// Orquestra l'upload d'un conjunt de fotos a Mirat. Paral·lelisme controlat
    /// (3 uploads simultanis), reporta progrés a statusMessage/miratUploadProgress.
    func uploadPhotosToMirat(_ photos: [PhotoItem], destination dest: MiratDestination) async {
        guard !photos.isEmpty else { return }

        isUploadingToMirat = true
        miratUploadProgress = 0
        hasError = false

        // Missatge immediat perquè l'usuari sàpiga que ha començat. Sense
        // això, durant la preparació (SHA-256 + thumbnail + primer fetch)
        // es queda visible el missatge anterior i sembla que s'hagi penjat.
        statusMessage = "Preparant pujada a Mirat (\(dest.displayLabel)): 0/\(photos.count)…"

        let svc = MiratService(destination: dest)
        let total = photos.count
        var uploaded = 0
        var duplicats = 0
        var errors = 0
        var lastError: String?

        // Pugem en dues tandes amb concurrència diferent (sliding window):
        //  - IMATGES: concurrència 3 (petites, multipart pel pod → ràpid).
        //  - VÍDEOS: concurrència 1 (serialitzats). Els vídeos van DIRECTES a MinIO
        //    (presignat) i són grans; fer-ne diversos alhora satura el disc únic del
        //    NAS i provoca 503 SlowDown. D'un en un, cada escriptura gran va sola.
        //    (A més, el PUT presignat reintenta amb backoff per si de cas.)
        func processarTanda(_ items: [PhotoItem], concurrency: Int) async {
            guard !items.isEmpty else { return }
            await withTaskGroup(of: MiratUploadResult.self) { group in
                var iterator = items.makeIterator()
                var inFlight = 0
                while inFlight < concurrency, let photo = iterator.next() {
                    group.addTask { await svc.uploadPhoto(photo) }
                    inFlight += 1
                }
                while let result = await group.next() {
                    inFlight -= 1
                    if result.success {
                        if result.duplicat { duplicats += 1 } else { uploaded += 1 }
                    } else {
                        errors += 1
                        lastError = result.errorMessage
                    }

                    let done = uploaded + duplicats + errors
                    miratUploadProgress = Double(done) / Double(total) * 100.0
                    var msg = "Pujant a Mirat (\(dest.displayLabel)): \(done)/\(total) "
                        + "· \(uploaded) noves · \(duplicats) duplicades · \(errors) errors"
                    if let lastError {
                        msg += " — Últim error: \(lastError)"
                    }
                    statusMessage = msg

                    if let next = iterator.next() {
                        group.addTask { await svc.uploadPhoto(next) }
                        inFlight += 1
                    }
                }
            }
        }

        let esVideo: (PhotoItem) -> Bool = {
            PhotoItem.videoExtensions.contains(URL(fileURLWithPath: $0.fullPath).pathExtension.lowercased())
        }
        await processarTanda(photos.filter { !esVideo($0) }, concurrency: 3)  // imatges, concurrents
        await processarTanda(photos.filter(esVideo), concurrency: 1)          // vídeos, serialitzats

        isUploadingToMirat = false
        miratUploadProgress = 0
        hasError = errors > 0

        // Netejar la selecció després d'una tanda completa (independentment
        // d'errors): l'usuari ha vist el resum final i no se sentir-se atrapat
        // amb fotos marcades que costa desseleccionar. Si vol reintentar les
        // que han fallat, les pot tornar a triar.
        for photo in photos where photo.isSelected {
            photo.isSelected = false
        }
        selectedPhotos.removeAll()

        var finalMsg = "Acabat: \(uploaded) noves · \(duplicats) duplicades · \(errors) errors a \(dest.displayLabel)."
        if let lastError {
            finalMsg += " — Últim error: \(lastError)"
        }
        statusMessage = finalMsg
    }

    /// Envia les fotos seleccionades del DISPOSITIU directament a Mirat: les baixa a
    /// una carpeta temporal (reusa el camí d'importació), les puja amb el flux de
    /// Mirat i esborra la temporal. Sense còpia permanent al disc.
    func uploadSelectedDeviceToMirat() async {
        guard let dest = activeMiratDestination else {
            statusMessage = "Cap destí Mirat seleccionat. Vincula'n un primer (⚙️)."
            return
        }
        let selected = Array(selectedPhotos)
        let files = selected.compactMap { $0.cameraFile }
        guard !files.isEmpty else { return }

        let tempFolder = NSTemporaryDirectory() + "iPhotoManager-mirat-\(UUID().uuidString)/"

        // 1) Baixa del telèfon a la carpeta temporal (en sèrie, com la importació normal).
        statusMessage = "Baixant \(files.count) del telèfon…"
        _ = await deviceService.importSelectedFiles(files, to: tempFolder) { _, _, _ in }

        // 2) Construeix PhotoItems locals des de la carpeta temporal i puja'ls a Mirat
        //    (concurrent, amb dedup/thumbnail/GPS via MiratService).
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: tempFolder)) ?? []
        let tempPhotos: [PhotoItem] = names.map { name in
            let path = tempFolder + name
            let size = ((try? fm.attributesOfItem(atPath: path))?[.size] as? Int64) ?? 0
            let original = selected.first { $0.fileName == name }
            return PhotoItem(fullPath: path, fileName: name, dateTaken: original?.dateTaken, sizeBytes: size, isLocal: true)
        }
        await uploadPhotosToMirat(tempPhotos, destination: dest)

        // 3) Neteja: carpeta temporal + selecció del dispositiu (la graella).
        try? fm.removeItem(atPath: tempFolder)
        for photo in selected { photo.isSelected = false }
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
        selectedPhotos.removeAll()

        var filtered: [PhotoItem]
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

        // Apply duplicates filter
        if filterExactDuplicates || filterSimilarDuplicates {
            filtered = filtered.filter { item in
                guard let groupId = item.duplicateGroupId else { return false }
                if filterExactDuplicates && groupId.hasPrefix("md5-") { return true }
                if filterSimilarDuplicates && (groupId.hasPrefix("phash-") || groupId.hasPrefix("exif-")) { return true }
                return false
            }
        }

        let sorted = filtered.sorted { a, b in
            let dateA = a.dateTaken ?? .distantPast
            let dateB = b.dateTaken ?? .distantPast
            return sortAscending ? dateA < dateB : dateA > dateB
        }

        for item in sorted {
            item.isSelected = false
        }

        // In device browse mode: propagate thumbnails within exact duplicate groups
        // so items without loaded thumbnails show the same image as their sibling
        if isDeviceBrowseMode && filterExactDuplicates {
            var groups: [String: [PhotoItem]] = [:]
            for item in sorted {
                guard let gid = item.duplicateGroupId, gid.hasPrefix("md5-") else { continue }
                groups[gid, default: []].append(item)
            }
            logDebug("[DupFilter] \(sorted.count) items, \(groups.count) groups")
            for (gid, group) in groups {
                let withThumb = group.filter { $0.thumbnail != nil }.count
                let withoutThumb = group.filter { $0.thumbnail == nil }.count
                logDebug("[DupFilter] group=\(gid) total=\(group.count) withThumb=\(withThumb) withoutThumb=\(withoutThumb)")
                if let donor = group.first(where: { $0.thumbnail != nil }) {
                    for item in group where item.thumbnail == nil {
                        item.thumbnail = donor.thumbnail
                        logDebug("[DupFilter] Propagated thumb to \(item.fileName)")
                    }
                } else {
                    logDebug("[DupFilter] NO DONOR in group \(gid)!")
                }
            }
        }

        // Replace in one shot (avoid empty grid flash)
        photos = sorted

        // En mode browse els thumbnails es carreguen MANDROSAMENT per cel·la
        // (.task a la graella) → no cal forçar cap càrrega en reordenar/filtrar.

        rebuildGroups()
        updateStatusMessage()
    }

    // MARK: - Folder Operations

    func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Selecciona una carpeta d'imatges"
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
            statusMessage = "Carpeta ja oberta: \(folderName)"
            return
        }

        // Cancel previous thumbnail operations
        thumbnailTask?.cancel()
        prefetchTask?.cancel()

        isLoading = true
        hasError = false
        statusMessage = "Escanejant carpeta..."
        currentFolderPath = path

        // Close viewer if open
        closeViewer()

        do {
            let items = try await fileService.scanFolder(at: path, recursive: recursiveFolders.contains(path)) { [weak self] scanned, found, file in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Escanejant... \(found) imatges trobades — \(file)"
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

            // Scan for duplicates in background
            scanForDuplicates()
        } catch {
            hasError = true
            statusMessage = "Error escanejant carpeta: \(error.localizedDescription)"
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

        statusMessage = "Obre una carpeta per veure imatges."
    }

    /// Updates the status message with folder and image counts.
    private func updateStatusMessage() {
        if isDeviceBrowseMode {
            let deviceName = deviceService.selectedDevice?.name ?? "dispositiu"
            statusMessage = "\(photos.count) imatge(s) de \(deviceName)"
            return
        }
        if openFolders.isEmpty {
            statusMessage = "Obre una carpeta per veure imatges."
        } else if openFolders.count == 1 {
            let folderName = (openFolders[0] as NSString).lastPathComponent
            statusMessage = "\(allPhotos.count) imatge(s) de \(folderName)"
        } else {
            statusMessage = "\(allPhotos.count) imatge(s) de \(openFolders.count) carpetes"
        }
    }

    // MARK: - Deduplication

    /// Scans all photos for duplicates using 3 strategies:
    /// 1. MD5 hash (exact copies)
    /// 2. Perceptual hash (visually similar)
    /// 3. EXIF fingerprint (same camera + moment)
    private func scanForDuplicates() {
        duplicateScanTask?.cancel()
        isScanningExact = true
        isScanningSimilar = true
        print("[Dedup] Scan started — isScanningExact=\(isScanningExact) isScanningSimilar=\(isScanningSimilar)")

        // Clear previous results
        for item in allPhotos {
            item.duplicateGroupId = nil
            item.md5Hash = nil
            item.perceptualHash = nil
            item.exifFingerprint = nil
        }
        exactDuplicateCount = 0
        similarDuplicateCount = 0

        let items = allPhotos.filter { $0.isLocal }

        duplicateScanTask = Task {
            // --- Pass 1: Group by file size (pre-filter) ---
            var sizeGroups: [Int64: [PhotoItem]] = [:]
            for item in items {
                sizeGroups[item.sizeBytes, default: []].append(item)
            }

            // --- Pass 2: MD5 for same-size files ---
            let sameSizeGroups = sizeGroups.values.filter { $0.count > 1 }

            for group in sameSizeGroups {
                if Task.isCancelled { return }
                for item in group {
                    if Task.isCancelled { return }
                    let path = item.fullPath
                    let hash = await Task.detached(priority: .utility) {
                        FileService.computeMD5(at: path)
                    }.value
                    await MainActor.run { item.md5Hash = hash }
                }
            }

            // Assign duplicate groups by MD5
            var md5Groups: [String: [PhotoItem]] = [:]
            for group in sameSizeGroups {
                for item in group {
                    guard let hash = item.md5Hash else { continue }
                    md5Groups[hash, default: []].append(item)
                }
            }

            var markedItems = Set<String>() // Track items already marked as duplicates
            for (hash, group) in md5Groups where group.count > 1 {
                let groupId = "md5-\(hash.prefix(12))"
                await MainActor.run {
                    for item in group {
                        item.duplicateGroupId = groupId
                        markedItems.insert(item.id)
                    }
                    self.exactDuplicateCount = self.allPhotos.filter { $0.duplicateGroupId?.hasPrefix("md5-") == true }.count
                }
            }

            await MainActor.run {
                self.isScanningExact = false
                print("[Dedup] Exact done — count=\(self.exactDuplicateCount)")
            }

            // --- Pass 3: Perceptual hash for images not yet marked ---
            let unmarkedImages = items.filter { !markedItems.contains($0.id) && $0.isImage && !$0.isVideo }

            for item in unmarkedImages {
                if Task.isCancelled { return }
                let path = item.fullPath
                let hash = await Task.detached(priority: .utility) {
                    FileService.computePerceptualHash(at: path)
                }.value
                await MainActor.run { item.perceptualHash = hash }
            }

            // Find perceptual duplicates (O(n²) — precise, acceptable speed for typical folders)
            let withPHash = unmarkedImages.filter { $0.perceptualHash != nil }
            var pHashProcessed = Set<String>()

            for i in 0..<withPHash.count {
                if Task.isCancelled { return }
                let itemA = withPHash[i]
                guard !pHashProcessed.contains(itemA.id),
                      let hashA = itemA.perceptualHash else { continue }

                var group: [PhotoItem] = [itemA]

                for j in (i+1)..<withPHash.count {
                    let itemB = withPHash[j]
                    guard !pHashProcessed.contains(itemB.id),
                          let hashB = itemB.perceptualHash else { continue }

                    if FileService.hammingDistance(hashA, hashB) <= 5 {
                        group.append(itemB)
                    }
                }

                if group.count > 1 {
                    let groupId = "phash-\(String(hashA, radix: 16).prefix(12))"
                    await MainActor.run {
                        for item in group {
                            item.duplicateGroupId = groupId
                            markedItems.insert(item.id)
                            pHashProcessed.insert(item.id)
                        }
                        // Update counter immediately when a new group is found
                        self.similarDuplicateCount = self.allPhotos.filter {
                            $0.duplicateGroupId?.hasPrefix("phash-") == true || $0.duplicateGroupId?.hasPrefix("exif-") == true
                        }.count
                    }
                }

                // Yield every 50 items to keep UI responsive
                if i % 50 == 0 {
                    await Task.yield()
                }
            }

            // --- Pass 4: EXIF fingerprint for remaining unmarked images ---
            let stillUnmarked = items.filter { !markedItems.contains($0.id) && $0.isImage && !$0.isVideo }

            for item in stillUnmarked {
                if Task.isCancelled { return }
                let path = item.fullPath
                let fp = await Task.detached(priority: .utility) {
                    FileService.computeExifFingerprint(at: path)
                }.value
                await MainActor.run { item.exifFingerprint = fp }
            }

            // Group by EXIF fingerprint
            var exifGroups: [String: [PhotoItem]] = [:]
            for item in stillUnmarked {
                guard let fp = item.exifFingerprint else { continue }
                exifGroups[fp, default: []].append(item)
            }

            for (fp, group) in exifGroups where group.count > 1 {
                let groupId = "exif-\(fp.prefix(12))"
                await MainActor.run {
                    for item in group {
                        item.duplicateGroupId = groupId
                    }
                }
            }

            // Update counts and refresh filter
            await MainActor.run {
                self.exactDuplicateCount = self.allPhotos.filter { $0.duplicateGroupId?.hasPrefix("md5-") == true }.count
                self.similarDuplicateCount = self.allPhotos.filter {
                    $0.duplicateGroupId?.hasPrefix("phash-") == true || $0.duplicateGroupId?.hasPrefix("exif-") == true
                }.count
                self.isScanningSimilar = false
                print("[Dedup] Similar done — count=\(self.similarDuplicateCount)")
                if self.filterExactDuplicates || self.filterSimilarDuplicates {
                    self.applyFilter()
                }
            }
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

        // Device items: show thumbnail first, then download (imatge → full-res;
        // vídeo → fitxer temporal per reproduir). No són fitxers locals, així que
        // AVPlayer/ImageIO no poden llegir-los directament del telèfon.
        if !item.isLocal {
            // Show thumbnail if available; keep previous image as fallback
            // so there's visual feedback during navigation
            if let thumb = item.thumbnail {
                viewerImage = thumb
            }
            updateViewerInfo(for: item)

            guard let cameraFile = item.cameraFile else {
                isViewingVideo = false
                viewerVideoURL = nil
                return
            }

            if item.isVideo {
                // Vídeo del dispositiu: el baixem a temp i el reproduïm des d'allà.
                // Mentre es baixa es veu la miniatura (la vista cau a viewerImage
                // perquè viewerVideoURL encara és nil).
                isViewingVideo = true
                viewerVideoRotation = item.videoRotation
                viewerVideoURL = nil
                statusMessage = "Baixant vídeo del dispositiu…"
                viewerDownloadTask = Task {
                    guard !Task.isCancelled else { return }
                    let localPath = await deviceService.downloadTempFile(cameraFile)
                    guard !Task.isCancelled, viewerCurrentItem == item else { return }
                    guard let localPath else {
                        statusMessage = "No s'ha pogut baixar el vídeo del dispositiu."
                        return
                    }
                    viewerVideoURL = URL(fileURLWithPath: localPath)
                    updateStatusMessage()
                    if item.videoRotation == 0 {
                        let rotation = await Task.detached(priority: .utility) {
                            FileService.getVideoRotation(filePath: localPath)
                        }.value
                        guard viewerCurrentItem == item else { return }
                        item.videoRotation = rotation
                        viewerVideoRotation = rotation
                    }
                }
                return
            }

            // Imatge del dispositiu
            isViewingVideo = false
            viewerVideoURL = nil
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
            return
        }

        if item.isVideo {
            isViewingVideo = true
            viewerVideoRotation = item.videoRotation
            viewerVideoURL = URL(fileURLWithPath: item.fullPath)
            viewerImage = item.thumbnail
            updateViewerInfo(for: item)

            // Llegir rotació en background per no bloquejar MainActor amb fitxers grans
            if item.videoRotation == 0 {
                let path = item.fullPath
                Task.detached(priority: .utility) { [weak self] in
                    let rotation = FileService.getVideoRotation(filePath: path)
                    await MainActor.run { [weak self] in
                        guard let self, self.viewerCurrentItem == item else { return }
                        item.videoRotation = rotation
                        self.viewerVideoRotation = rotation
                    }
                }
            }
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

        // 2.5. Quick preview (embedded JPEG for RAW/HEIC — near instant)
        if item.isRaw || item.fullPath.lowercased().hasSuffix(".heic") || item.fullPath.lowercased().hasSuffix(".heif") {
            let path = item.fullPath
            Task.detached(priority: .userInitiated) { [fileService] in
                if let preview = fileService.loadQuickPreview(at: path) {
                    await MainActor.run { [weak self] in
                        guard let self, self.viewerCurrentItem == item else { return }
                        // Only set if we haven't loaded the full image yet
                        if self.imageCache.get(path) == nil {
                            self.viewerImage = preview
                        }
                    }
                }
            }
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
            // Show path in status bar (useful for multi-folder duplicate identification)
            if item.isLocal {
                let dir = (item.fullPath as NSString).deletingLastPathComponent
                statusMessage = "\(item.fileName) — \(dir)"
            } else {
                statusMessage = item.fileName
            }
        } else {
            selectedPhotos.remove(item)
            updateStatusMessage()
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
        panel.title = "Selecciona carpeta destí per defecte"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            destinationFolder = url.path
            statusMessage = "Carpeta destí: \(url.path)"
        }
    }

    func clearDestinationFolder() {
        destinationFolder = nil
        statusMessage = "Carpeta destí esborrada."
    }

    /// Resolves the destination folder: returns the pre-set one if available,
    /// otherwise opens a folder picker. Returns nil if user cancels.
    private func resolveDestinationFolder(title: String = "Selecciona carpeta destí") -> String? {
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

        // Prioritat: si hi ha destí Mirat actiu, puja allà. Si no, carpeta local.
        if let mirat = activeMiratDestination {
            await uploadPhotosToMirat(Array(selectedPhotos), destination: mirat)
            return
        }

        guard let dest = resolveDestinationFolder(title: "Selecciona destí per copiar") else { return }

        await copyFiles(Array(selectedPhotos), to: dest)
    }

    func copyCurrentPhoto() async {
        guard let item = viewerCurrentItem else { return }

        if let mirat = activeMiratDestination {
            await uploadPhotosToMirat([item], destination: mirat)
            return
        }

        guard let dest = resolveDestinationFolder(title: "Selecciona destí per copiar") else { return }

        await copyFiles([item], to: dest)
    }

    private func copyFiles(_ files: [PhotoItem], to destination: String) async {
        isLoading = true
        isCopying = true
        hasError = false
        copyProgress = 0

        // Feedback immediat — el primer callback de progrés només arriba quan
        // s'està copiant el primer fitxer; abans, l'usuari no veia cap canvi.
        statusMessage = "Preparant còpia de \(files.count) fitxer(s) a \(destination)…"

        do {
            let copied = try await fileService.copyFiles(files, to: destination) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.copyProgress = Double(current) / Double(total) * 100
                    self?.statusMessage = "Copiant \(current)/\(total): \(fileName)"
                }
            }
            copyProgress = 100
            statusMessage = "\(copied) fitxer(s) copiats a \(destination)"
        } catch {
            hasError = true
            statusMessage = "Error copiant: \(error.localizedDescription)"
        }

        isCopying = false
        isLoading = false
    }

    func moveSelected() async {
        guard !selectedPhotos.isEmpty else { return }

        // Si hi ha destí Mirat actiu, "moure" = pujar + eliminar local (a la paperera,
        // reversible amb Cmd+Z gràcies a la infraestructura d'undo existent).
        if let mirat = activeMiratDestination {
            let filesToMove = Array(selectedPhotos)
            await uploadPhotosToMirat(filesToMove, destination: mirat)
            // Si l'upload ha anat amb errors, no eliminem (hasError queda a true).
            if !hasError {
                selectedPhotos = Set(filesToMove)
                await deleteSelected()
            }
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Select destination for move"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Confirm with the user
        let alert = NSAlert()
        alert.messageText = "Confirmar moviment"
        alert.informativeText = "Moure \(selectedPhotos.count) fitxer(s) a:\n\(url.path)\n\nAquesta acció no es pot desfer."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Moure")
        alert.addButton(withTitle: "Cancel·lar")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        isLoading = true
        isCopying = true
        hasError = false
        copyProgress = 0

        let filesToMove = Array(selectedPhotos)
        statusMessage = "Preparant moviment de \(filesToMove.count) fitxer(s) a \(url.path)…"

        do {
            let moved = try await fileService.moveFiles(filesToMove, to: url.path) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.copyProgress = Double(current) / Double(total) * 100
                    self?.statusMessage = "Movent \(current)/\(total): \(fileName)"
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

            statusMessage = "\(moved) fitxer(s) moguts a \(url.path)"
        } catch {
            hasError = true
            statusMessage = "Error movent: \(error.localizedDescription)"
        }

        isCopying = false
        isLoading = false
    }

    func deleteSelected() async {
        guard !selectedPhotos.isEmpty else { return }

        isLoading = true
        hasError = false

        let filesToDelete = Array(selectedPhotos)

        do {
            let result = try await fileService.deleteFiles(filesToDelete) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Eliminant \(current)/\(total): \(fileName)"
                }
            }

            let wasViewingDeletedItem = viewerCurrentItem.map { filesToDelete.contains($0) } ?? false
            let previousViewerIndex = viewerIndex

            for item in filesToDelete {
                allPhotos.removeAll { $0 == item }
                photos.removeAll { $0 == item }
                selectedPhotos.remove(item)
                // Reset isSelected a la instància: l'objecte continua viu
                // (lastDeletedItems el reté per a undo). Si l'usuari fa undo
                // i la foto torna, no volem que aparegui "fantasma seleccionada".
                item.isSelected = false
            }

            photoCount = allPhotos.filter { !$0.isVideo }.count
            videoCount = allPhotos.filter { $0.isVideo }.count

            // Guardar estat per undo (1 nivell — sobreescriu l'anterior)
            lastDeletedItems = filesToDelete
            lastDeletedTrashPairs = result.trashedPairs

            // Si el visor estava obert, avançar a la següent foto (o tancar si no en queden)
            if wasViewingDeletedItem {
                if photos.isEmpty {
                    closeViewer()
                } else {
                    let newIndex = min(previousViewerIndex, photos.count - 1)
                    navigateViewer(to: newIndex)
                }
            }

            statusMessage = "\(result.deleted) fitxer(s) moguts a la paperera — Cmd+Z per desfer"
        } catch {
            hasError = true
            statusMessage = "Error eliminant: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Paperera del VISOR: elimina NOMÉS la foto actual del visor, sense tocar la
    /// selecció (les fotos seleccionades es mantenen seleccionades). Per eliminar la
    /// selecció s'usa la paperera de la galeria (`deleteSelected`).
    func deleteCurrentViewerPhoto() async {
        guard let item = viewerCurrentItem else { return }

        isLoading = true
        hasError = false

        let filesToDelete = [item]

        do {
            let result = try await fileService.deleteFiles(filesToDelete) { [weak self] current, total, fileName in
                Task { @MainActor [weak self] in
                    self?.statusMessage = "Eliminant \(current)/\(total): \(fileName)"
                }
            }

            let previousViewerIndex = viewerIndex

            allPhotos.removeAll { $0 == item }
            photos.removeAll { $0 == item }
            // Només treu de la selecció la foto eliminada (ja no existeix); la resta
            // de fotos seleccionades es manté intacta.
            selectedPhotos.remove(item)
            item.isSelected = false

            photoCount = allPhotos.filter { !$0.isVideo }.count
            videoCount = allPhotos.filter { $0.isVideo }.count

            // Guardar estat per undo (1 nivell — sobreescriu l'anterior)
            lastDeletedItems = filesToDelete
            lastDeletedTrashPairs = result.trashedPairs

            // Avançar a la següent foto del visor (o tancar si no en queden)
            if photos.isEmpty {
                closeViewer()
            } else {
                let newIndex = min(previousViewerIndex, photos.count - 1)
                navigateViewer(to: newIndex)
            }

            statusMessage = "\(result.deleted) fitxer(s) moguts a la paperera — Cmd+Z per desfer"
        } catch {
            hasError = true
            statusMessage = "Error eliminant: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Tanca el toast d'undo sense restaurar res.
    func dismissUndoToast() {
        lastDeletedItems = []
        lastDeletedTrashPairs = []
    }

    /// Desfà l'última eliminació: restaura els fitxers de la paperera a la ubicació original
    /// i els re-insereix a la llista. Només 1 nivell.
    func undoLastDelete() async {
        guard !lastDeletedItems.isEmpty else {
            statusMessage = "No hi ha res per desfer."
            return
        }

        let items = lastDeletedItems
        let pairs = lastDeletedTrashPairs

        // Buidar estat d'undo immediatament per evitar dobles execucions
        lastDeletedItems = []
        lastDeletedTrashPairs = []

        isLoading = true
        hasError = false

        var restored = 0
        var failed = 0

        for pair in pairs {
            do {
                try await fileService.restoreFromTrash(trashURL: pair.trashURL, originalPath: pair.originalPath)
                if let item = items.first(where: { $0.fullPath == pair.originalPath }) {
                    allPhotos.append(item)
                    restored += 1
                }
            } catch {
                failed += 1
            }
        }

        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        applyFilter()

        if failed > 0 {
            hasError = true
            statusMessage = "Restaurats \(restored), errors \(failed)."
        } else {
            statusMessage = "Desfet: \(restored) fitxer(s) restaurats."
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
        isLoading = true
        do {
            let items = try await deviceService.browseDevice()
            guard !items.isEmpty else { isLoading = false; return }

            // Save current local state
            savedLocalPhotos = allPhotos
            savedOpenFolders = openFolders
            savedCurrentFolder = currentFolderPath

            // Enter browse mode
            isDeviceBrowseMode = true
            hasScannedDeviceDuplicates = false  // nova sessió: encara no s'han escanejat duplicats
            closeViewer()
            openFolders.removeAll()
            currentFolderPath = nil

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

            isLoading = false

            // Thumbnails: càrrega MANDROSA per cel·la (.task a la graella). L'escaneig
            // de duplicats és SOTA DEMANDA (s'activa amb el filtre de duplicats), NO
            // automàtic en obrir → no carrega 35k miniatures només navegant.
        } catch {
            isLoading = false
            deviceService.statusMessage = "Error de navegació: \(error.localizedDescription)"
        }
    }

    private func loadDeviceThumbnails() {
        // Cancel·la qualsevol càrrega en marxa per prioritzar les fotos actuals.
        thumbnailTask?.cancel()

        let visiblePhotos = photos  // Prioritat: filtrades/visibles primer
        let allItems = allPhotos
        thumbnailTask = Task { [weak self] in
            guard let self else { return }
            // Concurrent (abans era en SÈRIE → amb 35k fotos trigava una eternitat).
            await self.loadThumbnailsConcurrently(visiblePhotos)  // visibles primer
            await self.loadThumbnailsConcurrently(allItems)        // la resta (per a l'escaneig)
            self.thumbnailTask = nil
        }
    }

    /// Carrega thumbnails de `items` amb un màxim de `maxConcurrent` peticions
    /// simultànies al dispositiu (ImageCaptureCore es satura amb massa alhora).
    private func loadThumbnailsConcurrently(_ items: [PhotoItem], maxConcurrent: Int = 6) async {
        await withTaskGroup(of: Void.self) { group in
            var index = 0
            while index < maxConcurrent, index < items.count {
                let photo = items[index]; index += 1
                group.addTask { [weak self] in await self?.loadDeviceThumbnailIfNeeded(for: photo) }
            }
            while await group.next() != nil {
                if Task.isCancelled { group.cancelAll(); break }
                guard index < items.count else { continue }
                let photo = items[index]; index += 1
                group.addTask { [weak self] in await self?.loadDeviceThumbnailIfNeeded(for: photo) }
            }
        }
    }

    /// Demana el thumbnail d'una foto del dispositiu si encara no el té. Deduplicat:
    /// la graella mandrosa (per cel·la visible) i la càrrega de fons no el demanen
    /// dues vegades. La crida la graella a `.task` de cada cel·la i la càrrega de fons.
    func loadDeviceThumbnailIfNeeded(for photo: PhotoItem) async {
        guard photo.thumbnail == nil, let cameraFile = photo.cameraFile,
              !loadingThumbIds.contains(photo.id) else { return }
        loadingThumbIds.insert(photo.id)
        let thumb = await deviceService.requestThumbnail(for: cameraFile)
        loadingThumbIds.remove(photo.id)
        if let thumb { photo.thumbnail = thumb }
    }

    /// Scans device photos for duplicates using perceptual hash on thumbnails.
    /// Waits for thumbnails to load, then computes hashes.
    /// Engega l'escaneig de duplicats del dispositiu NOMÉS quan cal: en activar un
    /// filtre de duplicats en mode browse i si encara no s'ha fet en aquesta sessió.
    private func scanDeviceDuplicatesIfNeeded() {
        guard isDeviceBrowseMode, !hasScannedDeviceDuplicates,
              filterExactDuplicates || filterSimilarDuplicates else { return }
        hasScannedDeviceDuplicates = true
        scanDeviceDuplicates()
    }

    private func scanDeviceDuplicates() {
        duplicateScanTask?.cancel()
        isScanningExact = true
        isScanningSimilar = true
        exactDuplicateCount = 0
        similarDuplicateCount = 0

        let items = allPhotos  // Scan ALL photos, not just filtered

        // SOTA DEMANDA: carrega ARA totes les miniatures (necessàries per al hash
        // perceptual). Abans es carregaven sempre en navegar; ara, només en escanejar.
        loadDeviceThumbnails()

        duplicateScanTask = Task {
            // Wait for thumbnails to be loaded (poll every 2s, max 60s)
            for _ in 0..<30 {
                if Task.isCancelled { return }
                let loaded = items.filter { $0.thumbnail != nil }.count
                if loaded >= items.count / 3 { break } // at least a third loaded
                try? await Task.sleep(for: .seconds(2))
            }

            // Compute perceptual hash from thumbnails
            for item in items {
                if Task.isCancelled { return }
                guard let thumb = item.thumbnail else { continue }
                let hash = FileService.computePerceptualHashFromImage(thumb)
                await MainActor.run { item.perceptualHash = hash }
            }

            // Also group by file size for exact matches (same sizeBytes = likely same file)
            var sizeGroups: [Int64: [PhotoItem]] = [:]
            for item in items {
                sizeGroups[item.sizeBytes, default: []].append(item)
            }

            var markedItems = Set<String>()

            // Exact duplicates by size (good proxy on device where we can't compute MD5)
            for (_, group) in sizeGroups where group.count > 1 {
                // Also check perceptual hash to confirm
                let withHash = group.filter { $0.perceptualHash != nil }
                guard withHash.count > 1 else { continue }

                for i in 0..<withHash.count {
                    guard let hashA = withHash[i].perceptualHash else { continue }
                    for j in (i+1)..<withHash.count {
                        guard let hashB = withHash[j].perceptualHash else { continue }
                        if FileService.hammingDistance(hashA, hashB) == 0 {
                            let groupId = "md5-size\(withHash[i].sizeBytes)"
                            await MainActor.run {
                                withHash[i].duplicateGroupId = groupId
                                withHash[j].duplicateGroupId = groupId
                                markedItems.insert(withHash[i].id)
                                markedItems.insert(withHash[j].id)
                            }
                        }
                    }
                }
            }

            // Propagate thumbnails within exact duplicate groups:
            // if one item has a thumbnail and its duplicate doesn't, share it
            await MainActor.run {
                var exactGroups: [String: [PhotoItem]] = [:]
                for item in items where item.duplicateGroupId?.hasPrefix("md5-") == true {
                    exactGroups[item.duplicateGroupId!, default: []].append(item)
                }
                for (_, group) in exactGroups {
                    if let donor = group.first(where: { $0.thumbnail != nil }) {
                        for item in group where item.thumbnail == nil {
                            item.thumbnail = donor.thumbnail
                        }
                    }
                }
                self.exactDuplicateCount = self.allPhotos.filter { $0.duplicateGroupId?.hasPrefix("md5-") == true }.count
                self.isScanningExact = false
            }

            // Similar duplicates (Hamming distance ≤ 5)
            let withPHash = items.filter { $0.perceptualHash != nil && !markedItems.contains($0.id) }
            var pHashProcessed = Set<String>()

            for i in 0..<withPHash.count {
                if Task.isCancelled { return }
                let itemA = withPHash[i]
                guard !pHashProcessed.contains(itemA.id),
                      let hashA = itemA.perceptualHash else { continue }

                var group: [PhotoItem] = [itemA]

                for j in (i+1)..<withPHash.count {
                    let itemB = withPHash[j]
                    guard !pHashProcessed.contains(itemB.id),
                          let hashB = itemB.perceptualHash else { continue }

                    if FileService.hammingDistance(hashA, hashB) <= 5 {
                        group.append(itemB)
                    }
                }

                if group.count > 1 {
                    let groupId = "phash-\(String(hashA, radix: 16).prefix(12))"
                    await MainActor.run {
                        for item in group {
                            item.duplicateGroupId = groupId
                            pHashProcessed.insert(item.id)
                        }
                        self.similarDuplicateCount = self.allPhotos.filter { $0.duplicateGroupId?.hasPrefix("phash-") == true }.count
                    }
                }
            }

            // Final counts
            await MainActor.run {
                self.exactDuplicateCount = self.allPhotos.filter { $0.duplicateGroupId?.hasPrefix("md5-") == true }.count
                self.similarDuplicateCount = self.allPhotos.filter { $0.duplicateGroupId?.hasPrefix("phash-") == true }.count
                self.isScanningExact = false
                self.isScanningSimilar = false
                if self.filterExactDuplicates || self.filterSimilarDuplicates {
                    self.applyFilter()
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

        guard let dest = resolveDestinationFolder(title: "Selecciona destí per importar") else { return }

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

        let wasViewingDeletedItem = viewerCurrentItem.map { selected.contains($0) } ?? false
        let previousViewerIndex = viewerIndex

        // Remove deleted items from the master list and re-apply filter (which re-sorts)
        for item in selected {
            allPhotos.removeAll { $0 == item }
            selectedPhotos.remove(item)
        }
        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        applyFilter()

        // Si el visor estava obert, avançar a la següent foto (o tancar si no en queden)
        if wasViewingDeletedItem {
            if photos.isEmpty {
                closeViewer()
            } else {
                let newIndex = min(previousViewerIndex, photos.count - 1)
                navigateViewer(to: newIndex)
            }
        }

        statusMessage = "\(files.count) fitxer(s) eliminat(s). \(allPhotos.count) restants al dispositiu."
    }

    /// Paperera del VISOR en mode dispositiu: elimina NOMÉS la foto actual del visor,
    /// sense tocar la selecció.
    func deleteCurrentViewerFromDevice() async {
        guard let item = viewerCurrentItem, let file = item.cameraFile else { return }

        let alert = NSAlert()
        alert.messageText = "Eliminar del dispositiu"
        alert.informativeText = "Eliminar permanentment «\(item.fileName)» de \(deviceService.selectedDevice?.name ?? "dispositiu")?\n\nAquesta acció no es pot desfer."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Eliminar")
        alert.addButton(withTitle: "Cancel·lar")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        await deviceService.deleteFiles([file])

        let previousViewerIndex = viewerIndex

        allPhotos.removeAll { $0 == item }
        selectedPhotos.remove(item)
        item.isSelected = false
        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count
        applyFilter()

        if photos.isEmpty {
            closeViewer()
        } else {
            let newIndex = min(previousViewerIndex, photos.count - 1)
            navigateViewer(to: newIndex)
        }

        statusMessage = "1 fitxer eliminat. \(allPhotos.count) restants al dispositiu."
    }

    func exitDeviceBrowseMode() {
        guard isDeviceBrowseMode else { return }

        thumbnailTask?.cancel()
        deviceLocationTask?.cancel()
        closeViewer()
        deviceService.closeSession()
        deviceService.onDeviceDisconnected = nil
        deviceService.selectedDevice = nil
        deviceService.clearDevices()
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
        hasScannedDeviceDuplicates = false

        // Cancel any device duplicate scan
        duplicateScanTask?.cancel()
        isScanningExact = false
        isScanningSimilar = false

        photoCount = allPhotos.filter { !$0.isVideo }.count
        videoCount = allPhotos.filter { $0.isVideo }.count

        // Recalculate duplicate counts from restored local photos
        exactDuplicateCount = allPhotos.filter { $0.duplicateGroupId?.hasPrefix("md5-") == true }.count
        similarDuplicateCount = allPhotos.filter {
            $0.duplicateGroupId?.hasPrefix("phash-") == true || $0.duplicateGroupId?.hasPrefix("exif-") == true
        }.count

        applyFilter()
        updateStatusMessage()
    }
}
