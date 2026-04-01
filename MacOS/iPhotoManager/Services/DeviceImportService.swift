import Foundation
import AppKit
import ImageCaptureCore
import os.log

private let logger = Logger(subsystem: "com.iphotomanager", category: "import")

private func logToFile(_ msg: String) {
    let path = NSHomeDirectory() + "/iphoto_import.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// Real device import service using ImageCaptureCore framework.
/// Detects connected iPhones and cameras via USB and imports photos/videos.
@MainActor
@Observable
final class DeviceImportService: NSObject {

    // MARK: - State

    var devices: [DeviceInfo] = []
    var selectedDevice: DeviceInfo?
    var isScanning: Bool = false
    var statusMessage: String = "Connecta un iPhone o càmera per USB."
    var importProgress: Double = 0
    var isImporting: Bool = false
    var isBrowsing: Bool = false
    var browseProgress: Double = 0  // 0-100, progress of file enumeration
    var browseTotalFiles: Int = 0

    /// Callback when device disconnects during browse mode.
    var onDeviceDisconnected: (() -> Void)?

    // MARK: - Types

    struct DeviceInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let type: DeviceType
        let icDevice: ICCameraDevice

        enum DeviceType: String {
            case iPhone = "iPhone"
            case camera = "Camera"
            case unknown = "Unknown"
        }

        static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    // MARK: - Private

    private var browser: ICDeviceBrowser?
    private var downloadedCount = 0
    private var totalToDownload = 0
    private var downloadContinuation: CheckedContinuation<Void, Never>?
    private var tempDownloadContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var sessionContinuation: CheckedContinuation<Bool, Never>?
    private var thumbnailContinuations: [String: CheckedContinuation<CGImage?, Never>] = [:]
    private var deleteContinuation: CheckedContinuation<Void, Never>?
    private var metadataContinuations: [String: CheckedContinuation<[AnyHashable: Any]?, Never>] = [:]
    private var catalogContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Device Detection

    func detectDevices() async {
        isScanning = true
        statusMessage = "Cercant dispositius..."
        devices = []
        selectedDevice = nil

        if browser == nil {
            browser = ICDeviceBrowser()
            browser?.delegate = self
            browser?.start()
            // First time: wait longer for browser to initialize
            try? await Task.sleep(for: .seconds(3))
        } else {
            // Browser already running — re-enumerate known devices
            if let knownDevices = browser?.devices {
                for device in knownDevices {
                    if let cameraDevice = device as? ICCameraDevice {
                        let name = device.name ?? "Unknown"
                        let type: DeviceInfo.DeviceType
                        if name.lowercased().contains("iphone") || name.lowercased().contains("ipad") {
                            type = .iPhone
                        } else if device.type == .camera {
                            type = .camera
                        } else {
                            type = .unknown
                        }
                        let info = DeviceInfo(
                            id: device.uuidString ?? UUID().uuidString,
                            name: name,
                            type: type,
                            icDevice: cameraDevice
                        )
                        cameraDevice.delegate = self
                        if !devices.contains(where: { $0.id == info.id }) {
                            devices.append(info)
                        }
                    }
                }
            }
            // Short wait in case new devices appear
            try? await Task.sleep(for: .seconds(1))
        }

        isScanning = false

        // Final dedup by name (race conditions from didAdd callbacks during sleep)
        var seenNames = Set<String>()
        devices = devices.filter { seenNames.insert($0.name).inserted }

        if devices.isEmpty {
            statusMessage = "No s'han trobat dispositius. Assegura't que l'iPhone està desbloquejat i connectat per USB."
        } else {
            statusMessage = "\(devices.count) dispositiu(s) trobat(s)."
        }
    }

    /// Imports photos from the selected device.
    func importPhotos(
        to destination: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> Int {
        guard let device = selectedDevice else {
            throw DeviceImportError.noDeviceSelected
        }

        let icDevice = device.icDevice
        isImporting = true
        importProgress = 0
        statusMessage = "Connectant amb \(device.name)..."

        // Open session
        icDevice.delegate = self
        logToFile("[Import] Requesting open session for \(device.name)...")

        let opened = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionContinuation = cont
            icDevice.requestOpenSession()
        }
        logToFile("[Import] Session opened: \(opened)")

        guard opened else {
            isImporting = false
            throw DeviceImportError.importFailed("No s'ha pogut obrir la sessió. Assegura't que l'iPhone està desbloquejat i has premut 'Confiar'.")
        }

        // Wait for file enumeration
        statusMessage = "Llegint fitxers de \(device.name)..."
        try? await Task.sleep(for: .seconds(3))

        // Collect media files
        let files = collectMediaFilesAsync(from: icDevice)

        if files.isEmpty {
            try? await icDevice.requestCloseSession()
            isImporting = false
            statusMessage = "No s'han trobat fotos ni vídeos al dispositiu."
            return 0
        }

        totalToDownload = files.count
        downloadedCount = 0
        statusMessage = "Importing \(totalToDownload) files..."

        // Create destination
        try? FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

        let destURL = URL(fileURLWithPath: destination)
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destURL,
            .overwrite: false,
        ]

        // Download each file
        for file in files {
            downloadedCount += 1
            let fileName = file.name ?? "unknown"
            statusMessage = "Importat \(downloadedCount)/\(totalToDownload): \(fileName)"
            importProgress = Double(downloadedCount) / Double(totalToDownload) * 100

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.downloadContinuation = cont
                icDevice.requestDownloadFile(
                    file,
                    options: options,
                    downloadDelegate: self,
                    didDownloadSelector: #selector(handleDownloadComplete(_:error:options:contextInfo:)),
                    contextInfo: nil
                )

                // Timeout per file: 30 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    if let self, let pending = self.downloadContinuation {
                        self.downloadContinuation = nil
                        logToFile("[Import] Download TIMEOUT for \(fileName)")
                        pending.resume()
                    }
                }
            }

            progress(downloadedCount, totalToDownload, fileName)
        }

        try? await icDevice.requestCloseSession()
        isImporting = false
        importProgress = 100
        statusMessage = "\(downloadedCount) fitxer(s) importat(s)."

        return downloadedCount
    }

    // MARK: - Browse Device

    /// Opens a session, enumerates media files and returns PhotoItems without downloading.
    func browseDevice() async throws -> [PhotoItem] {
        guard let device = selectedDevice else {
            throw DeviceImportError.noDeviceSelected
        }

        let icDevice = device.icDevice
        isBrowsing = true
        statusMessage = "Connectant amb \(device.name)..."

        icDevice.delegate = self

        // Retry up to 3 times — first attempt often fails while device initializes
        var opened = false
        for attempt in 1...3 {
            logToFile("[Browse] Open session attempt \(attempt) for \(device.name)...")
            statusMessage = "Connectant amb \(device.name)... (intent \(attempt))"

            opened = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                sessionContinuation = cont
                icDevice.requestOpenSession()
            }
            logToFile("[Browse] Attempt \(attempt) result: \(opened)")

            if opened { break }
            try? await Task.sleep(for: .seconds(2))
        }

        guard opened else {
            isBrowsing = false
            throw DeviceImportError.importFailed("No s'ha pogut obrir la sessió. Assegura't que l'iPhone està desbloquejat i has premut 'Confiar'.")
        }

        statusMessage = "Llegint fitxers de \(device.name)..."

        // Wait for device to enumerate all files (catalog ready)
        // Poll device.mediaFiles with timeout — simpler and more reliable than continuation
        var catalogReady = false
        for attempt in 1...15 {
            logToFile("[Browse] Waiting for catalog... attempt \(attempt)")
            try? await Task.sleep(for: .seconds(1))
            if let mediaFiles = icDevice.mediaFiles, !mediaFiles.isEmpty {
                catalogReady = true
                logToFile("[Browse] Catalog ready with \(mediaFiles.count) items")
                break
            }
        }

        if !catalogReady {
            logToFile("[Browse] Catalog timeout — trying anyway")
        }

        // Enumerate files on background thread to avoid blocking UI
        statusMessage = "Processant fitxers de \(device.name)..."
        let capturedDevice = icDevice
        let allExts = PhotoItem.allExtensions
        let deviceId = device.id

        let items: [PhotoItem] = await Task.detached {
            guard let mediaFiles = capturedDevice.mediaFiles else { return [] }
            var results: [PhotoItem] = []
            for item in mediaFiles {
                if let file = item as? ICCameraFile {
                    let ext = (file.name ?? "").split(separator: ".").last?.lowercased() ?? ""
                    if allExts.contains(String(ext)) {
                        results.append(PhotoItem(cameraFile: file, deviceId: deviceId))
                    }
                }
            }
            return results
        }.value

        if items.isEmpty {
            isBrowsing = false
            statusMessage = "No s'han trobat fotos ni vídeos al dispositiu."
            return []
        }

        statusMessage = "\(items.count) fitxers trobats a \(device.name). Selecciona les fotos a importar."
        return items
    }

    /// Requests a thumbnail from the device for a camera file.
    func requestThumbnail(for file: ICCameraFile) async -> NSImage? {
        // Check if thumbnail is already available on the item
        if let thumb = file.thumbnail {
            return NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height))
        }

        let key = file.name ?? UUID().uuidString
        let cgImage: CGImage? = await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            thumbnailContinuations[key] = cont
            file.requestThumbnail()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                if let self, let pending = self.thumbnailContinuations.removeValue(forKey: key) {
                    pending.resume(returning: nil)
                }
            }
        }

        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Requests GPS coordinates from device file metadata.
    func requestGPSLocation(for file: ICCameraFile) async -> (latitude: Double, longitude: Double)? {
        let key = "meta_\(file.name ?? UUID().uuidString)"
        let metadata: [AnyHashable: Any]? = await withCheckedContinuation { (cont: CheckedContinuation<[AnyHashable: Any]?, Never>) in
            metadataContinuations[key] = cont
            file.requestMetadata()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                if let self, let pending = self.metadataContinuations.removeValue(forKey: key) {
                    pending.resume(returning: nil)
                }
            }
        }

        guard let metadata,
              let gps = metadata["{GPS}"] as? [String: Any] ?? metadata["GPS"] as? [String: Any],
              let lat = gps["Latitude"] as? Double,
              let lon = gps["Longitude"] as? Double else { return nil }
        let latRef = gps["LatitudeRef"] as? String ?? "N"
        let lonRef = gps["LongitudeRef"] as? String ?? "E"
        return (latRef == "S" ? -lat : lat, lonRef == "W" ? -lon : lon)
    }

    /// Imports only the specified files to a destination folder.
    func importSelectedFiles(
        _ files: [ICCameraFile],
        to destination: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async -> Int {
        guard let device = selectedDevice else { return 0 }
        let icDevice = device.icDevice

        isImporting = true
        importProgress = 0
        totalToDownload = files.count
        downloadedCount = 0

        try? FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
        let destURL = URL(fileURLWithPath: destination)
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destURL,
            .overwrite: false,
        ]

        for file in files {
            downloadedCount += 1
            let fileName = file.name ?? "unknown"
            statusMessage = "Importat \(downloadedCount)/\(totalToDownload): \(fileName)"
            importProgress = Double(downloadedCount) / Double(totalToDownload) * 100

            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.downloadContinuation = cont
                icDevice.requestDownloadFile(
                    file,
                    options: options,
                    downloadDelegate: self,
                    didDownloadSelector: #selector(handleDownloadComplete(_:error:options:contextInfo:)),
                    contextInfo: nil
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    if let self, let pending = self.downloadContinuation {
                        self.downloadContinuation = nil
                        pending.resume()
                    }
                }
            }
            progress(downloadedCount, totalToDownload, fileName)
        }

        isImporting = false
        importProgress = 100
        statusMessage = "\(downloadedCount) fitxer(s) importat(s)."
        return downloadedCount
    }

    /// Deletes specified files from the device.
    func deleteFiles(_ files: [ICCameraFile]) async {
        guard let device = selectedDevice else { return }
        let icDevice = device.icDevice

        isImporting = true
        statusMessage = "Eliminant \(files.count) fitxer(s) de \(device.name)..."

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.deleteContinuation = cont
            icDevice.requestDeleteFiles(files)
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(files.count) * 5 + 10) { [weak self] in
                if let self, let pending = self.deleteContinuation {
                    self.deleteContinuation = nil
                    pending.resume()
                }
            }
        }

        isImporting = false
        statusMessage = "\(files.count) fitxer(s) eliminat(s) del dispositiu."
    }

    /// Downloads a single file to a temp directory and returns the local path.
    /// Used to show full-resolution images from device in browse mode.
    /// Uses per-file continuations so concurrent downloads don't interfere.
    func downloadTempFile(_ file: ICCameraFile) async -> String? {
        guard let device = selectedDevice else { return nil }
        let icDevice = device.icDevice

        let tempDir = NSTemporaryDirectory() + "iPhotoManager/"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        let destURL = URL(fileURLWithPath: tempDir)
        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: destURL,
            .overwrite: true,
        ]

        let key = file.name ?? UUID().uuidString

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            tempDownloadContinuations[key] = cont
            icDevice.requestDownloadFile(
                file,
                options: options,
                downloadDelegate: self,
                didDownloadSelector: #selector(handleDownloadComplete(_:error:options:contextInfo:)),
                contextInfo: nil
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                if let self, let pending = self.tempDownloadContinuations.removeValue(forKey: key) {
                    pending.resume()
                }
            }
        }

        let fileName = file.name ?? "unknown"
        let filePath = tempDir + fileName
        if FileManager.default.fileExists(atPath: filePath) {
            return filePath
        }
        return nil
    }

    /// Closes the active device session.
    func closeSession() {
        guard let device = selectedDevice else { return }
        let icDevice = device.icDevice
        if icDevice.hasOpenSession {
            icDevice.requestCloseSession()
        }
        isBrowsing = false
    }

    // MARK: - Download callback

    @objc private func handleDownloadComplete(
        _ file: ICCameraFile,
        error: Error?,
        options: [String: Any]?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            // Check if this is a temp download (browse mode viewer)
            let key = file.name ?? ""
            if let cont = tempDownloadContinuations.removeValue(forKey: key) {
                cont.resume()
            } else {
                // Import download (sequential)
                downloadContinuation?.resume()
                downloadContinuation = nil
            }
        }
    }

    // MARK: - Helpers

    private func collectMediaFilesAsync(from device: ICCameraDevice) -> [ICCameraFile] {
        let allExts = PhotoItem.allExtensions

        var files: [ICCameraFile] = []
        guard let mediaFiles = device.mediaFiles else { return files }

        let total = mediaFiles.count
        browseTotalFiles = total
        browseProgress = 0
        statusMessage = "Llegint fitxers... 0/\(total)"

        for (index, item) in mediaFiles.enumerated() {
            if let file = item as? ICCameraFile {
                let ext = (file.name ?? "").split(separator: ".").last?.lowercased() ?? ""
                if allExts.contains(String(ext)) {
                    files.append(file)
                }
            }
            if index % 500 == 0 && total > 0 {
                browseProgress = Double(index) / Double(total) * 100
                statusMessage = "Llegint fitxers... \(index)/\(total) (\(files.count) compatibles)"
            }
        }

        browseProgress = 100
        statusMessage = "\(files.count) fitxers trobats de \(total) al dispositiu."
        return files
    }
}

// MARK: - ICDeviceBrowserDelegate

extension DeviceImportService: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        Task { @MainActor in
            guard let cameraDevice = device as? ICCameraDevice else { return }

            // Set delegate early so session events are captured
            cameraDevice.delegate = self

            let type: DeviceInfo.DeviceType
            let name = device.name ?? "Unknown"
            let serial = device.serialNumberString ?? ""
            logToFile("[Device] Detected: '\(name)' uuid=\(device.uuidString ?? "nil") serial=\(serial) type=\(device.type.rawValue)")

            if name.lowercased().contains("iphone") || name.lowercased().contains("ipad") {
                type = .iPhone
            } else if device.type == .camera {
                type = .camera
            } else {
                type = .unknown
            }

            let info = DeviceInfo(
                id: device.uuidString ?? UUID().uuidString,
                name: name,
                type: type,
                icDevice: cameraDevice
            )

            // Strict dedup: always rebuild list without duplicates by name
            // Remove any existing device with same name (replace with newer)
            devices.removeAll(where: { $0.name == info.name })
            devices.append(info)
            logToFile("[Device] Set: '\(name)' (total: \(devices.count))")
            statusMessage = "\(devices.count) dispositiu(s) trobat(s)."
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor in
            devices.removeAll { $0.id == (device.uuidString ?? "") }
        }
    }
}

// MARK: - ICCameraDeviceDownloadDelegate

extension DeviceImportService: ICCameraDeviceDownloadDelegate {}

// MARK: - ICCameraDeviceDelegate

extension DeviceImportService: ICCameraDeviceDelegate {
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {
        Task { @MainActor in
            let key = item.name ?? ""
            if let cont = thumbnailContinuations.removeValue(forKey: key) {
                cont.resume(returning: thumbnail)
            }
        }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: (any Error)?) {
        Task { @MainActor in
            deleteContinuation?.resume()
            deleteContinuation = nil
        }
    }
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable : Any]?, for item: ICCameraItem, error: (any Error)?) {
        Task { @MainActor in
            let key = "meta_\(item.name ?? "")"
            if let cont = metadataContinuations.removeValue(forKey: key) {
                cont.resume(returning: metadata)
            }
        }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        logToFile("[Import] Content catalog ready for \(device.name ?? "unknown")")
        Task { @MainActor in
            catalogContinuation?.resume()
            catalogContinuation = nil
        }
    }
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
}

// MARK: - ICDeviceDelegate

extension DeviceImportService: ICDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error {
            logToFile("[Import] Open session ERROR: \(error.localizedDescription)")
        } else {
            logToFile("[Import] Open session SUCCESS")
        }
        Task { @MainActor in
            sessionContinuation?.resume(returning: error == nil)
            sessionContinuation = nil
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {}
    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            let removedId = device.uuidString ?? ""
            let wasBrowsing = isBrowsing && selectedDevice?.id == removedId
            devices.removeAll { $0.id == removedId }
            if wasBrowsing {
                isBrowsing = false
                onDeviceDisconnected?()
            }
        }
    }
}

// MARK: - Errors

enum DeviceImportError: LocalizedError {
    case noDeviceSelected
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected: return "No device selected."
        case .importFailed(let msg): return "Import failed: \(msg)"
        }
    }
}
