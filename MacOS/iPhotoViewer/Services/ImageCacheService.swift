import Foundation
import AppKit

/// LRU in-memory cache for full-resolution images.
/// Uses a doubly-linked list + dictionary for O(1) operations.
final class ImageCacheService: @unchecked Sendable {

    // MARK: - Doubly-linked list node

    private class Node {
        let key: String
        let image: NSImage
        var prev: Node?
        var next: Node?

        init(key: String, image: NSImage) {
            self.key = key
            self.image = image
        }
    }

    // MARK: - State

    private let maxSize: Int
    private var map: [String: Node] = [:]
    private var head: Node? // Most recently used
    private var tail: Node? // Least recently used
    private var count = 0
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

        guard let node = map[key] else { return nil }
        moveToFront(node)
        return node.image
    }

    /// Adds an image to the cache. Evicts the oldest entry if capacity is exceeded.
    func put(_ key: String, image: NSImage) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = map[key] {
            removeNode(existing)
        }

        let node = Node(key: key, image: image)
        addToFront(node)
        map[key] = node

        while count > maxSize {
            if let lru = tail {
                removeNode(lru)
                map.removeValue(forKey: lru.key)
            }
        }
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
        map.removeAll()
        head = nil
        tail = nil
        count = 0
    }

    // MARK: - Private linked list operations

    private func addToFront(_ node: Node) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil { tail = node }
        count += 1
    }

    private func removeNode(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if node === head { head = node.next }
        if node === tail { tail = node.prev }
        node.prev = nil
        node.next = nil
        count -= 1
    }

    private func moveToFront(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        addToFront(node)
    }
}
