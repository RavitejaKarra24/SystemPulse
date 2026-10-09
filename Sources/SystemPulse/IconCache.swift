import AppKit
import Foundation

/// Thread-safe, session-only process icon cache with a strict entry-count bound.
/// The lock protects both the images and their least-recently-used ordering;
/// callers must not mutate an image after sharing it through this cache.
/// Entry count is not a byte/footprint budget for NSImage representations.
final class IconCache: @unchecked Sendable {
    static let defaultCapacity = 512
    static let shared = IconCache()

    let capacity: Int
    private var cache: [String: NSImage] = [:]
    private var recency: [String] = []
    private let lock = NSLock()

    init(capacity: Int = IconCache.defaultCapacity) {
        self.capacity = max(0, capacity)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    func get(_ key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        guard let image = cache[key] else { return nil }
        markRecentlyUsed(key)
        return image
    }

    func set(_ image: NSImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard capacity > 0 else { return }
        if cache[key] == nil, cache.count == capacity {
            let oldest = recency.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cache[key] = image
        markRecentlyUsed(key)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        recency.removeAll()
    }

    /// Called only while holding the lock; linear work is bounded by capacity.
    private func markRecentlyUsed(_ key: String) {
        if let index = recency.firstIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }
}
