import Foundation

/// Two cumulative byte channels (receive/send or read/write).
struct ByteCounters: Sendable {
    var first: UInt64
    var second: UInt64
}

/// Differences only counters present in both samples. A new device/interface
/// establishes a baseline; removing one cannot erase another one's traffic.
struct CounterRateTracker {
    private var previous: (counters: [String: ByteCounters], timestamp: Date)?
    private(set) var firstRate: Double = 0
    private(set) var secondRate: Double = 0
    private(set) var firstTotal: UInt64 = 0
    private(set) var secondTotal: UInt64 = 0

    /// Forget the rate interval, not the observed session totals. Bytes during
    /// suspension are deliberately unobserved, rather than smeared over wake.
    mutating func resetBaseline() {
        previous = nil
        firstRate = 0
        secondRate = 0
    }

    mutating func apply(_ counters: [String: ByteCounters], at timestamp: Date) {
        firstRate = 0
        secondRate = 0
        if let previous {
            let elapsed = timestamp.timeIntervalSince(previous.timestamp)
            // Do not consume an out-of-order reading or count the same bytes twice.
            guard elapsed.isFinite, elapsed > 0 else { return }
            var firstDelta: UInt64 = 0
            var secondDelta: UInt64 = 0
            for (key, current) in counters {
                guard let prior = previous.counters[key] else { continue }
                firstDelta = Self.add(firstDelta, current.first >= prior.first ? current.first - prior.first : 0)
                secondDelta = Self.add(secondDelta, current.second >= prior.second ? current.second - prior.second : 0)
            }
            firstRate = Double(firstDelta) / elapsed
            secondRate = Double(secondDelta) / elapsed
            firstTotal = Self.add(firstTotal, firstDelta)
            secondTotal = Self.add(secondTotal, secondDelta)
        }
        previous = (counters, timestamp)
    }

    private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let sum = lhs.addingReportingOverflow(rhs)
        return sum.overflow ? .max : sum.partialValue
    }
}
