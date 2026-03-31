import Foundation
import AppKit
import ImageCaptureCore

/// Real device import service using ImageCaptureCore framework.
/// Detects connected iPhones and cameras via USB and imports photos/videos.
@MainActor
@Observable
final class DeviceImportService: NSObject {

    // MARK: - State

    var devices: [DeviceInfo] = []
    var selectedDevice: DeviceInfo?
    var isScanning: Bool = false
    var statusMessage: String = "Connect an iPhone or camera via USB."
    var importProgress: Double = 0
    var isImporting: Bool = false

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
    private var sessionContinuation: CheckedContinuation<Bool, Never>?

    // MARK: - Device Detection

    func detectDevices() async {
        isScanning = true
        statusMessage = "Scanning for devices..."
        devices = []
        selectedDevice = nil

        if browser == nil {
            browser = ICDeviceBrowser()
            browser?.delegate = self
        }
        browser?.start()

        // Wait for devices to appear
        try? await Task.sleep(for: .seconds(3))

        browser?.stop()
        isScanning = false

        if devices.isEmpty {
            statusMessage = "No devices detected. Make sure your iPhone is unlocked and connected via USB."
        } else {
            statusMessage = "\(devices.count) device(s) found."
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
        statusMessage = "Connecting to \(device.name)..."

        // Open session
        icDevice.delegate = self
        let opened = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sessionContinuation = cont
            icDevice.requestOpenSession()
        }

        guard opened else {
            isImporting = false
            throw DeviceImportError.importFailed("Could not open device session.")
        }

        // Wait for file enumeration
        statusMessage = "Reading files from \(device.name)..."
        try? await Task.sleep(for: .seconds(3))

        // Collect media files
        let files = collectMediaFiles(from: icDevice)

        if files.isEmpty {
            try? await icDevice.requestCloseSession()
            isImporting = false
            statusMessage = "No photos or videos found on device."
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
            statusMessage = "Importing \(downloadedCount)/\(totalToDownload): \(fileName)"
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
            }

            progress(downloadedCount, totalToDownload, fileName)
        }

        try? await icDevice.requestCloseSession()
        isImporting = false
        importProgress = 100
        statusMessage = "\(downloadedCount) file(s) imported."

        return downloadedCount
    }

    // MARK: - Download callback

    @objc private func handleDownloadComplete(
        _ file: ICCameraFile,
        error: Error?,
        options: [String: Any]?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        Task { @MainActor in
            downloadContinuation?.resume()
            downloadContinuation = nil
        }
    }

    // MARK: - Helpers

    private func collectMediaFiles(from device: ICCameraDevice) -> [ICCameraFile] {
        let photoExts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "bmp", "gif", "tiff", "tif"]
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v"]
        let allExts = photoExts.union(videoExts)

        var files: [ICCameraFile] = []
        if let mediaFiles = device.mediaFiles {
            for item in mediaFiles {
                if let file = item as? ICCameraFile {
                    let ext = (file.name ?? "").split(separator: ".").last?.lowercased() ?? ""
                    if allExts.contains(String(ext)) {
                        files.append(file)
                    }
                }
            }
        }
        return files
    }
}

// MARK: - ICDeviceBrowserDelegate

extension DeviceImportService: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        Task { @MainActor in
            guard let cameraDevice = device as? ICCameraDevice else { return }

            let type: DeviceInfo.DeviceType
            let name = device.name ?? "Unknown"
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

            if !devices.contains(where: { $0.id == info.id }) {
                devices.append(info)
                statusMessage = "\(devices.count) device(s) found."
            }
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

// MARK: - ICDeviceDelegate

extension DeviceImportService: ICDeviceDelegate {
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        Task { @MainActor in
            sessionContinuation?.resume(returning: error == nil)
            sessionContinuation = nil
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {}
    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in
            devices.removeAll { $0.id == (device.uuidString ?? "") }
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
