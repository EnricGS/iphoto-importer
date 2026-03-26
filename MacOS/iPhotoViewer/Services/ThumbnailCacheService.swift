import Foundation
import AppKit
import CryptoKit

/// Persistent on-disk thumbnail cache service.
/// Stores thumbnails as JPEG at 85% quality, 512px max.
/// Two-level cache: in-memory ConcurrentDictionary + on-disk JPEG files.
actor ThumbnailCacheService {

    // MARK: - Configuration

    let thumbnailMaxSize: Int = 512
    let jpegQuality: CGFloat = 0.85

    // MARK: - State

    private let cacheFolder: URL
    private var memoryCache: [String: NSImage] = [:]
    private let fileService = FileService()

    // MARK: - Init

    init() {
        let appSupport = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheFolder = appSupport.appendingPathComponent("com.iphotoviewer.thumbnails", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Gets a thumbnail, checking memory first, then disk, then generating.
    func getThumbnail(for filePath: String) async -> NSImage? {
        // 1. Memory cache
        if let cached = memoryCache[filePath] {
            return cached
        }

        // 2. Disk cache
        let cacheKey = getCacheKey(for: filePath)
        let cachePath = cacheFolder.appendingPathComponent("\(cacheKey).jpg")

        if FileManager.default.fileExists(atPath: cachePath.path) {
            if let image = NSImage(contentsOf: cachePath) {
                memoryCache[filePath] = image
                return image
            }
        }

        // 3. Generate new thumbnail
        let thumbnail = await Task.detached(priority: .utility) { [fileService, thumbnailMaxSize] in
            fileService.generateThumbnail(for: filePath, maxSize: thumbnailMaxSize)
        }.value

        if let thumbnail {
            memoryCache[filePath] = thumbnail
            saveToDisk(image: thumbnail, at: cachePath)
        }

        return thumbnail
    }

    /// Clears the in-memory cache (disk cache persists).
    func clearMemoryCache() {
        memoryCache.removeAll()
    }

    // MARK: - Private

    /// Saves a thumbnail to disk as JPEG.
    private func saveToDisk(image: NSImage, at url: URL) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: jpegQuality]
              ) else {
            return
        }

        try? jpegData.write(to: url, options: .atomic)
    }

    /// Generates a cache key based on the file path, size and modification date.
    private func getCacheKey(for filePath: String) -> String {
        let fm = FileManager.default
        var raw = filePath

        if let attrs = try? fm.attributesOfItem(atPath: filePath) {
            let size = attrs[.size] as? Int64 ?? 0
            let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            raw = "\(filePath)|\(size)|\(modDate)"
        }

        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
