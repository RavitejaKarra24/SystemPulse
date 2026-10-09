import ServiceManagement
import SwiftUI
import XCTest

@testable import SystemPulse

final class PreferencesTests: XCTestCase {
    @MainActor
    func testDefaultsAreSafeAndDoNotChangeLoginRegistration() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.menuBarStyle, .gauges)
        XCTAssertEqual(preferences.refreshRate, .normal)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertNil(preferences.appearance.colorScheme)
        XCTAssertEqual(preferences.displayedTopics, MetricTab.allCases)
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu, .memory])
        XCTAssertFalse(preferences.alertsEnabled)
        XCTAssertTrue(preferences.showInsights)
        XCTAssertEqual(preferences.alertRules, AlertRule.defaults)
        XCTAssertEqual(fixture.login.registerCalls, 0)
        XCTAssertEqual(fixture.login.unregisterCalls, 0)
    }

    @MainActor
    func testAlertTokensTrackOnlyEffectiveChangesAndDoNotPersist() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let initial = preferences.alertConfigurationTokens
        preferences.alertsEnabled = false
        preferences.alertRules = AlertRule.defaults
        XCTAssertEqual(preferences.alertConfigurationTokens, initial)
        preferences.alertsEnabled = true
        preferences.alertsEnabled = false
        XCTAssertNotEqual(preferences.alertConfigurationTokens, initial)
        let beforeEdit = preferences.alertConfigurationTokens
        let rules = preferences.alertRules
        var edited = rules
        edited[0].threshold = 99
        preferences.alertRules = edited
        preferences.alertRules = rules
        XCTAssertNotEqual(preferences.alertConfigurationToken(for: .cpuUsage), beforeEdit[.cpuUsage])
        XCTAssertEqual(preferences.alertConfigurationToken(for: .diskAvailable), beforeEdit[.diskAvailable])
        XCTAssertEqual(fixture.makePreferences().alertConfigurationTokens, initial, "Tokens are session-only")
    }

    @MainActor
    func testMigratesLegacyKeysAndRetainsOldEnumValues() async throws {
        let fixture = try SettingsPreferencesFixture()
        fixture.defaults.set("Detailed", forKey: "prefs.menuBarStyle")
        fixture.defaults.set(3.0, forKey: "prefs.refreshRate")
        fixture.defaults.set(true, forKey: "prefs.showNetwork")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.menuBarStyle, .detailed)
        XCTAssertEqual(preferences.refreshRate, .relaxed)
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu, .memory, .network])
        XCTAssertTrue(preferences.showNetworkInMenuBar)
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "prefs.menuBarMetrics"), ["cpu", "memory", "network"])
        preferences.showNetworkInMenuBar = false
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu, .memory])
        XCTAssertFalse(fixture.defaults.bool(forKey: "prefs.showNetwork"))
        preferences.setMenuMetric(.network, enabled: true)
        XCTAssertTrue(preferences.showNetworkInMenuBar)
        XCTAssertTrue(fixture.defaults.bool(forKey: "prefs.showNetwork"))
        XCTAssertEqual(fixture.makePreferences().menuBarMetrics, preferences.menuBarMetrics)
    }

    @MainActor
    func testNewMetricListWinsOverContradictoryLegacyFlag() async throws {
        let fixture = try SettingsPreferencesFixture()
        fixture.defaults.set(true, forKey: "prefs.showNetwork")
        fixture.defaults.set(["battery", "memory", "battery", "future", "cpu"], forKey: "prefs.menuBarMetrics")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.menuBarMetrics, [.battery, .memory, .cpu])
        XCTAssertFalse(preferences.showNetworkInMenuBar)
        XCTAssertFalse(fixture.defaults.bool(forKey: "prefs.showNetwork"))
        preferences.showNetworkInMenuBar = true
        XCTAssertEqual(preferences.menuBarMetrics, [.battery, .memory, .cpu, .network])
        preferences.showNetworkInMenuBar = true
        XCTAssertEqual(preferences.menuBarMetrics.filter { $0 == .network }.count, 1)
    }

    @MainActor
    func testNormalizesUnknownDuplicateAndOverviewModules() async throws {
        let fixture = try SettingsPreferencesFixture()
        fixture.defaults.set(["Power", "Overview", "Memory", "Power", "Unknown"], forKey: "prefs.visibleModules")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.visibleModules, [.memory, .power])
        XCTAssertEqual(preferences.displayedTopics, [.overview, .memory, .power])
        XCTAssertTrue(preferences.isModuleVisible(.overview))
        XCTAssertFalse(preferences.isModuleVisible(.disk))
        preferences.setModule(.overview, enabled: false)
        XCTAssertTrue(preferences.isModuleVisible(.overview))
        preferences.setModule(.disk, enabled: true)
        preferences.setModule(.disk, enabled: true)
        XCTAssertEqual(preferences.visibleModules, [.memory, .disk, .power])
        XCTAssertEqual(fixture.makePreferences().visibleModules, [.memory, .disk, .power])
    }

    @MainActor
    func testEmptyListsAlwaysRestoreCPU() async throws {
        let fixture = try SettingsPreferencesFixture()
        fixture.defaults.set(["future"], forKey: "prefs.menuBarMetrics")
        fixture.defaults.set([], forKey: "prefs.visibleModules")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu])
        XCTAssertEqual(preferences.visibleModules, [.cpu])
        preferences.setModule(.cpu, enabled: false)
        preferences.setMenuMetric(.cpu, enabled: false)
        XCTAssertEqual(preferences.displayedTopics, [.overview, .cpu])
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu])
        preferences.visibleModules = [.overview]
        preferences.menuBarMetrics = []
        XCTAssertEqual(fixture.makePreferences().visibleModules, [.cpu])
        XCTAssertEqual(fixture.makePreferences().menuBarMetrics, [.cpu])
    }

    @MainActor
    func testMalformedPreferencesAndJSONListsAreNormalized() async throws {
        let fixture = try SettingsPreferencesFixture()
        fixture.defaults.set("future", forKey: "prefs.menuBarStyle")
        fixture.defaults.set("invalid", forKey: "prefs.refreshRate")
        fixture.defaults.set("future", forKey: "prefs.appearance")
        fixture.defaults.set(
            try JSONEncoder().encode(["disk", "cpu", "disk", "future"]), forKey: "prefs.menuBarMetrics")
        fixture.defaults.set(42, forKey: "prefs.visibleModules")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.menuBarStyle, .gauges)
        XCTAssertEqual(preferences.refreshRate, .normal)
        XCTAssertEqual(preferences.appearance, .system)
        XCTAssertEqual(preferences.menuBarMetrics, [.disk, .cpu])
        XCTAssertEqual(preferences.visibleModules, [.cpu])
        XCTAssertEqual(fixture.defaults.stringArray(forKey: "prefs.menuBarMetrics"), ["disk", "cpu"])
    }

    @MainActor
    func testMixedSavedTypesKeepValidOptionsAndCorruptRulesUseDefaults() async throws {
        let fixture = try SettingsPreferencesFixture()
        fixture.defaults.set(["Power", 42, "Memory", "future"] as [Any], forKey: "prefs.visibleModules")
        let metrics: [Any] = ["battery", false, "disk", ["unexpected": "object"], "battery"]
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: metrics), forKey: "prefs.menuBarMetrics")
        fixture.defaults.set(Data("not JSON".utf8), forKey: "prefs.alertRules")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.visibleModules, [.memory, .power])
        XCTAssertEqual(preferences.menuBarMetrics, [.battery, .disk])
        XCTAssertEqual(preferences.alertRules, AlertRule.defaults)
        XCTAssertFalse(preferences.alertsEnabled)
    }

    @MainActor
    func testOrderedMetricsMoveSafelyAndPersist() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        preferences.menuBarMetrics = [.cpu, .memory, .disk, .memory, .battery]
        preferences.moveMenuMetric(.disk, by: -1)
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu, .disk, .memory, .battery])
        preferences.moveMenuMetric(.battery, by: .min)
        XCTAssertEqual(preferences.menuBarMetrics, [.battery, .cpu, .disk, .memory])
        preferences.moveMenuMetric(.battery, by: .max)
        XCTAssertEqual(preferences.menuBarMetrics, [.cpu, .disk, .memory, .battery])
        preferences.moveMenuMetric(.network, by: 1)
        XCTAssertEqual(fixture.makePreferences().menuBarMetrics, [.cpu, .disk, .memory, .battery])
    }

    @MainActor
    func testImmediatePersistenceForAllNewAndExistingOptions() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        preferences.appearance = .dark
        preferences.refreshRate = .fast
        preferences.menuBarStyle = .compact
        preferences.alertsEnabled = true
        preferences.showInsights = false
        preferences.visibleModules = [.network, .memory, .network]
        preferences.menuBarMetrics = [.battery, .cpu]
        var rules = preferences.alertRules
        rules[0].enabled = false
        rules[0].threshold = 88
        preferences.alertRules = rules
        let restored = fixture.makePreferences()
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.appearance.colorScheme, .dark)
        preferences.appearance = .light
        XCTAssertEqual(preferences.appearance.colorScheme, .light)
        XCTAssertEqual(restored.refreshRate, .fast)
        XCTAssertEqual(restored.menuBarStyle, .compact)
        XCTAssertTrue(restored.alertsEnabled)
        XCTAssertFalse(restored.showInsights)
        XCTAssertEqual(restored.visibleModules, [.memory, .network])
        XCTAssertEqual(restored.menuBarMetrics, [.battery, .cpu])
        XCTAssertEqual(restored.alertRules, preferences.alertRules)
        XCTAssertEqual(fixture.login.registerCalls + fixture.login.unregisterCalls, 0)
    }

    @MainActor
    func testAlertNormalizationUsesEngineBoundsAndRejectsNonfiniteNumbers() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        var cpu = AlertRule(kind: .cpuUsage)
        cpu.threshold = .nan
        cpu.duration = -.infinity
        cpu.cooldown = 0
        var disk = AlertRule(kind: .diskAvailable)
        disk.threshold = -1
        disk.duration = .greatestFiniteMagnitude
        disk.cooldown = .infinity
        var thermal = AlertRule(kind: .thermal)
        thermal.threshold = 2.2
        preferences.alertRules = [cpu, disk, cpu, thermal]
        XCTAssertEqual(preferences.alertRules.count, AlertKind.allCases.count)
        XCTAssertEqual(preferences.alertRules.first { $0.kind == .cpuUsage }, cpu.normalized())
        XCTAssertEqual(preferences.alertRules.first { $0.kind == .diskAvailable }, disk.normalized())
        XCTAssertEqual(preferences.alertRules.first { $0.kind == .thermal }?.threshold, 3)
        for rule in preferences.alertRules {
            XCTAssertTrue(rule.threshold.isFinite && rule.duration.isFinite && rule.cooldown.isFinite)
            XCTAssertGreaterThanOrEqual(rule.duration, AlertRule.minimumDuration)
            XCTAssertGreaterThanOrEqual(rule.cooldown, AlertRule.minimumCooldown)
        }
        XCTAssertEqual(fixture.makePreferences().alertRules, preferences.alertRules)
    }

    @MainActor
    func testUnknownSavedAlertKindsDoNotDiscardKnownRules() async throws {
        let fixture = try SettingsPreferencesFixture()
        let entries: [[String: Any]] = [
            ["kind": "futureKind", "enabled": true, "threshold": 50],
            ["kind": "cpuUsage", "enabled": false, "threshold": 82, "duration": 90, "cooldown": 1800],
            ["kind": "cpuUsage", "enabled": true, "threshold": 75],
            ["kind": "diskAvailable", "threshold": "malformed"],
        ]
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: entries), forKey: "prefs.alertRules")
        let preferences = fixture.makePreferences()
        XCTAssertEqual(preferences.alertRules.map(\.kind), AlertKind.allCases)
        let cpu = try XCTUnwrap(preferences.alertRules.first { $0.kind == .cpuUsage })
        XCTAssertFalse(cpu.enabled)
        XCTAssertEqual(cpu.threshold, 82)
        XCTAssertEqual(cpu.duration, 90)
        XCTAssertEqual(cpu.cooldown, 1800)
        XCTAssertEqual(preferences.alertRules.first { $0.kind == .diskAvailable }?.threshold, 5 * 1_073_741_824)
        XCTAssertFalse(preferences.alertsEnabled)
        XCTAssertEqual(fixture.makePreferences().alertRules, preferences.alertRules)
    }

    @MainActor
    func testLoginToggleReflectsActualStateApprovalAndFailure() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        fixture.login.registrationResult = .requiresApproval
        XCTAssertNotNil(preferences.setLaunchAtLogin(true))
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertTrue(preferences.loginStatusLabel.contains("Login Items"))
        fixture.login.status = .enabled
        preferences.refreshLaunchAtLoginStatus()
        XCTAssertTrue(preferences.launchAtLogin)
        fixture.login.error = SettingsLoginTestError.refused
        XCTAssertNotNil(preferences.setLaunchAtLogin(false))
        XCTAssertTrue(preferences.launchAtLogin, "A failed unregister must not turn off the toggle")
        XCTAssertNotNil(preferences.loginError)
        fixture.login.error = nil
        XCTAssertNil(preferences.setLaunchAtLogin(false))
        XCTAssertFalse(preferences.launchAtLogin)
        XCTAssertNil(preferences.loginError)
        XCTAssertEqual(fixture.login.registerCalls, 1)
        XCTAssertEqual(fixture.login.unregisterCalls, 2)
    }

    @MainActor
    func testDiskDisplayConversionNeverPersistsGBAsBytes() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        var rules = preferences.alertRules
        let index = try XCTUnwrap(rules.firstIndex { $0.kind == .diskAvailable })
        let bytes = rules[index].threshold
        XCTAssertEqual(
            SettingsAlertUnits.displayedThreshold(bytes, kind: .diskAvailable), 5.36870912, accuracy: 0.00000001)
        rules[index].threshold = SettingsAlertUnits.storedThreshold(12.5, kind: .diskAvailable)
        preferences.alertRules = rules
        XCTAssertEqual(fixture.makePreferences().alertRules[index].threshold, 12_500_000_000)
        XCTAssertEqual(SettingsAlertUnits.storedThreshold(90, kind: .cpuUsage), 90)
    }
}

@MainActor
final class SettingsPreferencesFixture {
    let suiteName = "SystemPulse.SettingsTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let login = SettingsLoginTestClient()

    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }

    func makePreferences() -> Preferences {
        Preferences(defaults: defaults, loginClient: login)
    }
}

private enum SettingsLoginTestError: LocalizedError {
    case refused
    var errorDescription: String? { "Registration refused by test client" }
}

@MainActor
final class SettingsLoginTestClient: LoginItemClient {
    var status: SMAppService.Status = .notRegistered
    var registrationResult: SMAppService.Status = .enabled
    var error: Error?
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0

    func register() throws {
        registerCalls += 1
        if let error { throw error }
        status = registrationResult
    }

    func unregister() throws {
        unregisterCalls += 1
        if let error { throw error }
        status = .notRegistered
    }
}
