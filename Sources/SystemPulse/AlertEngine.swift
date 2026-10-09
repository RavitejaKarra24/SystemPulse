import Foundation

/// Memory headroom is an estimate, not the operating system's memory-pressure signal.
enum AlertKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpuUsage, memoryHeadroom, diskAvailable, batteryCharge, thermal

    var id: Self { self }

    var title: String {
        switch self {
        case .cpuUsage: "High CPU usage"
        case .memoryHeadroom: "Low estimated memory headroom"
        case .diskAvailable: "Low disk space"
        case .batteryCharge: "Low battery charge"
        case .thermal: "Serious thermal state"
        }
    }

    /// Disk thresholds and measurements are bytes; GiB is only a presentation unit.
    var unitLabel: String {
        switch self {
        case .cpuUsage, .memoryHeadroom, .batteryCharge: "%"
        case .diskAvailable: "bytes"
        case .thermal: "level"
        }
    }

    fileprivate var defaultThreshold: Double {
        switch self {
        case .cpuUsage: 90
        case .memoryHeadroom: 10
        case .diskAvailable: 5 * 1_073_741_824
        case .batteryCharge: 20
        case .thermal: 2
        }
    }

    fileprivate var thresholdRange: ClosedRange<Double> {
        switch self {
        case .cpuUsage: 1...100
        case .memoryHeadroom, .batteryCharge: 0...100
        case .diskAvailable: 1...1_125_899_906_842_624
        case .thermal: 2...3
        }
    }

    fileprivate func accepts(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        switch self {
        case .cpuUsage, .memoryHeadroom, .batteryCharge: return (0...100).contains(value)
        case .diskAvailable: return value >= 0
        case .thermal: return (0...3).contains(value) && value.rounded() == value
        }
    }

    fileprivate func isBreached(_ value: Double, threshold: Double) -> Bool {
        switch self {
        case .cpuUsage, .thermal: value >= threshold
        case .memoryHeadroom, .diskAvailable, .batteryCharge: value <= threshold
        }
    }
}

struct AlertRule: Codable, Equatable, Sendable, Identifiable {
    var id: AlertKind { kind }
    var kind: AlertKind
    var enabled: Bool
    var threshold: Double
    var duration: TimeInterval
    var cooldown: TimeInterval

    static let minimumDuration: TimeInterval = 30
    static let minimumCooldown: TimeInterval = 900
    static var defaults: [Self] { AlertKind.allCases.map { Self(kind: $0) } }

    init(
        kind: AlertKind, enabled: Bool = true, threshold: Double? = nil,
        duration: TimeInterval = 30, cooldown: TimeInterval = 900
    ) {
        self.kind = kind
        self.enabled = enabled
        self.threshold = threshold ?? kind.defaultThreshold
        self.duration = duration
        self.cooldown = cooldown
        self = normalized()
    }

    /// Invalid thresholds use kind-specific defaults. Finite times are clamped to
    /// 30 seconds...1 day and 15 minutes...7 days; nonfinite times use the minimum.
    func normalized() -> Self {
        var result = self
        if !threshold.isFinite || !kind.thresholdRange.contains(threshold) {
            result.threshold = kind.defaultThreshold
        }
        if kind == .thermal { result.threshold = result.threshold.rounded(.up) }
        result.duration = duration.isFinite ? min(max(duration, Self.minimumDuration), 86_400) : Self.minimumDuration
        result.cooldown = cooldown.isFinite ? min(max(cooldown, Self.minimumCooldown), 604_800) : Self.minimumCooldown
        return result
    }

    /// First occurrence wins, with stable case order. Missing kinds stay missing:
    /// callers can use `defaults` when constructing a complete preferences list.
    static func normalized(_ rules: [Self]) -> [Self] {
        var byKind: [AlertKind: Self] = [:]
        for rule in rules where byKind[rule.kind] == nil {
            byKind[rule.kind] = rule.normalized()
        }
        return AlertKind.allCases.compactMap { byKind[$0] }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, enabled, threshold, duration, cooldown
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(AlertKind.self, forKey: .kind)
        self.init(
            kind: kind,
            enabled: (try? values.decode(Bool.self, forKey: .enabled)) ?? true,
            threshold: try? values.decode(Double.self, forKey: .threshold),
            duration: (try? values.decode(Double.self, forKey: .duration)) ?? Self.minimumDuration,
            cooldown: (try? values.decode(Double.self, forKey: .cooldown)) ?? Self.minimumCooldown
        )
    }
}

/// Raw, Sendable event. Presentation is derived solely from metrics, never from
/// process names, mount points, file paths, or other private identifiers.
struct AlertEvent: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let kind: AlertKind
    let timestamp: Date
    let value: Double
    let threshold: Double
    let duration: TimeInterval

    init(kind: AlertKind, timestamp: Date, value: Double, threshold: Double, duration: TimeInterval) {
        id = UUID()
        self.kind = kind
        self.timestamp = timestamp
        self.value = value
        self.threshold = threshold
        self.duration = duration
    }

    var title: String { kind.title }

    var message: String {
        let seconds = String(format: "%.0f", duration)
        switch kind {
        case .cpuUsage:
            return "CPU usage is \(percent(value)) (threshold ≥ \(percent(threshold))) for \(seconds) seconds."
        case .memoryHeadroom:
            return
                "ESTIMATED memory headroom is \(percent(value)) (threshold ≤ \(percent(threshold))) for \(seconds) seconds. "
                + "This is not OS memory pressure."
        case .diskAvailable:
            let available = String(format: "%.1f", value / 1_073_741_824)
            let limit = String(format: "%.1f", threshold / 1_073_741_824)
            return "Available disk space is \(available) GiB (threshold ≤ \(limit) GiB) for \(seconds) seconds."
        case .batteryCharge:
            return
                "Battery charge is \(percent(value)) (threshold ≤ \(percent(threshold))) for \(seconds) seconds on battery power."
        case .thermal:
            return "Thermal state is \(value >= 3 ? "critical" : "serious") for \(seconds) seconds."
        }
    }

    private func percent(_ number: Double) -> String { String(format: "%.0f%%", number) }
}

/// Pure evaluation with caller-provided sample time. `at` must be the reading's
/// timestamp, not a fresh timestamp attached to cached telemetry. Battery values
/// must be omitted unless running on battery with a valid charge reading.
struct AlertEngine: Sendable {
    /// Gaps over 10 seconds break a sustained window (including sleep/wake).
    /// The dictionary API cannot detect cached values with fabricated timestamps.
    static let maximumContinuityGap: TimeInterval = 10

    private struct State: Sendable {
        let rule: AlertRule
        var pendingSince: Date?
        var lastReading: Date?
        var lastFired: Date?
        var latched = false
    }

    private var states: [AlertKind: State] = [:]
    private var lastEvaluation: Date?

    init() {}

    mutating func evaluate(
        _ measurements: [AlertKind: Double], at timestamp: Date, rules: [AlertRule], enabled: Bool
    ) -> [AlertEvent] {
        guard enabled else {
            states.removeAll()
            lastEvaluation = nil
            return []
        }
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            resetPending()
            lastEvaluation = nil
            return []
        }
        if let previous = lastEvaluation, timestamp <= previous {
            resetPending()
            lastEvaluation = timestamp
            return []
        }
        lastEvaluation = timestamp

        let rules = AlertRule.normalized(rules)
        let activeKinds = Set(rules.filter(\.enabled).map(\.kind))
        states = states.filter { activeKinds.contains($0.key) }
        var events: [AlertEvent] = []
        for rule in rules where rule.enabled {
            var state = states[rule.kind] ?? State(rule: rule)
            // Effective rule edits start a new window and clear previous latching.
            if state.rule != rule { state = State(rule: rule) }
            defer { states[rule.kind] = state }
            guard let value = measurements[rule.kind], rule.kind.accepts(value) else {
                state.pendingSince = nil
                state.lastReading = nil
                // Missing/invalid data is NOT proof of recovery. Keep the latch.
                continue
            }
            if let previous = state.lastReading,
                timestamp.timeIntervalSince(previous) > Self.maximumContinuityGap
            {
                state.pendingSince = nil
            }
            state.lastReading = timestamp
            guard rule.kind.isBreached(value, threshold: rule.threshold) else {
                state.pendingSince = nil
                state.latched = false
                continue
            }
            guard !state.latched else { continue }
            guard let start = state.pendingSince else {
                state.pendingSince = timestamp
                continue
            }
            let elapsed = timestamp.timeIntervalSince(start)
            guard elapsed >= rule.duration else { continue }
            if let lastFired = state.lastFired, timestamp.timeIntervalSince(lastFired) < rule.cooldown { continue }
            events.append(
                AlertEvent(
                    kind: rule.kind, timestamp: timestamp, value: value, threshold: rule.threshold, duration: elapsed)
            )
            state.lastFired = timestamp
            state.latched = true
            state.pendingSince = nil
        }
        return events
    }

    /// Suspension is not recovery. Keep breach latches and cooldown timestamps
    /// while requiring fresh observations to build any pending duration.
    mutating func interrupt() {
        resetPending()
        lastEvaluation = nil
    }

    private mutating func resetPending() {
        for kind in Array(states.keys) {
            states[kind]?.pendingSince = nil
            states[kind]?.lastReading = nil
        }
    }
}
