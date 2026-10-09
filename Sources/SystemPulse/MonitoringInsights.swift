import Foundation

/// Current optional snapshots plus RAW (not bucket-mean) CPU history. Missing values stay unknown.
/// The caller owns snapshot freshness for fields without timestamps and keeps these observations local;
/// process names are display-only, not inputs to exports or notifications.
struct InsightInput: Sendable {
    let cpuPoints: [TimedMetricSample]
    let memoryHeadroomPercent: Double?
    let memoryUsedBytes: UInt64?
    let memoryTotalBytes: UInt64?
    let swapUsedBytes: UInt64?
    let diskAvailableBytes: UInt64?
    let batteryChargePercent: Double?
    let isOnBattery: Bool
    let thermalLevel: Int?
    let topConsumerName: String?
    let topConsumerCPU: Double?
    let topConsumerSampledAt: Date?

    init(
        cpuPoints: [TimedMetricSample] = [],
        memoryHeadroomPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryTotalBytes: UInt64? = nil,
        swapUsedBytes: UInt64? = nil,
        diskAvailableBytes: UInt64? = nil,
        batteryChargePercent: Double? = nil,
        isOnBattery: Bool = false,
        thermalLevel: Int? = nil,
        topConsumerName: String? = nil,
        topConsumerCPU: Double? = nil,
        topConsumerSampledAt: Date? = nil
    ) {
        self.cpuPoints = cpuPoints
        self.memoryHeadroomPercent = memoryHeadroomPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.diskAvailableBytes = diskAvailableBytes
        self.batteryChargePercent = batteryChargePercent
        self.isOnBattery = isOnBattery
        self.thermalLevel = thermalLevel
        self.topConsumerName = topConsumerName
        self.topConsumerCPU = topConsumerCPU
        self.topConsumerSampledAt = topConsumerSampledAt
    }
}

/// Identity describes the rule, not its changing value or a process identity.
struct MonitoringInsight: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let metric: MetricTab
}

/// Deterministic, read-only rules. No timers, OS queries, inference across gaps, or corrective actions.
enum InsightEngine {
    static let maximumInsights = 4
    private static let cpuWindow: TimeInterval = 60
    private static let maximumCPUGap: TimeInterval = 4.5
    private static let minimumCPUSpan: TimeInterval = 30
    private static let cpuThreshold = 80.0
    private static let headroomThreshold = 18.0
    private static let diskThreshold: UInt64 = 5 * 1_073_741_824
    private static let consumerFreshness: TimeInterval = 15

    /// Stable priority: thermal, sustained CPU evidence, memory, disk, battery, current consumer.
    /// An empty result means no qualifying observation, NOT that the machine is healthy.
    static func insights(for input: InsightInput, at now: Date, visibleMetrics: Set<MetricTab>? = nil)
        -> [MonitoringInsight]
    {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return [] }
        var result: [MonitoringInsight] = []
        if let level = input.thermalLevel, (2...3).contains(level) {
            let label = level == 2 ? "Serious" : "Critical"
            result.append(
                MonitoringInsight(
                    id: "thermal", title: "\(label) thermal state",
                    detail: "macOS reports \(label.lowercased()) (level \(level) of 0–3; threshold 2). "
                        + "Review power and workload; this is a thermal state, not a temperature reading.",
                    metric: .power))
        }
        if let cpu = cpuInsight(input.cpuPoints, at: now) { result.append(cpu) }
        if let memory = memoryInsight(input) { result.append(memory) }
        if let available = input.diskAvailableBytes, available < diskThreshold {
            result.append(
                MonitoringInsight(
                    id: "disk-availability", title: "Limited home-volume availability",
                    detail: "About \(bytes(available)) available (\(available) bytes), below the 5 GiB threshold. "
                        + "APFS important-usage availability may include reclaimable space; "
                        + "it is not a measurement of purgeable bytes. This describes the home volume; "
                        + "the Disk page may have a different volume selected.",
                    metric: .disk))
        }
        if input.isOnBattery, let charge = input.batteryChargePercent,
            validPercent(charge), charge <= 20
        {
            result.append(
                MonitoringInsight(
                    id: "battery-charge", title: "Battery at or below 20%",
                    detail: "\(number(charge))% charge while running on battery (threshold ≤20%). "
                        + "Consider connecting power; charge alone does not predict remaining runtime.",
                    metric: .power))
        }
        if let consumer = consumerInsight(input, at: now) { result.append(consumer) }
        // Hidden modules must not consume the visible-card budget.
        return Array(result.filter { visibleMetrics?.contains($0.metric) ?? true }.prefix(maximumInsights))
    }

    private static func cpuInsight(_ points: [TimedMetricSample], at now: Date) -> MonitoringInsight? {
        // Reject malformed streams rather than sorting them or bridging over invalid readings.
        // Old/future well-formed points are excluded from the bounded evidence window.
        var previous: Date?
        for point in points {
            guard point.timestamp.timeIntervalSinceReferenceDate.isFinite, validPercent(point.value),
                previous.map({ point.timestamp > $0 }) ?? true
            else { return nil }
            previous = point.timestamp
        }
        let start = now.addingTimeInterval(-cpuWindow)
        let recent = points.filter { $0.timestamp >= start && $0.timestamp <= now }
        guard let last = recent.last, now.timeIntervalSince(last.timestamp) <= maximumCPUGap else { return nil }

        // Only the latest contiguous segment is eligible; a stale pre-gap segment cannot qualify.
        var firstIndex = recent.count - 1
        while firstIndex > 0,
            recent[firstIndex].timestamp.timeIntervalSince(recent[firstIndex - 1].timestamp) <= maximumCPUGap
        {
            firstIndex -= 1
        }
        let samples = recent[firstIndex...]
        guard let first = samples.first else { return nil }
        let span = last.timestamp.timeIntervalSince(first.timestamp)
        guard span >= minimumCPUSpan else { return nil }
        // Sample-weighted mean, NOT a time-weighted integral or an assertion about unobserved instants.
        var mean = 0.0
        for (index, sample) in samples.enumerated() {
            mean += (sample.value - mean) / Double(index + 1)
        }
        guard mean >= cpuThreshold else { return nil }
        return MonitoringInsight(
            id: "cpu-average", title: "High recent CPU average",
            detail: "CPU samples averaged \(number(mean))% across \(number(span)) seconds "
                + "(\(samples.count) raw readings; threshold ≥80%). "
                + "Sample-weighted, within the last 60 seconds, with gaps ≤4.5 seconds. Review CPU activity.",
            metric: .cpu)
    }

    private static func memoryInsight(_ input: InsightInput) -> MonitoringInsight? {
        let headroom = input.memoryHeadroomPercent.flatMap { validPercent($0) ? $0 : nil }
        let lowHeadroom = headroom.map { $0 < headroomThreshold } ?? false
        let hasSwap = input.swapUsedBytes.map { $0 > 0 } ?? false
        guard lowHeadroom || hasSwap else { return nil }
        var facts: [String] = []
        if lowHeadroom, let headroom {
            facts.append(
                "Estimated free + cached headroom is about \(number(headroom))% (threshold <18%); "
                    + "not Activity Monitor’s macOS memory pressure signal.")
        }
        if let used = input.memoryUsedBytes, let total = input.memoryTotalBytes, total > 0, used <= total {
            facts.append("\(bytes(used)) of \(bytes(total)) memory in use.")
        }
        if let swap = input.swapUsedBytes {
            facts.append("Swap currently used: \(bytes(swap)); not a rate or proof of current pressure.")
        }
        facts.append("Review memory details; these readings alone do not establish a problem.")
        return MonitoringInsight(
            id: "memory-observation", title: lowHeadroom ? "Memory headroom estimate" : "Swap in use",
            detail: facts.joined(separator: " "), metric: .memory)
    }

    private static func consumerInsight(_ input: InsightInput, at now: Date) -> MonitoringInsight? {
        guard let rawName = input.topConsumerName, let cpu = input.topConsumerCPU, cpu.isFinite, cpu > 0,
            let sampledAt = input.topConsumerSampledAt, sampledAt.timeIntervalSinceReferenceDate.isFinite
        else { return nil }
        let age = now.timeIntervalSince(sampledAt)
        guard age >= 0, age <= consumerFreshness else { return nil }
        let name = displayName(rawName)
        guard !name.isEmpty else { return nil }
        return MonitoringInsight(
            id: "cpu-consumer", title: "Recent top CPU consumer",
            detail: "\(name): \(number(cpu))% CPU, sampled \(number(age)) seconds ago (freshness ≤15 seconds). "
                + "100% represents one core; multicore values can exceed 100%. "
                + "This snapshot does not establish the cause of whole-machine CPU activity. Review CPU details.",
            metric: .cpu)
    }

    private static func validPercent(_ value: Double) -> Bool {
        value.isFinite && (0...100).contains(value)
    }

    private static func number(_ value: Double) -> String {
        // All callers validate finite values. Fixed precision keeps explanations compact.
        String(format: value > 10_000 ? "%.2g" : "%.1f", value)
    }

    /// UInt64 is never narrowed to Int/Int64 (which would trap for raw counters above Int64.max).
    private static func bytes(_ value: UInt64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
        var scaled = Double(value)
        var unit = 0
        while scaled >= 1024, unit < units.count - 1 {
            scaled /= 1024
            unit += 1
        }
        return unit == 0 ? "\(value) B" : "\(number(scaled)) \(units[unit])"
    }

    /// Bound work and display length; strip controls and bidi formatting, collapse whitespace.
    /// Text is rendered verbatim by the card, never as Markdown, a path, or an executable action.
    private static func displayName(_ name: String) -> String {
        let safeScalars = name.unicodeScalars.prefix(320).filter {
            switch $0.properties.generalCategory {
            case .control, .format: return false
            default: return true
            }
        }
        let safe = String(String.UnicodeScalarView(safeScalars))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return safe.count > 80 ? String(safe.prefix(80)) + "…" : safe
    }
}
