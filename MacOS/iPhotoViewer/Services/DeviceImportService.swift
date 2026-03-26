import Foundation
import AppKit

/// Placeholder service for device import on macOS.
///
/// On macOS, iPhone photo import works differently from Windows MTP:
/// - macOS uses ImageCaptureCore framework (ICDeviceBrowser, ICCameraDevice)
/// - Photos can also be accessed via Apple Photos framework
/// - USB communication uses IOKit instead of WPD/MTP
///
/// This service provides the interface and placeholder implementation.
/// Full ImageCaptureCore integration can be added when needed.
@Observable
final class DeviceImportService {

    // MARK: - State

    var devices: [DeviceInfo] = []
    var selectedDevice: DeviceInfo?
    var isScanning: Bool = false
    var statusMessage: String = "Connect an iPhone or camera via USB."

    // MARK: - Types

    struct DeviceInfo: Identifiable, Hashable {
        let id: String
        let name: String
        let type: DeviceType

        enum DeviceType: String {
            case iPhone = "iPhone"
            case camera = "Camera"
            case unknown = "Unknown"
        }
    }

    // MARK: - Device Detection

    /// Scans for connected devices.
    /// Placeholder: uses ImageCaptureCore on real macOS.
    func detectDevices() async {
        isScanning = true
        statusMessage = "Scanning for devices..."

        // Simulate a brief scan
        try? await Task.sleep(for: .milliseconds(500))

        // On real macOS, this would use ICDeviceBrowser:
        //
        // import ImageCaptureCore
        //
        // class DeviceBrowserDelegate: NSObject, ICDeviceBrowserDelegate {
        //     func deviceBrowser(_ browser: ICDeviceBrowser,
        //                        didAdd device: ICDevice, moreComing: Bool) {
        //         // Handle new device
        //     }
        // }
        //
        // let browser = ICDeviceBrowser()
        // browser.delegate = delegate
        // browser.start()

        devices = []
        selectedDevice = nil
        statusMessage = "No devices detected. Connect an iPhone or camera via USB."
        isScanning = false
    }

    /// Imports photos from the selected device to the destination folder.
    /// Placeholder implementation.
    func importPhotos(
        to destination: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> Int {
        guard let device = selectedDevice else {
            throw DeviceImportError.noDeviceSelected
        }

        statusMessage = "Importing from \(device.name)..."

        // On real macOS, this would use ICCameraDevice:
        //
        // import ImageCaptureCore
        //
        // func requestDownloadFile(_ file: ICCameraFile,
        //                          options: [ICDownloadOption: Any],
        //                          downloadDelegate: ICCameraDeviceDownloadDelegate,
        //                          didDownloadSelector: Selector,
        //                          contextInfo: UnsafeMutableRawPointer?)

        throw DeviceImportError.notImplemented(
            "Device import requires macOS with ImageCaptureCore. " +
            "This is a placeholder implementation."
        )
    }
}

// MARK: - Errors

enum DeviceImportError: LocalizedError {
    case noDeviceSelected
    case notImplemented(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            return "No device selected."
        case .notImplemented(let message):
            return message
        case .importFailed(let message):
            return "Import failed: \(message)"
        }
    }
}
