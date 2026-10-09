import Foundation

/// Each range reads one bounded tier; longer ranges show sample-weighted bucket means.
enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case fiveMinutes, oneHour, oneDay

    var id: Self { self }

    var label: String {
        switch self {
        case .fiveMinutes: return "5m"
        case .oneHour: return "1h"
        case .oneDay: return "24h"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .fiveMinutes: return 300
        case .oneHour: return 3_600
        case .oneDay: return 86_400
        }
    }

    var bucketDuration: TimeInterval {
        switch self {
        case .fiveMinutes: return 0
        case .oneHour: return 10
        case .oneDay: return 60
        }
    }
}

struct TimedMetricSample: Identifiable, Sendable, Codable, Equatable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

/// In-memory only. Appends and eviction are O(1) amortized, with no sorting or 24h raw log.
/// Values remain in caller units. Negative/nonfinite values, invalid dates and duplicate or
/// decreasing timestamps are ignored, without moving the retention clock.
struct MetricHistory: Sendable {
    // A hard cap also bounds memory if callers unexpectedly record faster than the app's 1s cadence.
    // At >4Hz the raw tier may cover less than five minutes; aggregates still include every sample.
    static let rawCapacity = 1_201
    static let hourCapacity = 361
    static let dayCapacity = 1_441

    private var raw = HistoryRing<TimedMetricSample>(capacity: rawCapacity)
    private var hourly = HistoryRing<HistoryBucket>(capacity: hourCapacity)
    private var daily = HistoryRing<HistoryBucket>(capacity: dayCapacity)
    private(set) var latestTimestamp: Date?

    var rawSampleCount: Int { raw.count }
    var hourBucketCount: Int { hourly.count }
    var dayBucketCount: Int { daily.count }

    mutating func record(_ value: Double, at timestamp: Date) {
        guard value.isFinite, value >= 0, timestamp.timeIntervalSinceReferenceDate.isFinite,
            latestTimestamp.map({ timestamp > $0 }) ?? true
        else { return }

        let sample = TimedMetricSample(timestamp: timestamp, value: value)
        raw.append(sample)
        while let first = raw.first, first.timestamp < timestamp.addingTimeInterval(-300) {
            raw.removeFirst()
        }
        Self.record(sample, in: &hourly, width: 10, retention: 3_600)
        Self.record(sample, in: &daily, width: 60, retention: 86_400)
        latestTimestamp = timestamp
    }

    /// Inclusive [endingAt - duration, endingAt]. Empty windows stay empty (no zero-fill).
    /// Bucket timestamp is its last real observation, NOT a synthetic bucket boundary.
    /// A bucket straddling either query edge is omitted: no out-of-window values can leak
    /// into a mean. Thus coarse windows can omit up to one bucket at each edge.
    /// Historical queries cannot recover evicted samples or split already aggregated buckets.
    func points(in range: HistoryRange, endingAt end: Date) -> [TimedMetricSample] {
        guard end.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let start = end.addingTimeInterval(-range.duration)
        switch range {
        case .fiveMinutes:
            return raw.elements().filter { $0.timestamp >= start && $0.timestamp <= end }
        case .oneHour:
            return Self.points(in: hourly, from: start, through: end)
        case .oneDay:
            return Self.points(in: daily, from: start, through: end)
        }
    }

    private static func points(
        in ring: HistoryRing<HistoryBucket>, from start: Date, through end: Date
    ) -> [TimedMetricSample] {
        ring.elements().compactMap { bucket in
            guard bucket.firstTimestamp >= start, bucket.lastTimestamp <= end else { return nil }
            return TimedMetricSample(timestamp: bucket.lastTimestamp, value: bucket.mean)
        }
    }

    private static func record(
        _ sample: TimedMetricSample, in ring: inout HistoryRing<HistoryBucket>,
        width: TimeInterval, retention: TimeInterval
    ) {
        // Keep the bucket key as Double to avoid integer conversion traps for extreme finite dates.
        let key = floor(sample.timestamp.timeIntervalSinceReferenceDate / width)
        if var last = ring.last, last.key == key {
            last.add(sample)
            ring.replaceLast(last)
        } else {
            ring.append(HistoryBucket(key: key, sample: sample))
        }
        let cutoff = sample.timestamp.addingTimeInterval(-retention)
        while let first = ring.first, first.lastTimestamp < cutoff {
            ring.removeFirst()
        }
    }
}

/// Pure window geometry/selection shared by the canvas and deterministic tests.
/// Nearest selection snaps only to an existing observation, even when the pointer is in a gap.
struct MetricHistoryWindow {
    let range: HistoryRange
    let endingAt: Date
    let points: [TimedMetricSample]

    init(history: MetricHistory, range: HistoryRange, endingAt: Date) {
        self.range = range
        self.endingAt = endingAt
        points = history.points(in: range, endingAt: endingAt)
    }

    var startingAt: Date { endingAt.addingTimeInterval(-range.duration) }

    func fraction(at timestamp: Date) -> Double {
        min(1, max(0, timestamp.timeIntervalSince(startingAt) / range.duration))
    }

    func nearestSample(to fraction: Double) -> TimedMetricSample? {
        guard fraction.isFinite else { return nil }
        let target = startingAt.addingTimeInterval(min(1, max(0, fraction)) * range.duration)
        // Bounded ordered array; binary search rather than sorting/scanning on every hover event.
        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].timestamp < target { low = middle + 1 } else { high = middle }
        }
        guard !points.isEmpty else { return nil }
        if low == 0 { return points.first }
        if low == points.count { return points.last }
        let before = points[low - 1]
        let after = points[low]
        return target.timeIntervalSince(before.timestamp) <= after.timestamp.timeIntervalSince(target)
            ? before : after
    }
}

private struct HistoryBucket: Sendable {
    let key: Double
    let firstTimestamp: Date
    var lastTimestamp: Date
    var mean: Double
    var count: Double = 1

    init(key: Double, sample: TimedMetricSample) {
        self.key = key
        firstTimestamp = sample.timestamp
        lastTimestamp = sample.timestamp
        mean = sample.value
    }

    mutating func add(_ sample: TimedMetricSample) {
        count += 1
        // Nonnegative inputs make the difference safe, unlike accumulating an overflowing sum.
        mean += (sample.value - mean) / count
        lastTimestamp = sample.timestamp
    }
}

/// Fixed-capacity FIFO, value semantics allow freezing a copy without pausing the recorder.
private struct HistoryRing<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var head = 0
    private(set) var count = 0

    init(capacity: Int) {
        storage = Array(repeating: nil, count: capacity)
    }

    var first: Element? { count == 0 ? nil : storage[head] }
    var last: Element? { count == 0 ? nil : storage[(head + count - 1) % storage.count] }

    mutating func append(_ element: Element) {
        if count == storage.count { removeFirst() }
        storage[(head + count) % storage.count] = element
        count += 1
    }

    mutating func replaceLast(_ element: Element) {
        guard count > 0 else { return }
        storage[(head + count - 1) % storage.count] = element
    }

    mutating func removeFirst() {
        guard count > 0 else { return }
        storage[head] = nil
        head = (head + 1) % storage.count
        count -= 1
    }

    func elements() -> [Element] {
        (0..<count).compactMap { storage[(head + $0) % storage.count] }
    }
}
