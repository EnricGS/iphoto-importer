import Foundation
import AppKit
import ImageIO
import AVFoundation
import CryptoKit
import UniformTypeIdentifiers

/// Service for local file operations: scanning folders, generating thumbnails,
/// loading full-resolution images, and file management (copy, move, delete).
actor FileService {

    // MARK: - Folder Scanning

    /// Scans a folder for image and video files.
    /// Reports progress via the callback.
    func scanFolder(
        at path: String,
        recursive: Bool = false,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> [PhotoItem] {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            throw FileServiceError.folderNotFound(path)
        }

        var results: [PhotoItem] = []
        var scanned = 0

        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive {
            options.insert(.skipsSubdirectoryDescendants)
        }

        let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: options
        )

        guard let enumerator else {
            throw FileServiceError.cannotEnumerate(path)
        }

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard PhotoItem.allExtensions.contains(ext) else { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey, .isRegularFileKey
            ])

            guard resourceValues?.isRegularFile == true else { continue }

            scanned += 1
            let fileSize = Int64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate

            let item = PhotoItem(
                fullPath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                dateTaken: modDate,
                sizeBytes: fileSize,
                isLocal: true
            )

            // Read video rotation from track header during scanning
            if item.isVideo {
                item.videoRotation = Self.getVideoRotation(filePath: fileURL.path)
            }

            results.append(item)

            if scanned % 50 == 0 {
                progress(scanned, results.count, fileURL.lastPathComponent)
            }
        }

        progress(scanned, results.count, "Completed")
        return results
    }

    // MARK: - GPS Extraction

    /// Extracts GPS coordinates from EXIF metadata of an image file.
    nonisolated static func extractGPSLocation(at path: String) -> (latitude: Double, longitude: Double)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double else { return nil }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String ?? "N"
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String ?? "E"
        return (latRef == "S" ? -lat : lat, lonRef == "W" ? -lon : lon)
    }

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail for an image file using ImageIO.
    /// Strategy (Photo Mechanic-style):
    ///   1. Try embedded JPEG preview (instant for RAW/HEIC)
    ///   2. Fall back to full decode with downscale
    nonisolated func generateThumbnail(for path: String, maxSize: Int = 512) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // Video thumbnail via AVFoundation
        if PhotoItem.videoExtensions.contains(ext) {
            return generateVideoThumbnail(for: path, maxSize: maxSize)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // Strategy 1: Try embedded preview/thumbnail (instant, no full decode)
        // RAW and HEIC files always have a usable embedded JPEG preview
        if PhotoItem.rawExtensions.contains(ext) || ext == "heic" || ext == "heif" {
            if let preview = extractEmbeddedPreview(source: source, maxSize: maxSize) {
                return preview
            }
        }

        // Strategy 2: Full decode with downscale (standard images)
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Extracts the embedded JPEG preview from a RAW/HEIC file.
    /// This is the Photo Mechanic trick: the preview is pre-rendered by the camera,
    /// so extraction is nearly instant vs. full RAW decode.
    nonisolated func extractEmbeddedPreview(source: CGImageSource, maxSize: Int = 512) -> NSImage? {
        // First try: kCGImageSourceCreateThumbnailFromImageIfAbsent = false
        // This only returns a thumbnail if one is already embedded (no decode)
        let fastOptions: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, fastOptions as CFDictionary) {
            // Verify the preview is usable (at least 200px)
            if cgImage.width >= 200 || cgImage.height >= 200 {
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }

        return nil
    }

    /// Generates a thumbnail from a video file using AVAssetImageGenerator.
    nonisolated func generateVideoThumbnail(for path: String, maxSize: Int = 512) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true // Respect video orientation
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    // MARK: - Quick Preview Loading

    /// Loads a fast preview for the viewer (level 2 of the pyramid).
    /// For RAW/HEIC: extracts the embedded preview (~1-2MP, instant).
    /// For standard images: loads at reduced resolution.
    nonisolated func loadQuickPreview(at path: String, maxSize: Int = 2048) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        // RAW/HEIC: try embedded preview first (instant)
        if PhotoItem.rawExtensions.contains(ext) || ext == "heic" || ext == "heif" {
            if let preview = extractEmbeddedPreview(source: source, maxSize: maxSize) {
                return preview
            }
        }

        // Standard: decode at reduced resolution
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Full Image Loading

    /// Loads a full-resolution image with EXIF orientation correction.
    /// Uses ImageIO for fast decoding with optional max pixel width.
    nonisolated func loadFullImage(at path: String, maxPixelWidth: Int? = nil) -> NSImage? {
        let url = URL(fileURLWithPath: path)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        if let maxWidth = maxPixelWidth {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxWidth
        }

        // If no max size specified, load the original image
        if maxPixelWidth == nil {
            // Load the full image directly
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else {
                return nil
            }

            // Apply EXIF orientation
            let oriented = applyExifOrientation(source: source, image: cgImage)
            return NSImage(cgImage: oriented, size: NSSize(width: oriented.width, height: oriented.height))
        }

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Reads EXIF orientation and creates a properly oriented CGImage.
    private nonisolated func applyExifOrientation(source: CGImageSource, image: CGImage) -> CGImage {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientationRaw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) else {
            return image
        }

        // If orientation is normal, return as-is
        if orientation == .up { return image }

        // Use CIImage to apply orientation transform efficiently
        let ciImage = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation.rawValue))
        let context = CIContext()
        guard let result = context.createCGImage(ciImage, from: ciImage.extent) else {
            return image
        }
        return result
    }

    // MARK: - Video Rotation Detection

    /// Reads the rotation of a video file from the tkhd (track header) box
    /// transformation matrix in MP4/MOV container structure.
    /// Returns degrees (0, 90, 180, 270).
    nonisolated static func getVideoRotation(filePath: String) -> Int {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath),
                                   options: [.mappedIfSafe]) else {
            return 0
        }

        let bufferSize = min(data.count, 262144) // Read up to 256KB
        let buffer = data.prefix(bufferSize)
        return findTkhdRotation(in: buffer)
    }

    /// Searches for the tkhd box in the buffer and extracts the rotation
    /// from the transformation matrix.
    /// The matrix is 3x3 fixed-point 16.16, at offset 40 (v0) or 52 (v1) from tkhd start.
    private nonisolated static func findTkhdRotation(in data: Data) -> Int {
        let bytes = Array(data)
        let count = bytes.count

        // Search for "tkhd" box type
        for i in 0..<(count - 4) {
            guard bytes[i] == 0x74,     // 't'
                  bytes[i+1] == 0x6B,   // 'k'
                  bytes[i+2] == 0x68,   // 'h'
                  bytes[i+3] == 0x64    // 'd'
            else { continue }

            // Content starts right after the type field
            let tkhdStart = i + 4
            guard tkhdStart + 84 <= count else { continue }

            let version = bytes[tkhdStart]
            // Matrix offset: v0 = 40, v1 = 52 from content start
            let matrixOffset = tkhdStart + (version == 0 ? 40 : 52)
            guard matrixOffset + 36 <= count else { continue }

            // matrix[0][0] (a) and matrix[0][1] (b) are fixed-point 16.16
            let a = readBigEndianInt32(bytes, at: matrixOffset)
            let b = readBigEndianInt32(bytes, at: matrixOffset + 4)

            let aVal = Double(a) / 65536.0
            let bVal = Double(b) / 65536.0

            let angle = atan2(bVal, aVal) * (180.0 / .pi)
            let rotation = (Int(angle.rounded()) + 360) % 360

            // Normalize to 0, 90, 180, 270
            if rotation >= 45 && rotation < 135 { return 90 }
            if rotation >= 135 && rotation < 225 { return 180 }
            if rotation >= 225 && rotation < 315 { return 270 }
            return 0
        }

        return 0
    }

    /// Reads a big-endian Int32 from a byte array.
    private nonisolated static func readBigEndianInt32(_ bytes: [UInt8], at offset: Int) -> Int32 {
        return Int32(bytes[offset]) << 24
             | Int32(bytes[offset + 1]) << 16
             | Int32(bytes[offset + 2]) << 8
             | Int32(bytes[offset + 3])
    }

    // MARK: - Deduplication Hashing

    /// Computes MD5 hash of a file (exact duplicate detection).
    /// Reads in 64KB chunks to handle large files efficiently.
    nonisolated static func computeMD5(at path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        var hasher = Insecure.MD5()
        let chunkSize = 65536

        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: chunkSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes a perceptual hash (average hash) of an image.
    /// Resizes to 8x8 grayscale, compares each pixel to the average.
    /// Returns a 64-bit hash. Similar images have small Hamming distance.
    nonisolated static func computePerceptualHash(at path: String) -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        // Generate tiny 8x8 thumbnail
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: 8,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Draw to 8x8 grayscale bitmap
        let size = 8
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size)

        // Compute average brightness
        var total: Int = 0
        for i in 0..<(size * size) {
            total += Int(pixels[i])
        }
        let average = total / (size * size)

        // Build 64-bit hash: each bit = pixel > average
        var hash: UInt64 = 0
        for i in 0..<(size * size) {
            if pixels[i] > UInt8(average) {
                hash |= (1 << i)
            }
        }

        return hash
    }

    /// Computes a perceptual hash from an NSImage (for device thumbnails).
    nonisolated static func computePerceptualHashFromImage(_ image: NSImage) -> UInt64? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let size = 8
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: size * size)

        var total: Int = 0
        for i in 0..<(size * size) {
            total += Int(pixels[i])
        }
        let average = total / (size * size)

        var hash: UInt64 = 0
        for i in 0..<(size * size) {
            if pixels[i] > UInt8(average) {
                hash |= (1 << i)
            }
        }

        return hash
    }

    /// Computes Hamming distance between two perceptual hashes.
    /// Lower distance = more similar (0 = identical, ≤5 = likely duplicate).
    nonisolated static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        return (a ^ b).nonzeroBitCount
    }

    /// Extracts an EXIF-based fingerprint: camera + datetime + dimensions.
    /// Matches photos taken at the same moment by the same camera.
    nonisolated static func computeExifFingerprint(at path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any]

        let dateTime = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String ?? ""
        let make = tiff?[kCGImagePropertyTIFFMake as String] as? String ?? ""
        let model = tiff?[kCGImagePropertyTIFFModel as String] as? String ?? ""
        let width = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0

        // Need at least datetime to be useful
        guard !dateTime.isEmpty else { return nil }

        let raw = "\(dateTime)|\(make)|\(model)|\(width)x\(height)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - File Operations

    /// Copies files to a destination folder. Returns the number of files copied.
    func copyFiles(
        _ files: [PhotoItem],
        to destination: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> Int {
        let fm = FileManager.default
        let destURL = URL(fileURLWithPath: destination)

        if !fm.fileExists(atPath: destination) {
            try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
        }

        var copied = 0
        for (index, file) in files.enumerated() {
            progress(index + 1, files.count, file.fileName)

            let destPath = uniqueDestinationPath(folder: destination, fileName: file.fileName)
            try fm.copyItem(atPath: file.fullPath, toPath: destPath)
            copied += 1
        }
        return copied
    }

    /// Moves files to a destination folder. Returns the number of files moved.
    func moveFiles(
        _ files: [PhotoItem],
        to destination: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> Int {
        let fm = FileManager.default
        let destURL = URL(fileURLWithPath: destination)

        if !fm.fileExists(atPath: destination) {
            try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
        }

        var moved = 0
        for (index, file) in files.enumerated() {
            progress(index + 1, files.count, file.fileName)

            let destPath = uniqueDestinationPath(folder: destination, fileName: file.fileName)
            try fm.moveItem(atPath: file.fullPath, toPath: destPath)
            moved += 1
        }
        return moved
    }

    /// Moves files to Trash. Returns the number of files deleted.
    func deleteFiles(
        _ files: [PhotoItem],
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> Int {
        let fm = FileManager.default
        var deleted = 0

        for (index, file) in files.enumerated() {
            progress(index + 1, files.count, file.fileName)

            let fileURL = URL(fileURLWithPath: file.fullPath)
            try fm.trashItem(at: fileURL, resultingItemURL: nil)
            deleted += 1
        }
        return deleted
    }

    // MARK: - Helpers

    /// Generates a unique destination path to avoid overwriting existing files.
    private func uniqueDestinationPath(folder: String, fileName: String) -> String {
        let fm = FileManager.default
        var destPath = (folder as NSString).appendingPathComponent(fileName)

        if !fm.fileExists(atPath: destPath) { return destPath }

        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 1

        repeat {
            let newName = "\(name)_\(counter).\(ext)"
            destPath = (folder as NSString).appendingPathComponent(newName)
            counter += 1
        } while fm.fileExists(atPath: destPath)

        return destPath
    }
}

// MARK: - Errors

enum FileServiceError: LocalizedError {
    case folderNotFound(String)
    case cannotEnumerate(String)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let path):
            return "Folder not found: \(path)"
        case .cannotEnumerate(let path):
            return "Cannot enumerate folder: \(path)"
        }
    }
}
