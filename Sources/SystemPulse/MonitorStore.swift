import AppKit
import Foundation
import Observation

/// Central observable data store that periodically samples system metrics.
@Observable
@MainActor
final class MonitorStore {

    // MARK: - CPU
    var cpuUsage: Double = 0
    var perCoreCPU: [Double] = []
    var cpuHistory: [Double] = []
    var cpuPeak: Double = 0

    // MARK: - Memory
    var memoryBreakdown = MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: 0)
    var memoryUsage: Double { memoryBreakdown.usedPercent }
    var memoryUsed: UInt64 { memoryBreakdown.used }
    var memoryTotal: UInt64 { memoryBreakdown.total }
    var memoryHistory: [Double] = []
    var memoryPeakPercent: Double = 0

    // MARK: - Disk
    var diskUsed: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskTotal: UInt64 = 0
    var diskUsage: Double = 0

    // MARK: - Disk I/O
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0
    var diskReadHistory: [Double] = []
    var diskWriteHistory: [Double] = []
    var diskReadPeak: Double = 0
    var diskWritePeak: Double = 0
    var sessionBytesRead: UInt64 = 0
    var sessionBytesWritten: UInt64 = 0

    // MARK: - Power
    var power = PowerInfo()
    var batteryHistory: [Double] = []
    var powerDrawHistory: [Double] = []
    var powerDrawPeak: Double = 0

    // MARK: - Network
    var netInRate: Double = 0
    var netOutRate: Double = 0
    var netHistory: [Double] = []
    var netInHistory: [Double] = []
    var netOutHistory: [Double] = []
    var netInPeak: Double = 0
    var netOutPeak: Double = 0
    var sessionBytesIn: UInt64 = 0
    var sessionBytesOut: UInt64 = 0

    // MARK: - System
    var systemInfo = SystemInfo()

    // MARK: - Processes
    var processGroups: [ProcessGroup] = []
    var topProcessName: String = "—"
    var topProcessCPU: Double = 0

    // MARK: - Disk Clean
    var diskCategories: [DiskCategory] = []
    var isScanning: Bool = false
    var scanCurrentPath: String = ""
    var scanProgress: Double = 0
    var lastScanComplete: Bool = false
    var reclaimableBytes: UInt64 {
        diskCategories.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - UI feedback
    var toast: ToastMessage?

    static let historyLimit = 60

    /// Set by the app delegate as the panel opens and closes. While it's false
    /// only the metrics the menu bar actually renders are collected, which keeps
    /// a monitor that runs all day from becoming the thing worth monitoring.
    var isPanelVisible = false {
        didSet {
            guard isPanelVisible, isPanelVisible != oldValue else { return }
            sample()
        }
    }

    // MARK: - Private
    private let sampler = SystemSampler()
    private var timer: Timer?
    private var isSampling = false
    private var prevNet: NetworkSnapshot?
    private var prevDiskIO: DiskIOSnapshot?
    private var lastPowerSample: Date?
    private var lastProcessRefresh: Date?
    private var isRefreshingProcesses = false
    private var toastClearTask: Task<Void, Never>?
    private let preferences = Preferences.shared

    /// Battery and adapter state moves far slower than the refresh rate.
    private static let powerSampleInterval: TimeInterval = 5

    /// Process-table cadence while the panel is hidden: slow enough to be
    /// negligible, recent enough to give the next refresh a CPU baseline.
    private static let hiddenProcessInterval: TimeInterval = 15

    init() {
        startPolling()
    }

    func restartPolling() {
        timer?.invalidate()
        startPolling()
    }

    private func startPolling() {
        sample()
        let interval = preferences.refreshRate.rawValue
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sample()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// A single in-flight pass keeps Mach counters ordered and avoids piling up
    /// work when an IOKit or filesystem query takes longer than the refresh rate.
    private func sample() {
        guard !isSampling else { return }
        isSampling = true
        let includeDetail = isPanelVisible
        let includePower = lastPowerSample.map { Date().timeIntervalSince($0) >= Self.powerSampleInterval } ?? true
        if includePower { lastPowerSample = Date() }
        Task.detached(priority: .utility) { [sampler, weak self] in
            let cpu = sampler.cpuSample()
            let memory = sampler.memoryBreakdown()
            let io = DiskIOSampler.snapshot()
            let power = includePower ? PowerSampler.sample() : nil
            let net = sampler.networkSnapshot()
            let disk = includeDetail ? sampler.diskUsage() : nil
            let info = includeDetail ? sampler.systemInfo() : nil
            await self?.applySample(cpu: cpu, memory: memory, io: io,
                                    power: power, net: net, disk: disk, info: info)
        }
    }

    private func applySample(cpu: SystemSampler.CPUSample, memory: MemoryBreakdown,
                             io: DiskIOSnapshot, power: PowerInfo?, net: NetworkSnapshot,
                             disk: SystemSampler.DiskUsage?, info: SystemInfo?) {
        defer { isSampling = false }
        // One CPU reading per tick. Sampling consumes the previous tick's
        // counters, so overall and per-core have to come off the same call —
        // a second call would measure a microsecond-wide window of noise.
        cpuUsage = cpu.overall
        perCoreCPU = cpu.perCore
        appendHistory(&cpuHistory, value: cpuUsage)
        cpuPeak = max(cpuPeak, cpuUsage)

        memoryBreakdown = memory
        appendHistory(&memoryHistory, value: Double(memoryBreakdown.used))
        memoryPeakPercent = max(memoryPeakPercent, memoryUsage)

        applyDiskIO(io)
        if let power { applyPower(power) }

        // Interface counters restart when a link goes away (Wi-Fi toggled, cable
        // unplugged), so the running total can move backwards. Accumulate only
        // forward deltas — an unsigned wrap here would spike the rate to ~1.8e19
        // and permanently flatten the graph against a bogus peak.
        if let prev = prevNet {
            let dt = net.timestamp.timeIntervalSince(prev.timestamp)
            let deltaIn = net.bytesIn >= prev.bytesIn ? net.bytesIn - prev.bytesIn : 0
            let deltaOut = net.bytesOut >= prev.bytesOut ? net.bytesOut - prev.bytesOut : 0
            if dt > 0 {
                netInRate = Double(deltaIn) / dt
                netOutRate = Double(deltaOut) / dt
            }
            sessionBytesIn += deltaIn
            sessionBytesOut += deltaOut
        }
        prevNet = net
        appendHistory(&netHistory, value: netInRate + netOutRate)
        appendHistory(&netInHistory, value: netInRate)
        appendHistory(&netOutHistory, value: netOutRate)
        netInPeak = max(netInPeak, netInRate)
        netOutPeak = max(netOutPeak, netOutRate)

        refreshProcessesIfDue()

        if let disk {
            diskUsed = disk.used
            diskFree = disk.free
            diskTotal = disk.total
            diskUsage = disk.total > 0 ? Double(disk.used) / Double(disk.total) * 100 : 0
        }
        if let info { systemInfo = info }
    }

    /// Rebuilds the grouped process table — the heaviest step, since it walks
    /// every pid and resolves bundle metadata.
    ///
    /// This keeps running at a slow cadence while the panel is hidden rather
    /// than stopping outright: per-process CPU is a delta against the previous
    /// pass, so going fully idle would make the list read 0% for everything on
    /// the first refresh after the panel opens.
    private func refreshProcessesIfDue() {
        guard !isRefreshingProcesses else { return }

        let interval = isPanelVisible
            ? preferences.refreshRate.rawValue * 2
            : Self.hiddenProcessInterval
        let due = lastProcessRefresh.map { Date().timeIntervalSince($0) >= interval } ?? true
        guard due else { return }

        lastProcessRefresh = Date()
        isRefreshingProcesses = true
        Task.detached(priority: .utility) { [sampler] in
            let groups = sampler.groupedProcesses()
            let top = groups.first
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.processGroups = groups
                self.topProcessName = top?.name ?? "—"
                self.topProcessCPU = top?.totalCPU ?? 0
                self.isRefreshingProcesses = false
            }
        }
    }

    private func applyDiskIO(_ io: DiskIOSnapshot) {
        if let prev = prevDiskIO {
            let dt = io.timestamp.timeIntervalSince(prev.timestamp)
            let deltaRead = io.bytesRead >= prev.bytesRead ? io.bytesRead - prev.bytesRead : 0
            let deltaWrite = io.bytesWritten >= prev.bytesWritten ? io.bytesWritten - prev.bytesWritten : 0
            if dt > 0 {
                diskReadRate = Double(deltaRead) / dt
                diskWriteRate = Double(deltaWrite) / dt
            }
            sessionBytesRead += deltaRead
            sessionBytesWritten += deltaWrite
        }
        prevDiskIO = io
        appendHistory(&diskReadHistory, value: diskReadRate)
        appendHistory(&diskWriteHistory, value: diskWriteRate)
        diskReadPeak = max(diskReadPeak, diskReadRate)
        diskWritePeak = max(diskWritePeak, diskWriteRate)
    }

    private func applyPower(_ power: PowerInfo) {
        self.power = power
        if power.hasBattery {
            appendHistory(&batteryHistory, value: power.chargePercent)
        }
        if let watts = power.systemPowerWatts {
            appendHistory(&powerDrawHistory, value: watts)
            powerDrawPeak = max(powerDrawPeak, watts)
        }
    }

    private func appendHistory(_ array: inout [Double], value: Double) {
        array.append(value)
        if array.count > Self.historyLimit {
            array.removeFirst(array.count - Self.historyLimit)
        }
    }

    // MARK: - Process Actions

    func quit(pid: pid_t, force: Bool) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            kill(pid, force ? SIGKILL : SIGTERM)
            showToast(force ? "Force quit signal sent" : "Quit signal sent")
            return
        }
        if force {
            app.forceTerminate()
            showToast("Force quit sent")
        } else {
            app.terminate()
            showToast("Quit requested")
        }
    }

    func quitGroup(_ group: ProcessGroup, force: Bool) {
        for proc in group.processes {
            quit(pid: proc.id, force: force)
        }
    }

    func revealProcess(_ group: ProcessGroup) {
        if let path = group.processes.first?.bundlePath ?? group.processes.first?.executablePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func copySnapshot() {
        let summary = """
        SystemPulse · \(Date().formatted(date: .abbreviated, time: .standard))
        CPU: \(String(format: "%.1f%%", cpuUsage))
        Memory: \(ByteFormatter.format(memoryUsed)) / \(ByteFormatter.format(memoryTotal)) · \(memoryBreakdown.pressure.rawValue) pressure
        Network: ↓ \(ByteFormatter.formatRate(netInRate)) · ↑ \(ByteFormatter.formatRate(netOutRate))
        Disk: \(ByteFormatter.format(diskFree)) free / \(ByteFormatter.format(diskTotal))
        Power: \(power.stateLabel) · \(power.systemPowerWatts.map { String(format: "%.1f W", $0) } ?? "draw unavailable")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
        showToast("System snapshot copied")
    }

    func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        showToast("Path copied")
    }

    func startDate(forPid pid: pid_t) -> Date? {
        ProcessMetadataProvider.startDate(for: pid)
    }

    // MARK: - Disk Scanning

    func scanDisk() {
        guard !isScanning else { return }
        isScanning = true
        lastScanComplete = false
        diskCategories = []
        scanProgress = 0
        Task.detached(priority: .utility) {
            DiskScanner.scan { update in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.diskCategories = update.categories
                    self.scanCurrentPath = update.currentPath
                    self.scanProgress = update.progress
                    if update.isComplete {
                        self.isScanning = false
                        self.lastScanComplete = true
                        self.scanCurrentPath = ""
                        self.scanProgress = 1
                    }
                }
            }
        }
    }

    func revealInFinder(path: String) {
        DiskScanner.reveal(path: path)
    }

    @discardableResult
    func deleteDiskItem(_ item: DiskItem) -> Bool {
        let ok = DiskScanner.delete(path: item.path)
        if ok {
            for i in diskCategories.indices {
                diskCategories[i].items.removeAll { $0.id == item.id }
                diskCategories[i].bytes = diskCategories[i].items.reduce(0) { $0 + $1.bytes }
            }
            diskCategories.removeAll { $0.items.isEmpty }
            showToast("Moved to Trash · \(item.sizeFormatted)")
        } else {
            showToast("Could not delete item", isError: true)
        }
        return ok
    }

    // MARK: - Toast

    func showToast(_ text: String, isError: Bool = false) {
        toastClearTask?.cancel()
        toast = ToastMessage(text: text, isError: isError)
        toastClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            if toast?.text == text {
                toast = nil
            }
        }
    }
}
