import Foundation
import AppKit

/// LRU in-memory cache for full-resolution images.
/// Keeps the last N loaded images for fast navigation.
final class ImageCacheService: @unchecked Sendable {

    // MARK: - Types

    private struct CacheEntry {
        let key: String
        let image: NSImage
    }

    // MARK: - State

    private let maxSize: Int
    private var list: [CacheEntry] = []
    private var map: [String: Int] = [:]  // key -> index in list
    private let lock = NSLock()

    // MARK: - Init

    init(maxSize: Int = 20) {
        self.maxSize = maxSize
    }

    // MARK: - Public API

    /// Gets an image from the cache if it exists, moving it to the front (most recent).
    func get(_ key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }

        guard let index = map[key] else { return nil }
        let entry = list.remove(at: index)
        list.insert(entry, at: 0)
        rebuildMap()
        return entry.image
    }

    /// Adds an image to the cache. Evicts the oldest entry if capacity is exceeded.
    func put(_ key: String, image: NSImage) {
        lock.lock()
        defer { lock.unlock() }

        // If key already exists, update and move to front
        if let index = map[key] {
            list.remove(at: index)
        }

        let entry = CacheEntry(key: key, image: image)
        list.insert(entry, at: 0)

        // Evict oldest if over capacity
        while list.count > maxSize {
            let removed = list.removeLast()
            map.removeValue(forKey: removed.key)
        }

        rebuildMap()
    }

    /// Checks if a key exists in the cache.
    func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return map[key] != nil
    }

    /// Clears the entire cache.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        list.removeAll()
        map.removeAll()
    }

    // MARK: - Private

    private func rebuildMap() {
        map.removeAll(keepingCapacity: true)
        for (index, entry) in list.enumerated() {
            map[entry.key] = index
        }
    }
}
