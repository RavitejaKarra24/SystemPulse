import Foundation

struct AlertConfigurationToken: Equatable, Sendable {
    let activation: UInt64
    let rule: UInt64
}

struct SampledAlertValue: Sendable {
    let value: Double
    let sampledAt: Date
}

/// CPU/memory arrive each pass; power and capacity arrive more slowly. Advance
/// each rule only on a NEW actual observation, never by re-dating a cached value.
struct AlertCoordinator {
    private var engines: [AlertKind: AlertEngine] = [:]
    private var consumed: [AlertKind: Date] = [:]
    private var lastFrame: Date?
    private var activatedAt: [AlertKind: Date] = [:]
    private var configured: [AlertKind: AlertRule] = [:]
    private var configurationTokens: [AlertKind: AlertConfigurationToken] = [:]

    mutating func interrupt() {
        for kind in engines.keys { engines[kind]?.interrupt() }
        consumed.removeAll()
        activatedAt.removeAll()
        lastFrame = nil
    }

    mutating func evaluate(
        _ measurements: [AlertKind: SampledAlertValue], at timestamp: Date,
        rules: [AlertRule], enabled: Bool,
        configuration: [AlertKind: AlertConfigurationToken] = [:]
    ) -> [AlertEvent] {
        guard enabled else {
            engines.removeAll()
            consumed.removeAll()
            lastFrame = nil
            activatedAt.removeAll()
            configured.removeAll()
            configurationTokens.removeAll()
            return []
        }
        let activeRules = AlertRule.normalized(rules).filter(\.enabled)
        let kinds = Set(activeRules.map(\.kind))
        engines = engines.filter { kinds.contains($0.key) }
        consumed = consumed.filter { kinds.contains($0.key) }
        activatedAt = activatedAt.filter { kinds.contains($0.key) }
        configured = configured.filter { kinds.contains($0.key) }
        configurationTokens = configurationTokens.filter { kinds.contains($0.key) }
        guard timestamp.timeIntervalSinceReferenceDate.isFinite,
            lastFrame.map({ timestamp > $0 }) ?? true
        else {
            for rule in activeRules {
                _ = engines[rule.kind]?.evaluate([:], at: timestamp, rules: [rule], enabled: true)
            }
            consumed.removeAll()
            lastFrame = timestamp.timeIntervalSinceReferenceDate.isFinite ? timestamp : nil
            activatedAt =
                lastFrame.map { date in
                    Dictionary(uniqueKeysWithValues: activeRules.map { ($0.kind, date) })
                } ?? [:]
            return []
        }
        lastFrame = timestamp
        var events: [AlertEvent] = []
        for rule in activeRules {
            if configured[rule.kind] != rule || configurationTokens[rule.kind] != configuration[rule.kind] {
                activatedAt[rule.kind] = timestamp
                consumed[rule.kind] = nil
                configured[rule.kind] = rule
                configurationTokens[rule.kind] = configuration[rule.kind]
                engines[rule.kind] = AlertEngine()
            }
            // Invalid frame dates clear watermarks, not latch/cooldown history.
            // Restore the watermark on the next valid frame so sampling recovers.
            if activatedAt[rule.kind] == nil { activatedAt[rule.kind] = timestamp }
            var engine = engines[rule.kind] ?? AlertEngine()
            defer { engines[rule.kind] = engine }
            guard let measurement = measurements[rule.kind] else {
                _ = engine.evaluate([:], at: timestamp, rules: [rule], enabled: true)
                consumed[rule.kind] = nil
                continue
            }
            let age = timestamp.timeIntervalSince(measurement.sampledAt)
            guard age.isFinite, age >= 0, age <= AlertEngine.maximumContinuityGap,
                activatedAt[rule.kind].map({ measurement.sampledAt >= $0 }) ?? false
            else {
                _ = engine.evaluate([:], at: timestamp, rules: [rule], enabled: true)
                consumed[rule.kind] = nil
                continue
            }
            if consumed[rule.kind] == measurement.sampledAt { continue }
            events += engine.evaluate(
                [rule.kind: measurement.value], at: measurement.sampledAt, rules: [rule], enabled: true)
            consumed[rule.kind] = measurement.sampledAt
        }
        return events
    }
}
