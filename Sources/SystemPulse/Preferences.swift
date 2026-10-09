import Foundation
import ServiceManagement
import SwiftUI

/// Injectable so tests never register or unregister the real login item.
@MainActor
protocol LoginItemClient {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor
private struct SystemLoginItemClient: LoginItemClient {
    private var isSupported: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
            && NSClassFromString("XCTestCase") == nil
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    var status: SMAppService.Status {
        isSupported ? SMAppService.mainApp.status : .notFound
    }

    func register() throws {
        guard isSupported else { throw LoginItemError.unsupported }
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        guard isSupported else { throw LoginItemError.unsupported }
        try SMAppService.mainApp.unregister()
    }

    private enum LoginItemError: LocalizedError {
        case unsupported
        var errorDescription: String? {
            "Launch at Login requires the installed SystemPulse app."
        }
    }
}

/// User-facing preferences backed by UserDefaults.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case gauges = "Gauges"
        case compact = "Compact"
        case detailed = "Detailed"
        case iconOnly = "Icon Only"

        var id: String { rawValue }
    }

    enum RefreshRate: Double, CaseIterable, Identifiable {
        case fast = 1.0
        case normal = 1.5
        case relaxed = 3.0

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .fast: return "Fast (1s)"
            case .normal: return "Normal (1.5s)"
            case .relaxed: return "Relaxed (3s)"
            }
        }
    }

    enum Appearance: String, Codable, CaseIterable, Identifiable {
        case system, light, dark

        var id: Self { self }
        var title: String { rawValue.capitalized }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    private let defaults: UserDefaults
    private let loginClient: any LoginItemClient

    var menuBarStyle: MenuBarStyle {
        didSet { defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    var refreshRate: RefreshRate {
        didSet { defaults.set(refreshRate.rawValue, forKey: Keys.refreshRate) }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    private var storedModules: [MetricTab]
    var visibleModules: [MetricTab] {
        get { storedModules }
        set {
            storedModules = Self.normalizeModules(newValue)
            defaults.set(storedModules.map(\.rawValue), forKey: Keys.visibleModules)
        }
    }

    private var storedMenuMetrics: [MenuBarMetric]
    var menuBarMetrics: [MenuBarMetric] {
        get { storedMenuMetrics }
        set {
            storedMenuMetrics = Self.normalizeMenuMetrics(newValue)
            persistMenuMetrics()
        }
    }

    /// Legacy callers use the same source of truth as the ordered metrics.
    var showNetworkInMenuBar: Bool {
        get { menuBarMetrics.contains(.network) }
        set { setMenuMetric(.network, enabled: newValue) }
    }

    @ObservationIgnored private var alertActivationRevision: UInt64 = 0
    @ObservationIgnored private var alertRuleRevisions: [AlertKind: UInt64] = [:]

    var alertsEnabled: Bool {
        didSet {
            if alertsEnabled != oldValue { alertActivationRevision &+= 1 }
            defaults.set(alertsEnabled, forKey: Keys.alertsEnabled)
        }
    }

    /// Session-only tokens make transient opt-outs/rule edits observable even if
    /// the final values match a previous sampling pass. Never persisted.
    func alertConfigurationToken(for kind: AlertKind) -> AlertConfigurationToken {
        AlertConfigurationToken(activation: alertActivationRevision, rule: alertRuleRevisions[kind] ?? 0)
    }

    var alertConfigurationTokens: [AlertKind: AlertConfigurationToken] {
        Dictionary(uniqueKeysWithValues: AlertKind.allCases.map { ($0, alertConfigurationToken(for: $0)) })
    }

    private var storedAlertRules: [AlertRule]
    var alertRules: [AlertRule] {
        get { storedAlertRules }
        set {
            let normalized = Self.normalizeAlertRules(newValue)
            for rule in normalized where storedAlertRules.first(where: { $0.kind == rule.kind }) != rule {
                alertRuleRevisions[rule.kind, default: 0] &+= 1
            }
            storedAlertRules = normalized
            persistAlertRules()
        }
    }

    var showInsights: Bool {
        didSet { defaults.set(showInsights, forKey: Keys.showInsights) }
    }

    private(set) var launchAtLogin: Bool
    private(set) var loginStatusLabel = ""
    private(set) var loginError: String?

    var displayedTopics: [MetricTab] { [.overview] + visibleModules }

    func isModuleVisible(_ tab: MetricTab) -> Bool {
        tab == .overview || visibleModules.contains(tab)
    }

    func setModule(_ tab: MetricTab, enabled: Bool) {
        guard tab != .overview else { return }
        visibleModules = enabled ? visibleModules + [tab] : visibleModules.filter { $0 != tab }
    }

    func setMenuMetric(_ metric: MenuBarMetric, enabled: Bool) {
        menuBarMetrics = enabled ? menuBarMetrics + [metric] : menuBarMetrics.filter { $0 != metric }
    }

    func moveMenuMetric(_ metric: MenuBarMetric, by offset: Int) {
        guard let index = menuBarMetrics.firstIndex(of: metric) else { return }
        // Saturate before addition, including Int.min/Int.max from callers.
        let destination = index + min(max(offset, -index), menuBarMetrics.count - 1 - index)
        guard destination != index else { return }
        var metrics = menuBarMetrics
        metrics.remove(at: index)
        metrics.insert(metric, at: destination)
        menuBarMetrics = metrics
    }

    private enum Keys {
        static let menuBarStyle = "prefs.menuBarStyle"
        static let refreshRate = "prefs.refreshRate"
        static let showNetwork = "prefs.showNetwork"
        static let appearance = "prefs.appearance"
        static let visibleModules = "prefs.visibleModules"
        static let menuBarMetrics = "prefs.menuBarMetrics"
        static let alertsEnabled = "prefs.alertsEnabled"
        static let alertRules = "prefs.alertRules"
        static let showInsights = "prefs.showInsights"
    }

    init(defaults: UserDefaults = .standard, loginClient: (any LoginItemClient)? = nil) {
        self.defaults = defaults
        self.loginClient = loginClient ?? SystemLoginItemClient()
        if let raw = defaults.string(forKey: Keys.menuBarStyle),
            let style = MenuBarStyle(rawValue: raw)
        {
            menuBarStyle = style
        } else {
            menuBarStyle = .gauges
        }

        let rate = defaults.double(forKey: Keys.refreshRate)
        refreshRate = RefreshRate(rawValue: rate) ?? .normal
        appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        let modules = Self.savedStrings(defaults, key: Keys.visibleModules)
        storedModules = Self.normalizeModules(
            modules?.compactMap(MetricTab.init(rawValue:)) ?? MetricTab.allCases)
        let metrics = Self.savedStrings(defaults, key: Keys.menuBarMetrics)
        let legacyNetwork = defaults.object(forKey: Keys.showNetwork) as? Bool ?? false
        storedMenuMetrics = Self.normalizeMenuMetrics(
            metrics?.compactMap(MenuBarMetric.init(rawValue:))
                ?? ([.cpu, .memory] + (legacyNetwork ? [.network] : [])))
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? false
        storedAlertRules = Self.normalizeAlertRules(Self.savedAlertRules(defaults) ?? AlertRule.defaults)
        showInsights = defaults.object(forKey: Keys.showInsights) as? Bool ?? true
        launchAtLogin = false
        refreshLaunchAtLoginStatus()

        // Save canonical values once; a new metrics key takes precedence over the old network flag.
        defaults.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle)
        defaults.set(refreshRate.rawValue, forKey: Keys.refreshRate)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(storedModules.map(\.rawValue), forKey: Keys.visibleModules)
        defaults.set(alertsEnabled, forKey: Keys.alertsEnabled)
        defaults.set(showInsights, forKey: Keys.showInsights)
        persistMenuMetrics()
        persistAlertRules()
    }

    /// Returns actionable feedback; the toggle always reflects the service's actual state.
    @discardableResult
    func setLaunchAtLogin(_ enabled: Bool) -> String? {
        loginError = nil
        do {
            if enabled {
                try loginClient.register()
            } else {
                try loginClient.unregister()
            }
        } catch {
            loginError = "Could not change Launch at Login: \(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
        return loginError ?? (loginClient.status == .requiresApproval ? loginStatusLabel : nil)
    }

    func refreshLaunchAtLoginStatus() {
        let status = loginClient.status
        launchAtLogin = status == .enabled
        switch status {
        case .enabled: loginStatusLabel = "Enabled"
        case .notRegistered: loginStatusLabel = "Off"
        case .requiresApproval:
            loginStatusLabel = "Allow SystemPulse in System Settings → General → Login Items."
        case .notFound: loginStatusLabel = "Unavailable. Use the installed SystemPulse app."
        @unknown default: loginStatusLabel = "Login item status unavailable."
        }
    }

    private static func normalizeModules(_ modules: [MetricTab]) -> [MetricTab] {
        let normalized = MetricTab.allCases.filter { $0 != .overview && modules.contains($0) }
        return normalized.isEmpty ? [.cpu] : normalized
    }

    private static func normalizeMenuMetrics(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        var seen = Set<MenuBarMetric>()
        let normalized = metrics.filter { seen.insert($0).inserted }
        return normalized.isEmpty ? [.cpu] : normalized
    }

    private static func normalizeAlertRules(_ rules: [AlertRule]) -> [AlertRule] {
        // The engine owns numeric safety bounds; settings must show exactly what it evaluates.
        AlertRule.defaults.map { fallback in
            (rules.first { $0.kind == fallback.kind } ?? fallback).normalized()
        }
    }

    private static func savedStrings(_ defaults: UserDefaults, key: String) -> [String]? {
        guard let value = defaults.object(forKey: key) else { return nil }
        if let entries = value as? [Any] { return entries.compactMap { $0 as? String } }
        if let data = value as? Data, let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return entries.compactMap { $0 as? String }
        }
        return []
    }

    private static func savedAlertRules(_ defaults: UserDefaults) -> [AlertRule]? {
        guard let value = defaults.object(forKey: Keys.alertRules) else { return nil }
        guard let data = value as? Data,
            let entries = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [] }
        // Decode separately so an unknown future kind doesn't discard other, valid rules.
        return entries.compactMap { entry in
            guard JSONSerialization.isValidJSONObject(entry),
                let data = try? JSONSerialization.data(withJSONObject: entry)
            else { return nil }
            return try? JSONDecoder().decode(AlertRule.self, from: data)
        }
    }

    private func persistMenuMetrics() {
        defaults.set(storedMenuMetrics.map(\.rawValue), forKey: Keys.menuBarMetrics)
        defaults.set(storedMenuMetrics.contains(.network), forKey: Keys.showNetwork)
    }

    private func persistAlertRules() {
        if let data = try? JSONEncoder().encode(storedAlertRules) {
            defaults.set(data, forKey: Keys.alertRules)
        }
    }
}
