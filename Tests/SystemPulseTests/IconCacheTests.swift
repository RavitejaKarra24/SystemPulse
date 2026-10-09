import AppKit
import XCTest

@testable import SystemPulse

final class IconCacheTests: XCTestCase {
    func testSharedDefaultIsExplicitlyBounded() {
        XCTAssertEqual(IconCache.defaultCapacity, 512)
        let cache = IconCache()
        XCTAssertEqual(cache.capacity, IconCache.defaultCapacity)
        XCTAssertEqual(cache.count, 0)
    }

    func testReadRefreshesRecencyAndMissingReadDoesNotEvict() {
        let cache = IconCache(capacity: 2)
        let a = NSImage(size: NSSize(width: 32, height: 32))
        let b = NSImage(size: NSSize(width: 32, height: 32))
        let c = NSImage(size: NSSize(width: 32, height: 32))
        cache.set(a, for: "a")
        cache.set(b, for: "b")
        XCTAssertTrue(cache.get("a") === a)
        XCTAssertNil(cache.get("missing"))
        cache.set(c, for: "c")
        XCTAssertNil(cache.get("b"))
        XCTAssertTrue(cache.get("a") === a)
        XCTAssertTrue(cache.get("c") === c)
        XCTAssertEqual(cache.count, 2)
    }

    func testReplacementRefreshesRecencyWithoutConsumingAnotherSlot() {
        let cache = IconCache(capacity: 2)
        let initial = NSImage(size: NSSize(width: 32, height: 32))
        let replacement = NSImage(size: NSSize(width: 32, height: 32))
        cache.set(initial, for: "a")
        cache.set(initial, for: "b")
        cache.set(replacement, for: "a")
        XCTAssertEqual(cache.count, 2)
        cache.set(initial, for: "c")
        XCTAssertNil(cache.get("b"))
        XCTAssertTrue(cache.get("a") === replacement)
        XCTAssertEqual(cache.count, 2)
    }

    func testZeroAndNegativeCapacityNeverRetainImages() {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        for capacity in [0, -1, Int.min] {
            let cache = IconCache(capacity: capacity)
            cache.set(image, for: "fixture")
            XCTAssertEqual(cache.capacity, 0)
            XCTAssertEqual(cache.count, 0)
            XCTAssertNil(cache.get("fixture"))
            cache.clear()
        }
    }

    func testClearResetsImagesAndOrderingAndAllowsReuse() {
        let cache = IconCache(capacity: 1)
        let image = NSImage(size: NSSize(width: 32, height: 32))
        cache.set(image, for: "before")
        cache.clear()
        cache.clear()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.get("before"))
        cache.set(image, for: "after")
        cache.set(image, for: "latest")
        XCTAssertNil(cache.get("after"))
        XCTAssertTrue(cache.get("latest") === image)
        XCTAssertEqual(cache.count, 1)
    }

    func testEvictionAndClearReleaseCacheOwnedImages() {
        let cache = IconCache(capacity: 1)
        weak var evicted: NSImage?
        weak var cleared: NSImage?
        autoreleasepool {
            let image = NSImage(size: NSSize(width: 32, height: 32))
            evicted = image
            cache.set(image, for: "old")
        }
        XCTAssertNotNil(evicted)
        autoreleasepool {
            let image = NSImage(size: NSSize(width: 32, height: 32))
            cleared = image
            cache.set(image, for: "new")
        }
        XCTAssertNil(evicted)
        XCTAssertNotNil(cleared)
        cache.clear()
        XCTAssertNil(cleared)
    }

    func testSyntheticLongSessionPathChurnStaysBounded() {
        let cache = IconCache(capacity: 32)
        let image = NSImage(size: NSSize(width: 32, height: 32))
        // Synthetic keys only: never resolve live apps/files or collect icons.
        for index in 0..<20_000 {
            cache.set(image, for: "fixture-\(index)")
            XCTAssertLessThanOrEqual(cache.count, 32)
        }
        XCTAssertNil(cache.get("fixture-0"))
        for index in (20_000 - 32)..<20_000 {
            XCTAssertTrue(cache.get("fixture-\(index)") === image)
        }
        XCTAssertEqual(cache.count, 32)
    }

    func testConcurrentGetSetAndClearPreserveBoundAndUsability() {
        let cache = IconCache(capacity: 16)
        let image = NSImage(size: NSSize(width: 32, height: 32))
        // The immutable fixture is shared without touching NSImage rendering.
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for index in 0..<1_000 {
                let key = "fixture-\(worker)-\(index)"
                cache.set(image, for: key)
                _ = cache.get(key)
                if index.isMultiple(of: 31) { cache.clear() }
            }
        }
        XCTAssertLessThanOrEqual(cache.count, 16)
        cache.clear()
        cache.set(image, for: "final")
        XCTAssertTrue(cache.get("final") === image)
        XCTAssertEqual(cache.count, 1)
    }
}
