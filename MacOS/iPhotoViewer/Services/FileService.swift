import Foundation
import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

/// Service for local file operations: scanning folders, generating thumbnails,
/// loading full-resolution images, and file management (copy, move, delete).
actor FileService {

    // MARK: - Folder Scanning

    /// Scans a folder recursively for image and video files.
    /// Reports progress via the callback.
    func scanFolder(
        at path: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws -> [PhotoItem] {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            throw FileServiceError.folderNotFound(path)
        }

        var results: [PhotoItem] = []
        var scanned = 0

        let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
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

            results.append(item)

            if scanned % 50 == 0 {
                progress(scanned, results.count, fileURL.lastPathComponent)
            }
        }

        progress(scanned, results.count, "Completed")
        return results
    }

    // MARK: - Thumbnail Generation

    /// Generates a thumbnail for an image file using ImageIO.
    /// Uses CGImageSource for fast, EXIF-aware decoding.
    nonisolated func generateThumbnail(for path: String, maxSize: Int = 512) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // Video thumbnail via AVFoundation
        if PhotoItem.videoExtensions.contains(ext) {
            return generateVideoThumbnail(for: path, maxSize: maxSize)
        }

        // Image thumbnail via ImageIO (respects EXIF orientation)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // Apply EXIF orientation
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
