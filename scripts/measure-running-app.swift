import Darwin
import Foundation

// Internal entry point for measure-running-app.sh, not XCTest or app code.
// PID, exact birth identity, executable UUID and full paths never enter the report.
private struct ProbeError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

private struct Nullable<Value: Encodable>: Encodable {
    let value: Value?
    init(_ value: Value?) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value { try container.encode(value) } else { try container.encodeNil() }
    }
}

private struct Timebase: Encodable {
    let numerator: UInt32
    let denominator: UInt32

    init() throws {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else {
            throw ProbeError("Mach timebase unavailable; no CPU estimate published")
        }
        numerator = info.numer
        denominator = info.denom
    }

    func nanoseconds(_ ticks: UInt64) throws -> UInt64 {
        let divisor = UInt64(denominator)
        let product = ticks.multipliedFullWidth(by: UInt64(numerator))
        // dividingFullWidth traps if the quotient will not fit in UInt64.
        guard product.high < divisor else { throw ProbeError("CPU time conversion overflow") }
        return divisor.dividingFullWidth(product).quotient
    }
}

// Deliberately NOT Encodable. Birth times are integers, never lossy Date/Double values.
private struct Identity: Equatable {
    let startSeconds: UInt64
    let startMicroseconds: UInt64
    let startMachTicks: UInt64
    let executableUUID: [UInt8]
    let executablePath: String
}

private struct Observation {
    let identity: Identity
    let info: rusage_info_v0
    let uptime: Double
}

private func birth(_ pid: pid_t) throws -> (seconds: UInt64, microseconds: UInt64) {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
    guard count == size else {
        throw ProbeError("Process identity unavailable (errno \(errno)); target may have exited")
    }
    // SZOMB is 5 on Darwin. proc_pid_rusage can succeed for zombies, so reject explicitly.
    guard info.pbi_pid == UInt32(pid), info.pbi_status != 5,
        info.pbi_start_tvsec > 0, info.pbi_start_tvusec < 1_000_000
    else { throw ProbeError("Target exited or has an invalid start identity") }
    return (info.pbi_start_tvsec, info.pbi_start_tvusec)
}

private func executable(_ pid: pid_t) throws -> String {
    var name = [UInt8](repeating: 0, count: 1024)
    guard proc_name(pid, &name, UInt32(name.count)) > 0,
        let nameEnd = name.firstIndex(of: 0),
        String(bytes: name[..<nameEnd], encoding: .utf8) == "SystemPulse"
    else { throw ProbeError("Target is not a readable SystemPulse process") }

    var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
        let end = buffer.firstIndex(of: 0),
        let path = String(bytes: buffer[..<end], encoding: .utf8), path.hasPrefix("/")
    else { throw ProbeError("Target executable path unavailable") }
    // Validate the actual filesystem target, not a symlink named like an app executable.
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    let macOS = url.deletingLastPathComponent()
    let contents = macOS.deletingLastPathComponent()
    let app = contents.deletingLastPathComponent()
    guard url.lastPathComponent == "SystemPulse", macOS.lastPathComponent == "MacOS",
        contents.lastPathComponent == "Contents", app.pathExtension == "app",
        FileManager.default.isExecutableFile(atPath: url.path)
    else { throw ProbeError("Target is not an actual .app/Contents/MacOS/SystemPulse executable") }
    return url.path
}

private func observe(_ pid: pid_t, expected: Identity? = nil) throws -> Observation {
    let before = try birth(pid)
    let path = try executable(pid)
    var info = rusage_info_v0()
    // libproc's void** ABI writes a V0 structure into this allocated V0 buffer.
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V0, $0)
        }
    }
    let uptime = ProcessInfo.processInfo.systemUptime
    guard result == 0 else { throw ProbeError("Resource sampling failed (errno \(errno)); no report published") }
    guard info.ri_proc_start_abstime > 0, info.ri_proc_exit_abstime == 0 else {
        throw ProbeError("Target exited or resource start identity is unavailable")
    }
    let afterPath = try executable(pid)
    let after = try birth(pid)
    guard before.seconds == after.seconds, before.microseconds == after.microseconds, path == afterPath else {
        throw ProbeError("Target changed identity during capture (PID reuse/exec); no report published")
    }
    let identity = Identity(
        startSeconds: before.seconds, startMicroseconds: before.microseconds,
        startMachTicks: info.ri_proc_start_abstime,
        executableUUID: withUnsafeBytes(of: info.ri_uuid) { Array($0) }, executablePath: path)
    guard expected == nil || expected == identity else {
        throw ProbeError("Target changed identity (PID reuse/exec); no report published")
    }
    return Observation(identity: identity, info: info, uptime: uptime)
}

private struct AppMetadata: Encodable {
    let executableBasename = "SystemPulse"
    let bundleBasename: Nullable<String>
    let version: Nullable<String>
    let build: Nullable<String>
}

private func metadata(_ path: String) -> AppMetadata {
    let app = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    // Read only bundle metadata, never UserDefaults or the app's preference/permission state.
    let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) }
    let dictionary = plist as? [String: Any]
    func safe(_ value: String?, pattern: String) -> String? {
        guard let value, value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return value
    }
    return AppMetadata(
        bundleBasename: Nullable(safe(app.lastPathComponent, pattern: "^[A-Za-z0-9_-]{1,64}\\.app$")),
        version: Nullable(
            safe(dictionary?["CFBundleShortVersionString"] as? String, pattern: "^[0-9][A-Za-z0-9.+_-]{0,31}$")),
        build: Nullable(safe(dictionary?["CFBundleVersion"] as? String, pattern: "^[0-9][A-Za-z0-9.+_-]{0,31}$")))
}

private struct Sample: Encodable {
    let elapsedSeconds: Double
    let userMachTicks: UInt64
    let systemMachTicks: UInt64
    let userNanoseconds: UInt64
    let systemNanoseconds: UInt64
    let physicalFootprintBytes: Nullable<UInt64>
    let packageIdleWakeups: Nullable<UInt64>
}

private func sample(_ observation: Observation, start: Double, timebase: Timebase) throws -> Sample {
    let info = observation.info
    return Sample(
        elapsedSeconds: observation.uptime - start,
        userMachTicks: info.ri_user_time, systemMachTicks: info.ri_system_time,
        userNanoseconds: try timebase.nanoseconds(info.ri_user_time),
        systemNanoseconds: try timebase.nanoseconds(info.ri_system_time),
        physicalFootprintBytes: Nullable(info.ri_phys_footprint > 0 ? info.ri_phys_footprint : nil),
        packageIdleWakeups: Nullable(info.ri_pkg_idle_wkups > 0 ? info.ri_pkg_idle_wkups : nil))
}

private func checkedDelta(_ start: UInt64, _ end: UInt64) throws -> UInt64 {
    guard end >= start else { throw ProbeError("Resource counter regressed; no report published") }
    return end - start
}

private func nullableDelta(_ start: UInt64?, _ end: UInt64?) throws -> UInt64? {
    guard let start, let end else { return nil }
    return try checkedDelta(start, end)
}

private struct Summary: Encodable {
    let userCPUNanoseconds: UInt64
    let systemCPUNanoseconds: UInt64
    let totalCPUNanoseconds: UInt64
    let cpuPercentOneCore: Double
    let physicalFootprintStartBytes: Nullable<UInt64>
    let physicalFootprintEndBytes: Nullable<UInt64>
    let physicalFootprintMinBytes: Nullable<UInt64>
    let physicalFootprintMaxBytes: Nullable<UInt64>
    let packageIdleWakeupsDelta: Nullable<UInt64>
    let packageIdleWakeupsPerSecond: Nullable<Double>
}

private func summary(_ samples: [Sample]) throws -> Summary {
    guard let first = samples.first, let last = samples.last, last.elapsedSeconds > 0 else {
        throw ProbeError("Incomplete sampling window")
    }
    let user = try checkedDelta(first.userNanoseconds, last.userNanoseconds)
    let system = try checkedDelta(first.systemNanoseconds, last.systemNanoseconds)
    let total = user.addingReportingOverflow(system)
    guard !total.overflow else { throw ProbeError("CPU total overflow") }
    let footprint = samples.compactMap { $0.physicalFootprintBytes.value }
    // Any zero counter is conservatively unavailable, including zero -> positive transitions.
    let idle =
        samples.allSatisfy { $0.packageIdleWakeups.value != nil }
        ? try nullableDelta(first.packageIdleWakeups.value, last.packageIdleWakeups.value) : nil
    return Summary(
        userCPUNanoseconds: user, systemCPUNanoseconds: system, totalCPUNanoseconds: total.partialValue,
        cpuPercentOneCore: Double(total.partialValue) / 1_000_000_000 / last.elapsedSeconds * 100,
        physicalFootprintStartBytes: first.physicalFootprintBytes,
        physicalFootprintEndBytes: last.physicalFootprintBytes,
        physicalFootprintMinBytes: Nullable(footprint.min()), physicalFootprintMaxBytes: Nullable(footprint.max()),
        packageIdleWakeupsDelta: Nullable(idle),
        packageIdleWakeupsPerSecond: Nullable(idle.map { Double($0) / last.elapsedSeconds }))
}

private struct Report: Encodable {
    let schemaVersion = 1
    let status = "completed"
    let measurementKind = "external-packaged-app-process-observation"
    let resourceAPI = "proc_pid_rusage / RUSAGE_INFO_V0"
    let app: AppMetadata
    let userDeclaredLabel: Nullable<String>
    let uiVisibility = "user-declared/unverified"
    let alertConfiguration = "user-declared/unverified"
    let energyMeasured = false
    let exactStartIdentityVerified = true
    let startedAt: Date
    let endedAt: Date
    let osVersion: String
    let logicalCPUCount: Int
    let cpuTimebase: Timebase
    let requestedWarmupSeconds: Int
    let actualWarmupSeconds: Double
    let requestedDurationSeconds: Int
    let actualDurationSeconds: Double
    let samplingIntervalSeconds = 5
    let summary: Summary
    let samples: [Sample]
    let caveats = [
        "Observes only the supplied already-running packaged app PID; no launch, kill, XCTest, app code injection, preferences, permission requests, notifications or UI manipulation.",
        "Exact integer BSD birth time, rusage birth ticks, executable UUID/name/path are checked around every capture, through warmup and before publication. They and the PID are intentionally not saved. No atomic kernel transaction spans all calls; exit after final validation remains possible.",
        "Bundle basename/version/build are read from the on-disk bundle if available; this is not binary signing or loaded-version verification.",
        "V0 CPU counters are Mach ticks, converted using checked mach_timebase_info full-width arithmetic. CPU percent uses one core as 100 percent and can exceed 100. Wall time is monotonic system uptime.",
        "Physical footprint is bytes, not RSS. Extrema are sampled, not continuous peaks; zero footprint is null. Samples are scheduled every 5 seconds, with a shorter final interval for nonmultiples and possible scheduler delay.",
        "Package-idle wakeups are not all wakeups/timers/interrupts. Zero is conservatively null (unsupported or no observed accounting), not proof of zero wakeups; any unavailable sample makes the summary unavailable.",
        "Sampler/compiler CPU is excluded from the target counters. The observer still adds host sampling workload and can indirectly affect the app/system. Compilation completes before warmup.",
        "Energy/joules are not measured. UI visibility, alert configuration and any label are user-declared/unverified; app settings are never inspected. No efficiency pass/fail claim.",
        "Compare only like-for-like workloads, OS, power/thermal conditions and declared UI/settings. Warmup is excluded from the measured counters; logs are retained on failure and no successful JSON is published.",
    ]
}

private func run() throws {
    let args = CommandLine.arguments
    guard args.count == 6, let pid = pid_t(args[1]), pid > 0, pid != getpid(), geteuid() != 0,
        let duration = Int(args[3]), (30...86400).contains(duration),
        let warmup = Int(args[4]), (0...300).contains(warmup),
        args[5].isEmpty || args[5].range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$", options: .regularExpression) != nil
    else { throw ProbeError("Use measure-running-app.sh with explicit validated arguments as a non-root user") }
    let output = URL(fileURLWithPath: args[2])
    let parent = output.deletingLastPathComponent()
    let attributes = try FileManager.default.attributesOfItem(atPath: parent.path)
    guard args[2].hasPrefix("/"), output.lastPathComponent == "report.json",
        attributes[.type] as? FileAttributeType == .typeDirectory,
        (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
        !FileManager.default.fileExists(atPath: output.path)
    else { throw ProbeError("Output must be a new report.json in the wrapper's private run directory") }

    let timebase = try Timebase()
    let initial = try observe(pid)
    let app = metadata(initial.identity.executablePath)
    print("Validated packaged SystemPulse; exact start identity retained in memory only. Warmup: \(warmup)s.")
    let warmupStart = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - warmupStart < Double(warmup) {
        let remaining = Double(warmup) - (ProcessInfo.processInfo.systemUptime - warmupStart)
        Thread.sleep(forTimeInterval: max(0, min(5, remaining)))
        _ = try observe(pid, expected: initial.identity)
    }
    let actualWarmup = ProcessInfo.processInfo.systemUptime - warmupStart
    let startedAt = Date()
    let first = try observe(pid, expected: initial.identity)
    var samples = [try sample(first, start: first.uptime, timebase: timebase)]
    var nextOffset = min(5, Double(duration))
    while true {
        Thread.sleep(forTimeInterval: max(0, first.uptime + nextOffset - ProcessInfo.processInfo.systemUptime))
        let current = try observe(pid, expected: initial.identity)
        let captured = try sample(current, start: first.uptime, timebase: timebase)
        if let previous = samples.last {
            _ = try checkedDelta(previous.userMachTicks, captured.userMachTicks)
            _ = try checkedDelta(previous.systemMachTicks, captured.systemMachTicks)
            _ = try nullableDelta(previous.packageIdleWakeups.value, captured.packageIdleWakeups.value)
        }
        samples.append(captured)
        print("Captured sample \(samples.count): elapsed \(captured.elapsedSeconds)s")
        if captured.elapsedSeconds >= Double(duration) { break }
        // Skip missed deadlines rather than inventing/catching up historical observations.
        nextOffset = min((floor(captured.elapsedSeconds / 5) + 1) * 5, Double(duration))
    }
    let endedAt = Date()
    let totals = try summary(samples)
    guard let last = samples.last else { throw ProbeError("No samples") }
    let report = Report(
        app: app, userDeclaredLabel: Nullable(args[5].isEmpty ? nil : args[5]),
        startedAt: startedAt, endedAt: endedAt,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        logicalCPUCount: ProcessInfo.processInfo.activeProcessorCount, cpuTimebase: timebase,
        requestedWarmupSeconds: warmup, actualWarmupSeconds: actualWarmup,
        requestedDurationSeconds: duration, actualDurationSeconds: last.elapsedSeconds,
        summary: totals, samples: samples)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    _ = try observe(pid, expected: initial.identity)
    guard !FileManager.default.fileExists(atPath: output.path) else { throw ProbeError("Report already exists") }
    try data.write(to: output, options: .atomic)
    print("Completed: CPU \(totals.cpuPercentOneCore)% of one core. Energy not measured.")
}

do {
    try run()
} catch {
    // Do not interpolate Foundation errors: they can contain raw user paths.
    let message = (error as? ProbeError)?.message ?? "Metadata/output operation failed; no successful report published"
    FileHandle.standardError.write(Data("Running-app probe failed: \(message)\n".utf8))
    exit(1)
}
