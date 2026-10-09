import AppKit
import Darwin
import ServiceManagement
import SwiftUI
import XCTest

@testable import SystemPulse

/// Opt-in, read-only process probe. Run each scenario in a separate release swift-test process.
final class PerformanceProbeTests: XCTestCase {
    @MainActor
    func testPerformanceProbe() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["SYSTEMPULSE_PERFORMANCE_SCENARIO"] else {
            throw XCTSkip("Opt in with scripts/measure-performance.sh; ordinary tests never start this probe")
        }
        try requireReleaseBuild()
        let scenario = try XCTUnwrap(Scenario(rawValue: name), "Unknown performance scenario: \(name)")
        let duration = try seconds(environment["SYSTEMPULSE_PERFORMANCE_DURATION"], default: 60, bounds: 30...3600)
        let warmup = try seconds(environment["SYSTEMPULSE_PERFORMANCE_WARMUP"], default: 15, bounds: 15...300)
        let output = try outputURL(environment["SYSTEMPULSE_PERFORMANCE_OUTPUT"])
        let timebase = cpuTimebase()

        // Never construct the app delegate, Preferences.shared, or any notification service.
        let suite = "SystemPulse.PerformanceProbe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults, loginClient: ProbeLoginItemClient())
        preferences.refreshRate = .normal
        preferences.menuBarStyle = .gauges
        preferences.menuBarMetrics = scenario == .hiddenDiskMenu ? [.cpu, .memory, .disk] : [.cpu, .memory]
        preferences.appearance = .light
        preferences.visibleModules = [.cpu, .memory, .network, .disk, .power]
        preferences.showInsights = true
        preferences.alertsEnabled = scenario.simulatesAuthorization
        preferences.alertRules = AlertRule.defaults.map { rule in
            var rule = rule
            rule.enabled = scenario != .hiddenDiskAlert || rule.kind == .diskAvailable
            return rule
        }

        var sinkCount = 0
        var store: MonitorStore? = MonitorStore(
            startPolling: true,
            processActions: ProcessActions(
                applicationRequest: { _, _ in false }, signalRequest: { _, _ in EPERM }, ownPID: getpid()),
            trashItem: { _ in false }, preferences: preferences, alertSink: { _ in sinkCount += 1 })
        store?.notificationDeliveryAllowed = scenario.simulatesAuthorization
        defer {
            store?.stopPolling()
            store = nil
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        defer { NSStatusBar.system.removeStatusItem(statusItem) }
        let render: @MainActor () -> Void = { [weak store] in
            guard let store, let button = statusItem.button else { return }
            store.synchronizePollingPreferences()
            let readings = store.menuBarReadings()
            let metrics = preferences.menuBarMetrics
            let style = preferences.menuBarStyle
            button.image = MenuBarRenderer.image(readings: readings, metrics: metrics, style: style)
            button.attributedTitle = MenuBarRenderer.title(readings: readings, metrics: metrics, style: style)
            let description = MenuBarRenderer.tooltipDescription(readings: readings, metrics: metrics)
            button.toolTip = description
        }
        var menuRenderCount = 0
        let menuTimer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                render()
                menuRenderCount += 1
            }
        }
        RunLoop.main.add(menuTimer, forMode: .common)
        defer { menuTimer.invalidate() }
        render()

        var window: ProbeWindow?
        if scenario == .openOverview, let store {
            guard let screen = NSScreen.main else { throw ProbeError.invalid("Overview needs a logged-in GUI session") }
            let height = min(CGFloat(720), screen.visibleFrame.height - 90)
            let frame = NSRect(x: 0, y: 0, width: Theme.popoverWidth, height: height)
            let hosting = NSHostingView(rootView: RootView(store: store, preferences: preferences, panelHeight: height))
            let opened = ProbeWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            opened.isReleasedWhenClosed = false
            opened.title = "SystemPulse performance probe — Overview (input disabled)"
            opened.ignoresMouseEvents = true
            opened.appearance = NSAppearance(named: .aqua)
            opened.contentView = hosting
            hosting.frame = frame
            opened.center()
            store.isPanelVisible = true
            // A SwiftPM XCTest host is not the installed accessory application.
            // Do not activate that host or depend on key-window ownership; show
            // a native, nonactivating render surface and report its actual state.
            opened.orderFrontRegardless()
            hosting.layoutSubtreeIfNeeded()
            window = opened
        }
        defer {
            store?.isPanelVisible = false
            window?.orderOut(nil)
            window?.contentView = nil
            window?.close()
            window = nil
        }

        let warmupStart = ProcessInfo.processInfo.systemUptime
        // Suspending the main actor leaves RunLoop.main servicing AppKit, SwiftUI and common-mode timers.
        try await Task.sleep(for: .seconds(warmup))
        let actualWarmup = ProcessInfo.processInfo.systemUptime - warmupStart
        if let window {
            guard window.isVisible else {
                throw ProbeError.invalid("Overview window must be visible; run in an active GUI session")
            }
        }
        guard store?.latestSampleAt != nil else {
            throw ProbeError.invalid("Polling produced no samples during warmup")
        }

        let startedAt = Date()
        let startUptime = ProcessInfo.processInfo.systemUptime
        let sinkStart = sinkCount
        let renderStart = menuRenderCount
        let processRevisionStart = store?.processSampleRevision ?? 0
        var samples = [capture(elapsed: 0, timebase: timebase)]
        while true {
            let remaining = duration - (ProcessInfo.processInfo.systemUptime - startUptime)
            if remaining <= 0 { break }
            try await Task.sleep(for: .seconds(min(5, remaining)))
            samples.append(capture(elapsed: ProcessInfo.processInfo.systemUptime - startUptime, timebase: timebase))
        }
        let elapsed = try XCTUnwrap(samples.last).elapsedSeconds
        let start = try XCTUnwrap(samples.first)
        let end = try XCTUnwrap(samples.last)
        let user = delta(start.userNanoseconds.value, end.userNanoseconds.value)
        let system = delta(start.systemNanoseconds.value, end.systemNanoseconds.value)
        let cpuNanoseconds = sum(user, system)
        // A zero package counter may mean unsupported hardware accounting, not zero wakeups.
        let idle = delta(start.packageIdleWakeups.value, end.packageIdleWakeups.value)
        let footprints = samples.compactMap { $0.physicalFootprintBytes.value }
        let report = Report(
            scenario: scenario.rawValue, startedAt: startedAt, endedAt: Date(), pid: getpid(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            toolchain: environment["SYSTEMPULSE_PERFORMANCE_TOOLCHAIN"] ?? "Not supplied (use the shell harness)",
            logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount, cpuTimebase: Nullable(timebase),
            requestedWarmupSeconds: warmup, actualWarmupSeconds: actualWarmup,
            requestedDurationSeconds: duration, actualDurationSeconds: elapsed,
            authorizationSimulated: scenario.simulatesAuthorization,
            menuMetrics: preferences.menuBarMetrics.map(\.rawValue), menuStyle: preferences.menuBarStyle.rawValue,
            enabledAlertRules: preferences.alertsEnabled ? preferences.alertRules.filter(\.enabled) : [],
            panelVisible: store?.isPanelVisible ?? false, overviewWindowKey: window?.isKeyWindow ?? false,
            overviewWindowUnoccluded: window?.occlusionState.contains(.visible) ?? false,
            alertSinkCountDuringMeasurement: sinkCount - sinkStart, alertSinkCountIncludingWarmup: sinkCount,
            menuTimerTicksDuringMeasurement: menuRenderCount - renderStart,
            processRefreshesDuringMeasurement: (store?.processSampleRevision ?? 0) - processRevisionStart,
            cadence: [
                "pollSeconds": preferences.refreshRate.rawValue, "menuRendererSeconds": 1,
                "probeSampleSeconds": 5, "powerMinimumSeconds": 5,
                "hiddenProcessMinimumSeconds": 15, "visibleProcessMinimumSeconds": 3,
                "diskMenuMinimumSeconds": 10, "authorizedDiskAlertMinimumSeconds": 5,
                "visibleVolumeMinimumSeconds": 10,
            ],
            summary: Summary(
                userCPUNanoseconds: Nullable(user), systemCPUNanoseconds: Nullable(system),
                totalCPUNanoseconds: Nullable(cpuNanoseconds),
                cpuPercentOneCore: Nullable(cpuNanoseconds.map { Double($0) / 1_000_000_000 / elapsed * 100 }),
                physicalFootprintStartBytes: start.physicalFootprintBytes,
                physicalFootprintEndBytes: end.physicalFootprintBytes,
                physicalFootprintMinBytes: Nullable(footprints.min()),
                physicalFootprintMaxBytes: Nullable(footprints.max()),
                packageIdleWakeupsDelta: Nullable(idle),
                packageIdleWakeupsPerSecond: Nullable(idle.map { Double($0) / elapsed })),
            samples: samples,
            caveats: [
                "Release SwiftPM XCTest process; includes AppKit, test runtime, probe sampling and renderer overhead, not the packaged app.",
                "Fresh subprocess per scenario; no app delegate or notification APIs, requests, permissions or real delivery. Authorization is a store Boolean simulation; alert sink only counts events.",
                "Private UUID UserDefaults suite is removed on normal exit; mock login client never queries or registers a real service. Forced termination may leave the disposable suite.",
                "Read-only live host sampling and process enumeration; no cleanup scans, deletion, signals or external requests. Overview window discards input to stay on Overview.",
                "Light appearance, normal 1.5-second polling, gauges and insights enabled. Overview is a real NSHostingView/window, not the app popover; a transient real status item runs in all scenarios.",
                "Cadences are minimums checked on polling ticks, so work can occur later; probe footprint extrema are sampled every 5 seconds, not continuous peaks.",
                "proc_pid_rusage RUSAGE_INFO_V0: raw CPU counters are Mach ticks converted to nanoseconds with mach_timebase_info (checked full-width integer arithmetic). Footprint is bytes; idle wakeups are package-idle wakeups, not all timers/interrupts.",
                "Unavailable timebase or conversion overflow yields null CPU nanoseconds/percent, never a guessed 1:1 conversion; raw CPU ticks remain in samples.",
                "API failure yields explicit nulls and errno; zero footprint and zero idle counters are conservatively treated as unavailable. Nil idle delta can also mean no observed accounting, not proof of zero wakeups.",
                "CPU percent uses one core as 100 percent and can exceed 100; wall time is monotonic system uptime. No energy/joules claim or performance pass/fail threshold.",
                "Keep other workloads, power source, thermal state, OS/toolchain and GUI visibility consistent. Overview is shown without activating the XCTest host; key-window and occlusion flags are reported, not assumed. Do not interact with or cover the window; no performance assertions across machines.",
                "Shutdown releases window/status item, invalidates the renderer and calls store.stopPolling(); already-running synchronous OS queries finish but cannot publish after shutdown.",
            ])
        guard store?.isScanning == false, store?.diskCategories.isEmpty == true else {
            throw ProbeError.invalid("Probe unexpectedly entered cleanup scanning")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // Output is required to be new; the shell harness supplies a private staging directory.
        guard (try? FileManager.default.attributesOfItem(atPath: output.path)) == nil else {
            throw ProbeError.invalid("Output already exists")
        }
        try encoder.encode(report).write(to: output, options: .atomic)
        print("Performance probe \(scenario.rawValue): \(elapsed)s; JSON: \(output.path)")
    }

    private func requireReleaseBuild() throws {
        #if DEBUG
            throw ProbeError.invalid("Performance probes require swift test -c release")
        #endif
    }

    private func seconds(_ raw: String?, default fallback: Double, bounds: ClosedRange<Double>) throws -> Double {
        guard let raw else { return fallback }
        guard let value = Double(raw), value.isFinite, bounds.contains(value) else {
            throw ProbeError.invalid("Seconds must be finite and within \(bounds)")
        }
        return value
    }

    private func outputURL(_ path: String?) throws -> URL {
        guard let path, path.hasPrefix("/"), !path.contains("\n"), !path.contains("\r") else {
            throw ProbeError.invalid("SYSTEMPULSE_PERFORMANCE_OUTPUT must be an absolute path to a new JSON file")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var directory: ObjCBool = false
        guard url.pathExtension == "json", (try? FileManager.default.attributesOfItem(atPath: url.path)) == nil,
            FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &directory),
            directory.boolValue
        else { throw ProbeError.invalid("Output must be a new .json file in an existing non-symlink directory") }
        // Foundation's resolvingSymlinksInPath can rewrite canonical /private/tmp back to /tmp.
        // Inspect each existing ancestor's actual file type instead of comparing rewritten URL strings.
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
            let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw ProbeError.invalid("Output ancestors must be directories, not symlinks")
            }
            parent.deleteLastPathComponent()
        }
        return url
    }

    private func cpuTimebase() -> MachTimebase? {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else { return nil }
        return MachTimebase(numerator: info.numer, denominator: info.denom)
    }

    private func nanoseconds(_ ticks: UInt64?, timebase: MachTimebase?) -> UInt64? {
        guard let ticks, let timebase else { return nil }
        let denominator = UInt64(timebase.denominator)
        let product = ticks.multipliedFullWidth(by: UInt64(timebase.numerator))
        // dividingFullWidth traps if the quotient cannot fit; report unavailable instead.
        guard product.high < denominator else { return nil }
        return denominator.dividingFullWidth(product).quotient
    }

    private func capture(elapsed: Double, timebase: MachTimebase?) -> Sample {
        var info = rusage_info_v0()
        // The C signature is void**, but the kernel copies a V0 structure into this allocated V0 buffer.
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V0, $0)
            }
        }
        let error = result == 0 ? nil : errno
        let userTicks = result == 0 ? info.ri_user_time : nil
        let systemTicks = result == 0 ? info.ri_system_time : nil
        return Sample(
            elapsedSeconds: elapsed, userMachTicks: Nullable(userTicks), systemMachTicks: Nullable(systemTicks),
            userNanoseconds: Nullable(nanoseconds(userTicks, timebase: timebase)),
            systemNanoseconds: Nullable(nanoseconds(systemTicks, timebase: timebase)),
            physicalFootprintBytes: Nullable(result == 0 && info.ri_phys_footprint > 0 ? info.ri_phys_footprint : nil),
            packageIdleWakeups: Nullable(result == 0 && info.ri_pkg_idle_wkups > 0 ? info.ri_pkg_idle_wkups : nil),
            errorCode: Nullable(error))
    }

    private func delta(_ start: UInt64?, _ end: UInt64?) -> UInt64? {
        guard let start, let end, end >= start else { return nil }
        return end - start
    }

    private func sum(_ lhs: UInt64?, _ rhs: UInt64?) -> UInt64? {
        guard let lhs, let rhs else { return nil }
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? nil : result.partialValue
    }
}

private enum ProbeError: Error {
    case invalid(String)
}

private enum Scenario: String {
    case hiddenDefault = "hidden-default"
    case hiddenDiskMenu = "hidden-disk-menu"
    case hiddenAlerts = "hidden-alerts"
    case hiddenDiskAlert = "hidden-disk-alert"
    case openOverview = "open-overview"

    var simulatesAuthorization: Bool { self == .hiddenAlerts || self == .hiddenDiskAlert }
}

@MainActor
private struct ProbeLoginItemClient: LoginItemClient {
    var status: SMAppService.Status { .notRegistered }
    func register() throws { throw ProbeError.invalid("Probe cannot register login items") }
    func unregister() throws { throw ProbeError.invalid("Probe cannot unregister login items") }
}

@MainActor
private final class ProbeWindow: NSWindow {
    // Keep AppKit's lifecycle/expose/occlusion events intact. Discarding every
    // sendEvent also suppresses native window bookkeeping. Mouse input is
    // disabled at the WindowServer boundary; the probe cannot take key focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Synthesized Optional encoding omits keys; counters must instead serialize unavailable values as JSON null.
private struct Nullable<Value: Encodable>: Encodable {
    let value: Value?
    init(_ value: Value?) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}

private struct MachTimebase: Encodable {
    let numerator: UInt32
    let denominator: UInt32
}

private struct Sample: Encodable {
    let elapsedSeconds: Double
    let userMachTicks: Nullable<UInt64>
    let systemMachTicks: Nullable<UInt64>
    let userNanoseconds: Nullable<UInt64>
    let systemNanoseconds: Nullable<UInt64>
    let physicalFootprintBytes: Nullable<UInt64>
    let packageIdleWakeups: Nullable<UInt64>
    let errorCode: Nullable<Int32>
}

private struct Summary: Encodable {
    let userCPUNanoseconds: Nullable<UInt64>
    let systemCPUNanoseconds: Nullable<UInt64>
    let totalCPUNanoseconds: Nullable<UInt64>
    let cpuPercentOneCore: Nullable<Double>
    let physicalFootprintStartBytes: Nullable<UInt64>
    let physicalFootprintEndBytes: Nullable<UInt64>
    let physicalFootprintMinBytes: Nullable<UInt64>
    let physicalFootprintMaxBytes: Nullable<UInt64>
    let packageIdleWakeupsDelta: Nullable<UInt64>
    let packageIdleWakeupsPerSecond: Nullable<Double>
}

private struct Report: Encodable {
    let schemaVersion = 1
    let buildConfiguration = "release"
    let swiftLanguageMode = "5"
    let resourceAPI = "proc_pid_rusage / RUSAGE_INFO_V0"
    let scenario: String
    let startedAt: Date
    let endedAt: Date
    let pid: pid_t
    let osVersion: String
    let toolchain: String
    let logicalCPUCount: Int
    let cpuTimebase: Nullable<MachTimebase>
    let requestedWarmupSeconds: Double
    let actualWarmupSeconds: Double
    let requestedDurationSeconds: Double
    let actualDurationSeconds: Double
    let authorizationSimulated: Bool
    let menuMetrics: [String]
    let menuStyle: String
    let enabledAlertRules: [AlertRule]
    let panelVisible: Bool
    let overviewWindowKey: Bool
    let overviewWindowUnoccluded: Bool
    let alertSinkCountDuringMeasurement: Int
    let alertSinkCountIncludingWarmup: Int
    let menuTimerTicksDuringMeasurement: Int
    let processRefreshesDuringMeasurement: UInt64
    let cadence: [String: Double]
    let summary: Summary
    let samples: [Sample]
    let caveats: [String]
}
