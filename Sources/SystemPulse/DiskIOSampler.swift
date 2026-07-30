import Foundation
import IOKit

/// Cumulative block-device byte counters, summed across every storage driver.
struct DiskIOSnapshot: Sendable {
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
    var timestamp: Date = .now
}

/// Reads disk throughput counters from the `IOBlockStorageDriver` registry
/// entries. These are cumulative since boot, so callers difference two
/// snapshots to get a rate.
enum DiskIOSampler {

    // Keys from IOKit/storage/IOBlockStorageDriver.h, which isn't surfaced to Swift.
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    static func snapshot() -> DiskIOSnapshot {
        var snapshot = DiskIOSnapshot()

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        ) == KERN_SUCCESS else { return snapshot }
        defer { IOObjectRelease(iterator) }

        while true {
            let drive = IOIteratorNext(iterator)
            guard drive != 0 else { break }
            defer { IOObjectRelease(drive) }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(drive, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props[statisticsKey] as? [String: Any] else { continue }

            snapshot.bytesRead += (stats[bytesReadKey] as? NSNumber)?.uint64Value ?? 0
            snapshot.bytesWritten += (stats[bytesWrittenKey] as? NSNumber)?.uint64Value ?? 0
        }

        return snapshot
    }
}
