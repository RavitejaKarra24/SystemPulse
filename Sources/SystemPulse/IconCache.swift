import AppKit
import Foundation

/// Thread-safe in-memory cache for process app icons.
final class IconCache: @unchecked Sendable {
    static let shared = IconCache()

    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    func set(_ image: NSImage, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = image
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}