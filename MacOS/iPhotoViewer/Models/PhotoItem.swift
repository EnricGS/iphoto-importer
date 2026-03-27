import Foundation
import AppKit
import AVFoundation

/// Represents a photo or video item, from a local folder or an MTP device.
@Observable
final class PhotoItem: Identifiable, Hashable {

    // MARK: - Identity

    let id: String
    let fullPath: String
    let fileName: String
    let isLocal: Bool

    // MARK: - Metadata

    var dateTaken: Date?
    let sizeBytes: Int64
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0

    /// Video rotation in degrees (0, 90, 180, 270) from track header metadata.
    var videoRotation: Int = 0

    // MARK: - UI State

    var isSelected: Bool = false
    var isHighlighted: Bool = false
    var thumbnail: NSImage?

    // MARK: - Computed

    var isVideo: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return Self.videoExtensions.contains(ext)
    }

    var isImage: Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    // MARK: - Supported extensions

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "bmp", "gif", "webp", "tiff", "tif", "heic", "heif"
    ]

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "avi", "mkv"
    ]

    static let allExtensions: Set<String> = imageExtensions.union(videoExtensions)

    // MARK: - Init

    init(fullPath: String, fileName: String, dateTaken: Date? = nil,
         sizeBytes: Int64, isLocal: Bool = true) {
        self.id = fullPath
        self.fullPath = fullPath
        self.fileName = fileName
        self.dateTaken = dateTaken
        self.sizeBytes = sizeBytes
        self.isLocal = isLocal
    }

    // MARK: - Hashable

    static func == (lhs: PhotoItem, rhs: PhotoItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
