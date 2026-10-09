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
    private(set) var cpuReadingIsBaseline = false
    var hasCPUReading: Bool { !perCoreCPU.isEmpty && !cpuReadingIsBaseline }
    var cpuHistory: [Double] = []
    var cpuPeak: Double = 0
    var cpuTimeline = MetricHistory()
    var memoryTimeline = MetricHistory()
    var downloadTimeline = MetricHistory()
    var uploadTimeline = MetricHistory()
    var diskReadTimeline = MetricHistory()
    var diskWriteTimeline = MetricHistory()
    var powerDrawTimeline = MetricHistory()
    private(set) var latestSampleAt: Date?
    private(set) var latestCPUSampleAt: Date?
    private(set) var latestMemorySampleAt: Date?
    private(set) var latestPowerSampleAt: Date?
    private(set) var latestHomeDiskSampleAt: Date?
    private(set) var latestThermalSampleAt: Date?
    private(set) var latestProcessSampleAt: Date?
    /// Permission is refreshed by the app lifecycle, never requested by sampling.
    private(set) var notificationAuthorizationRevision: UInt64 = 0
    var notificationDeliveryAllowed = false {
        didSet {
            // Revocation/reauthorization between telemetry passes starts fresh
            // evidence, even when the final permission state is unchanged.
            if notificationDeliveryAllowed != oldValue {
                notificationAuthorizationRevision &+= 1
                alertEngine = AlertCoordinator()
            }
        }
    }

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
    var volumes: [MonitoredVolume] = []
    var selectedVolumeID: String?
    var selectedVolume: MonitoredVolume? { VolumeSelection.resolve(selectedID: selectedVolumeID, in: volumes) }

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
    var networkInterfaces: [NetworkInterfaceReading] = []
    var selectedNetworkInterfaceID: String? {
        didSet {
            guard selectedNetworkInterfaceID != oldValue else { return }
            selectedDownloadTimeline = MetricHistory()
            selectedUploadTimeline = MetricHistory()
        }
    }
    var selectedDownloadTimeline = MetricHistory()
    var selectedUploadTimeline = MetricHistory()
    var networkPageDownloadTimeline: MetricHistory {
        selectedNetworkInterfaceID == nil ? downloadTimeline : selectedDownloadTimeline
    }
    var networkPageUploadTimeline: MetricHistory {
        selectedNetworkInterfaceID == nil ? uploadTimeline : selectedUploadTimeline
    }

    // MARK: - System
    var systemInfo = SystemInfo()

    // MARK: - Processes
    var processGroups: [ProcessGroup] = []
    private(set) var processSampleRevision: UInt64 = 0
    var topProcessName: String = "—"
    var topProcessCPU: Double = 0

    // MARK: - Disk Clean
    var diskCategories: [DiskCategory] = []
    var isScanning: Bool = false
    var scanCurrentPath: String = ""
    var scanProgress: Double = 0
    var lastScanComplete: Bool = false
    private(set) var scanScope: DiskScanScope = .cleanupLocations
    private(set) var folderInventory: FolderInventory?
    private(set) var folderNavigation: [URL] = []
    var diskScanRevision: UInt64 { diskScanGeneration }
    private(set) var cleanupQueue: [DiskItem] = []
    private(set) var cleanupReview: CleanupReview?
    private var singleItemTrashReview: DiskTrashReview?
    private(set) var cleanupResults: [CleanupItemResult] = []
    private(set) var cleanupRunID: UUID?
    private(set) var isPerformingCleanup = false
    private(set) var isStoppingCleanup = false
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    private(set) var isChoosingScanFolder = false
    private var folderSelectionRevision: UInt64 = 0
    var cleanupIsBlocked: Bool {
        isScanning || isChoosingScanFolder || isPerformingCleanup || !lastScanComplete
            || scanResultsArePartial || scanScope.isReadOnly || pollingState == .stopped || pollingState == .suspended
    }
    private(set) var isCancellingScan = false
    private(set) var lastScanCancelled = false
    private(set) var scanSkippedLocationCount = 0
    var scanResultsArePartial: Bool { lastScanCancelled || scanSkippedLocationCount > 0 }
    var reclaimableBytes: UInt64 {
        CleanupQueue.totalBytes(diskCategories.flatMap(\.items).filter(\.safeToDelete))
    }

    // MARK: - UI feedback
    var toast: ToastMessage?

    static let historyLimit = 60

    /// Set by the app delegate as the panel opens and closes. While it's false
    /// counters/history continue, processes slow down, and volume detail is deferred.
    /// Home capacity is also sampled slowly when a selected menu metric or opted-in
    /// authorized alert needs it.
    var isPanelVisible = false {
        didSet {
            guard isPanelVisible, isPanelVisible != oldValue else { return }
            sample()
            refreshVolumes()
        }
    }

    // MARK: - Private
    private let sampler = SystemSampler()
    private let processSampler: @Sendable (Bool) -> [ProcessGroup]
    /// A manual driver keeps active-lifecycle tests entirely synthetic, including
    /// wake/restart paths. Production always uses the default automatic driver.
    private let automaticallySchedulesPolling: Bool
    @ObservationIgnored private var timer: Timer?
    private var isSampling = false
    private var networkCounters = CounterRateTracker()
    private var interfaceTracker = NetworkInterfaceTracker()
    private var lastVolumeRefresh: Date?
    private var isRefreshingVolumes = false
    private var volumeRefreshPending = false
    private var diskIOCounters = CounterRateTracker()
    private var pollingLifecycle: PollingLifecycle
    private var pollingEnabled: Bool { pollingLifecycle.isRunning }
    private var resetCPUBaseline = false
    private var resetProcessBaseline = false
    var pollingState: PollingLifecycle.State { pollingLifecycle.state }
    private let processActions: ProcessActions
    private let trashItem: (DiskItem) -> Bool
    private let cleanupTrashClient: CleanupTrashClient
    private let cleanupEligibility: (DiskItem) -> Bool
    private let accessibilityStatusClient: AccessibilityStatusClient
    typealias ScanRunner = @Sendable (@escaping @Sendable (DiskScanner.ScanUpdate) -> Void) -> Void
    private let scanRunner: ScanRunner
    typealias FolderScanRunner = @Sendable (URL, @escaping @Sendable (DiskScanner.ScanUpdate) -> Void) -> Void
    private let folderScanRunner: FolderScanRunner
    @ObservationIgnored private var diskScanTask: Task<Void, Never>?
    @ObservationIgnored private var diskScanObservationTask: Task<Void, Never>?
    private var diskScanGeneration: UInt64 = 0
    private var lastPowerSample: Date?
    private var lastProcessRefresh: Date?
    private var isRefreshingProcesses = false
    @ObservationIgnored private var processRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var toastClearTask: Task<Void, Never>?
    private let preferences: Preferences
    private var alertEngine = AlertCoordinator()
    private let alertSink: (@MainActor (AlertEvent) -> Void)?
    private var lastHomeDiskAttempt: Date?
    private var pollingRefreshRate: Preferences.RefreshRate?

    /// Battery and adapter state moves far slower than the refresh rate.
    private static let powerSampleInterval: TimeInterval = 5

    /// Process-table cadence while the panel is hidden: slow enough to be
    /// negligible, recent enough to give the next refresh a CPU baseline.
    private static let hiddenProcessInterval: TimeInterval = 15

    /// Disable all automatic sampling for previews and deterministic tests.
    init(
        startPolling: Bool = true, processActions: ProcessActions? = nil,
        trashItem: @escaping (DiskItem) -> Bool = { DiskScanner.delete(item: $0) },
        preferences: Preferences? = nil,
        alertSink: (@MainActor (AlertEvent) -> Void)? = nil,
        scanRunner: @escaping ScanRunner = { DiskScanner.scan(onUpdate: $0) },
        folderScanRunner: @escaping FolderScanRunner = { DiskScanner.scanFolder(at: $0, onUpdate: $1) },
        cleanupTrashClient: CleanupTrashClient = .live,
        cleanupEligibility: @escaping (DiskItem) -> Bool = { DiskScanner.canDelete($0) },
        accessibilityStatusClient: AccessibilityStatusClient = .live,
        automaticallySchedulesPolling: Bool = true,
        processSampler: (@Sendable (Bool) -> [ProcessGroup])? = nil
    ) {
        pollingLifecycle = PollingLifecycle(enabled: startPolling)
        self.automaticallySchedulesPolling = automaticallySchedulesPolling
        let sampler = self.sampler
        self.processSampler = processSampler ?? { sampler.groupedProcesses(resetBaseline: $0) }
        self.preferences = preferences ?? .shared
        self.alertSink = alertSink
        self.processActions = processActions ?? .live
        self.trashItem = trashItem
        self.cleanupTrashClient = cleanupTrashClient
        self.cleanupEligibility = cleanupEligibility
        self.accessibilityStatusClient = accessibilityStatusClient
        self.scanRunner = scanRunner
        self.folderScanRunner = folderScanRunner
        if startPolling { self.startPolling() }
    }

    deinit {
        timer?.invalidate()
        toastClearTask?.cancel()
        diskScanTask?.cancel()
        diskScanObservationTask?.cancel()
        cleanupTask?.cancel()
        processRefreshTask?.cancel()
    }

    /// Sleep invalidates results already in flight but never starts a second OS
    /// query over them. Counters resume with new baselines; history/totals remain.
    func suspendPolling() {
        guard pollingLifecycle.suspend() else { return }
        stopCleanup()
        cleanupReview = nil
        singleItemTrashReview = nil
        timer?.invalidate()
        timer = nil
        invalidateCurrentReadings()
        resetCPUBaseline = true
        resetProcessBaseline = true
        networkCounters.resetBaseline()
        diskIOCounters.resetBaseline()
        interfaceTracker.resetBaselines()
        networkInterfaces = interfaceTracker.interfaces
        netInRate = 0
        netOutRate = 0
        diskReadRate = 0
        diskWriteRate = 0
        alertEngine.interrupt()
        notificationAuthorizationRevision &+= 1
    }

    func resumePolling() {
        guard pollingLifecycle.resume() else { return }
        lastPowerSample = nil
        lastHomeDiskAttempt = nil
        lastProcessRefresh = nil
        lastVolumeRefresh = nil
        startPolling()
        if isPanelVisible { refreshVolumes() }
    }

    /// Terminal shutdown: never resurrected by a delayed wake/settings callback.
    func stopPolling() {
        guard pollingLifecycle.state != .stopped else { return }
        pollingLifecycle.stop()
        stopCleanup()
        cleanupReview = nil
        singleItemTrashReview = nil
        cleanupQueue = []
        isChoosingScanFolder = false
        folderSelectionRevision &+= 1
        cancelDiskScan()
        timer?.invalidate()
        timer = nil
        toastClearTask?.cancel()
        toastClearTask = nil
        volumeRefreshPending = false
        invalidateCurrentReadings()
        alertEngine.interrupt()
        notificationAuthorizationRevision &+= 1
    }

    private func invalidateCurrentReadings() {
        latestSampleAt = nil
        cpuReadingIsBaseline = true
        latestCPUSampleAt = nil
        latestMemorySampleAt = nil
        latestPowerSampleAt = nil
        latestHomeDiskSampleAt = nil
        latestThermalSampleAt = nil
        latestProcessSampleAt = nil
    }

    func restartPolling() {
        timer?.invalidate()
        if pollingEnabled { startPolling() }
    }

    func synchronizePollingPreferences() {
        guard pollingEnabled, pollingRefreshRate != preferences.refreshRate else { return }
        restartPolling()
    }

    private func startPolling() {
        pollingRefreshRate = preferences.refreshRate
        guard automaticallySchedulesPolling else { return }
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
        guard automaticallySchedulesPolling, pollingEnabled, !isSampling else { return }
        isSampling = true
        let generation = pollingLifecycle.generation
        let resetCPU = resetCPUBaseline
        resetCPUBaseline = false
        let includeDetail = isPanelVisible
        let needsDiskAlert =
            preferences.alertsEnabled && notificationDeliveryAllowed
            && preferences.alertRules.contains { $0.kind == .diskAvailable && $0.enabled }
        let needsHomeDisk =
            (preferences.menuBarMetrics.contains(.disk) && preferences.menuBarStyle != .iconOnly) || needsDiskAlert
        // Authorized disk alerts require actual samples inside the engine's 10s
        // continuity limit. Menu-bar-only capacity needs a slower cadence.
        let diskInterval: TimeInterval = needsDiskAlert ? 5 : 10
        let includeDisk =
            includeDetail
            || (needsHomeDisk && (lastHomeDiskAttempt.map { Date().timeIntervalSince($0) >= diskInterval } ?? true))
        if includeDisk { lastHomeDiskAttempt = .now }
        let includePower = lastPowerSample.map { Date().timeIntervalSince($0) >= Self.powerSampleInterval } ?? true
        if includePower { lastPowerSample = Date() }
        Task.detached(priority: .utility) { [sampler, weak self] in
            let cpu = sampler.cpuSample(resetBaseline: resetCPU)
            let cpuAt = Date()
            let memory = sampler.memoryBreakdown()
            let memoryAt = Date()
            let io = DiskIOSampler.snapshot()
            let power = includePower ? PowerSampler.sample() : nil
            let powerAt = power == nil ? nil : Date()
            let net = sampler.networkSnapshot()
            let disk = includeDisk ? sampler.diskUsage() : nil
            let diskAt = disk == nil ? nil : Date()
            let info = includeDetail ? sampler.systemInfo() : nil
            let thermal = ProcessInfo.processInfo.thermalState
            let times = SampleObservationTimes(
                cpu: cpuAt, memory: memoryAt, power: powerAt, disk: diskAt, thermal: Date())
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isSampling = false
                guard self.pollingLifecycle.accepts(generation) else { return }
                self.applySample(
                    cpu: cpu, memory: memory, io: io,
                    power: power, net: net, disk: disk, info: info, thermal: thermal, observationTimes: times)
            }
        }
    }

    func applySample(
        cpu: SystemSampler.CPUSample, memory: MemoryBreakdown,
        io: DiskIOSnapshot, power: PowerInfo?, net: NetworkSnapshot,
        disk: SystemSampler.DiskUsage?, info: SystemInfo?,
        thermal: ProcessInfo.ThermalState? = nil,
        observationTimes: SampleObservationTimes? = nil,
        evaluatedAt: Date? = nil
    ) {
        defer { isSampling = false }
        let times =
            observationTimes
            ?? SampleObservationTimes(
                cpu: net.timestamp, memory: net.timestamp, power: net.timestamp, disk: net.timestamp,
                thermal: net.timestamp)
        latestSampleAt = net.timestamp
        latestCPUSampleAt = cpu.hasInterval && !cpu.perCore.isEmpty ? times.cpu : nil
        latestMemorySampleAt = times.memory
        // One CPU reading per tick. Sampling consumes the previous tick's
        // counters, so overall and per-core have to come off the same call —
        // a second call would measure a microsecond-wide window of noise.
        cpuReadingIsBaseline = !cpu.hasInterval
        cpuUsage = cpu.overall
        perCoreCPU = cpu.perCore
        if hasCPUReading {
            appendHistory(&cpuHistory, value: cpuUsage)
            cpuPeak = max(cpuPeak, cpuUsage)
            cpuTimeline.record(cpuUsage, at: times.cpu)
        }

        memoryBreakdown = memory
        appendHistory(&memoryHistory, value: Double(memoryBreakdown.used))
        memoryPeakPercent = max(memoryPeakPercent, memoryUsage)
        if memoryTotal > 0 { memoryTimeline.record(Double(memoryUsed), at: times.memory) }

        applyDiskIO(io)
        if let power, let sampledAt = times.power { applyPower(power, at: sampledAt) }

        applyNetwork(net)

        refreshProcessesIfDue()

        if let disk {
            diskUsed = disk.used
            diskFree = disk.free
            diskTotal = disk.total
            diskUsage = disk.total > 0 ? Double(disk.used) / Double(disk.total) * 100 : 0
            latestHomeDiskSampleAt = disk.total > 0 ? times.disk : nil
        }
        if let info {
            systemInfo = info
            latestThermalSampleAt = times.thermal
        }
        if let thermal {
            systemInfo.thermalState = thermal
            latestThermalSampleAt = times.thermal
        }
        // Evaluate against delivery-time wall clock, not a stale acquisition
        // timestamp: blocked I/O or sleep must not warn immediately on resume.
        evaluateAlerts(at: evaluatedAt ?? Date())
        if isPanelVisible { refreshVolumesIfDue() }
    }

    /// Rebuilds the grouped process table — the heaviest step, since it walks
    /// every pid and resolves bundle metadata.
    ///
    /// This keeps running at a slow cadence while the panel is hidden rather
    /// than stopping outright: per-process CPU is a delta against the previous
    /// pass, so going fully idle would make the list read 0% for everything on
    /// the first refresh after the panel opens.
    func refreshProcessesIfDue(at timestamp: Date = .now) {
        guard pollingEnabled, !isRefreshingProcesses, timestamp.timeIntervalSinceReferenceDate.isFinite else { return }

        let interval =
            isPanelVisible
            ? preferences.refreshRate.rawValue * 2
            : Self.hiddenProcessInterval
        let due = lastProcessRefresh.map { timestamp.timeIntervalSince($0) >= interval } ?? true
        guard due else { return }

        lastProcessRefresh = timestamp
        isRefreshingProcesses = true
        let generation = pollingLifecycle.generation
        let resetProcesses = resetProcessBaseline
        resetProcessBaseline = false
        processRefreshTask = Task.detached(priority: .utility) { [processSampler, weak self] in
            let groups = processSampler(resetProcesses)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRefreshingProcesses = false
                self.processRefreshTask = nil
                guard self.pollingLifecycle.accepts(generation) else { return }
                self.applyProcesses(groups)
            }
        }
    }

    /// Join the current pass without launching work. Cancellation cannot interrupt
    /// a blocked synchronous OS query; generation checks still reject late results.
    func waitForProcessRefresh() async {
        await processRefreshTask?.value
    }

    /// One revision per sampling pass, even when values are unchanged. Detail
    /// charts must not duplicate a sample when CPU and memory change together.
    func applyProcesses(_ groups: [ProcessGroup], at timestamp: Date = .now) {
        latestProcessSampleAt = timestamp
        processGroups = groups
        topProcessName = groups.first?.name ?? "—"
        topProcessCPU = groups.first?.totalCPU ?? 0
        processSampleRevision &+= 1
    }

    func applyNetwork(_ net: NetworkSnapshot) {
        networkCounters.apply(
            net.interfaceCounters ?? ["aggregate": ByteCounters(first: net.bytesIn, second: net.bytesOut)],
            at: net.timestamp)
        netInRate = networkCounters.firstRate
        netOutRate = networkCounters.secondRate
        sessionBytesIn = networkCounters.firstTotal
        sessionBytesOut = networkCounters.secondTotal
        appendHistory(&netHistory, value: netInRate + netOutRate)
        appendHistory(&netInHistory, value: netInRate)
        appendHistory(&netOutHistory, value: netOutRate)
        netInPeak = max(netInPeak, netInRate)
        netOutPeak = max(netOutPeak, netOutRate)
        if net.interfaces?.isEmpty != true {
            downloadTimeline.record(netInRate, at: net.timestamp)
            uploadTimeline.record(netOutRate, at: net.timestamp)
        }
        if let interfaces = net.interfaces {
            interfaceTracker.apply(interfaces, at: net.timestamp)
            networkInterfaces = interfaceTracker.interfaces
            recordSelectedNetwork(at: net.timestamp)
        }
    }

    func applyDiskIO(_ io: DiskIOSnapshot) {
        diskIOCounters.apply(
            ["aggregate": ByteCounters(first: io.bytesRead, second: io.bytesWritten)], at: io.timestamp)
        diskReadRate = diskIOCounters.firstRate
        diskWriteRate = diskIOCounters.secondRate
        sessionBytesRead = diskIOCounters.firstTotal
        sessionBytesWritten = diskIOCounters.secondTotal
        appendHistory(&diskReadHistory, value: diskReadRate)
        appendHistory(&diskWriteHistory, value: diskWriteRate)
        diskReadPeak = max(diskReadPeak, diskReadRate)
        diskWritePeak = max(diskWritePeak, diskWriteRate)
        diskReadTimeline.record(diskReadRate, at: io.timestamp)
        diskWriteTimeline.record(diskWriteRate, at: io.timestamp)
    }

    func applyPower(_ power: PowerInfo, at timestamp: Date = .now) {
        self.power = power
        latestPowerSampleAt = timestamp
        if power.hasBattery, power.hasChargeReading {
            appendHistory(&batteryHistory, value: power.chargePercent)
        }
        if let watts = power.systemPowerWatts, watts.isFinite, watts >= 0 {
            appendHistory(&powerDrawHistory, value: watts)
            powerDrawPeak = max(powerDrawPeak, watts)
            powerDrawTimeline.record(watts, at: timestamp)
        }
    }

    private func appendHistory(_ array: inout [Double], value: Double) {
        array.append(value)
        if array.count > Self.historyLimit {
            array.removeFirst(array.count - Self.historyLimit)
        }
    }

    private func evaluateAlerts(at timestamp: Date) {
        let events = alertEngine.evaluate(
            sampledAlertMeasurements(at: timestamp), at: timestamp, rules: preferences.alertRules,
            enabled: preferences.alertsEnabled && notificationDeliveryAllowed && alertSink != nil,
            configuration: preferences.alertConfigurationTokens)
        for event in events { alertSink?(event) }
    }

    // MARK: - Interface and volume selection

    var selectedNetworkInterface: NetworkInterfaceReading? {
        networkInterfaces.first { $0.id == selectedNetworkInterfaceID }
    }
    var networkPageInRate: Double {
        selectedNetworkInterfaceID == nil ? netInRate : selectedNetworkInterface?.inRate ?? 0
    }
    var networkPageOutRate: Double {
        selectedNetworkInterfaceID == nil ? netOutRate : selectedNetworkInterface?.outRate ?? 0
    }
    var networkPageBytesIn: UInt64 {
        selectedNetworkInterfaceID == nil ? sessionBytesIn : selectedNetworkInterface?.sessionBytesIn ?? 0
    }
    var networkPageBytesOut: UInt64 {
        selectedNetworkInterfaceID == nil ? sessionBytesOut : selectedNetworkInterface?.sessionBytesOut ?? 0
    }
    var networkPageTotalBytes: UInt64 {
        let result = networkPageBytesIn.addingReportingOverflow(networkPageBytesOut)
        return result.overflow ? .max : result.partialValue
    }
    var networkPeakLabel: String { selectedNetworkInterfaceID == nil ? "peak" : "5m peak" }
    var networkPageInPeak: Double {
        guard selectedNetworkInterfaceID != nil else { return netInPeak }
        return selectedDownloadTimeline.points(
            in: .fiveMinutes, endingAt: selectedDownloadTimeline.latestTimestamp ?? .now
        ).map(\.value).max() ?? 0
    }
    var networkPageOutPeak: Double {
        guard selectedNetworkInterfaceID != nil else { return netOutPeak }
        return selectedUploadTimeline.points(in: .fiveMinutes, endingAt: selectedUploadTimeline.latestTimestamp ?? .now)
            .map(\.value).max() ?? 0
    }

    private func recordSelectedNetwork(at timestamp: Date) {
        guard selectedNetworkInterfaceID != nil, let reading = selectedNetworkInterface else { return }
        // A missing/disconnected interface is a gap, not an invented zero measurement.
        guard reading.isPresent, reading.isActive else { return }
        selectedDownloadTimeline.record(reading.inRate, at: timestamp)
        selectedUploadTimeline.record(reading.outRate, at: timestamp)
    }

    /// Filesystem metadata is slower than system counters. Poll only while the panel
    /// is open; mount/unmount notifications can request an immediate refresh.
    func refreshVolumes() {
        refreshVolumesIfDue(force: true)
    }

    private func refreshVolumesIfDue(force: Bool = false) {
        guard automaticallySchedulesPolling, pollingEnabled, isPanelVisible else { return }
        if isRefreshingVolumes {
            if force { volumeRefreshPending = true }
            return
        }
        let now = Date()
        guard force || lastVolumeRefresh.map({ now.timeIntervalSince($0) >= 10 }) ?? true else { return }
        isRefreshingVolumes = true
        lastVolumeRefresh = now
        let generation = pollingLifecycle.generation
        Task.detached(priority: .utility) { [weak self] in
            let sampled = VolumeSampler.sample()
            await self?.finishVolumeRefresh(sampled, generation: generation)
        }
    }

    private func finishVolumeRefresh(_ sampled: [MonitoredVolume], generation: UInt64) {
        isRefreshingVolumes = false
        guard pollingLifecycle.accepts(generation) else {
            volumeRefreshPending = false
            return
        }
        applyVolumes(sampled)
        if volumeRefreshPending {
            volumeRefreshPending = false
            refreshVolumesIfDue(force: true)
        }
    }

    func applyVolumes(_ sampled: [MonitoredVolume]) {
        volumes = sampled
        if let selectedVolumeID, !sampled.contains(where: { $0.id == selectedVolumeID }) {
            self.selectedVolumeID = nil
            showToast(
                sampled.isEmpty
                    ? "Selected volume unavailable; no mounted-volume readings"
                    : "Selected volume unavailable; showing the default volume")
        }
    }

    // MARK: - Process Actions

    func quit(pid: pid_t, force: Bool) {
        guard !processGroups.contains(where: { $0.isSystemGroup && $0.processes.contains(where: { $0.id == pid }) })
        else {
            showToast(ProcessActionError.protectedProcess.message, isError: true)
            return
        }
        switch processActions.request(pid: pid, force: force) {
        case .success: showToast(force ? "Force quit requested" : "Quit requested")
        case .failure(let error): showToast(error.message, isError: true)
        }
    }

    func quitGroup(_ group: ProcessGroup, force: Bool) {
        // Preflight the entire group before sending any requests.
        let systemPIDs = Set(processGroups.filter(\.isSystemGroup).flatMap(\.processes).map(\.id))
        guard !group.isSystemGroup,
            !group.processes.contains(where: { processActions.isProtected($0.id) || systemPIDs.contains($0.id) })
        else {
            showToast(ProcessActionError.protectedProcess.message, isError: true)
            return
        }
        let pids = Set(group.processes.map(\.id)).sorted()
        guard !pids.isEmpty else {
            showToast("No processes to quit", isError: true)
            return
        }
        var accepted = 0
        var failures: [ProcessActionError] = []
        for pid in pids {
            switch processActions.request(pid: pid, force: force) {
            case .success: accepted += 1
            case .failure(let error): failures.append(error)
            }
        }
        let action = force ? "Force quit" : "Quit"
        if let failure = failures.first {
            showToast("\(action): \(accepted) requested, \(failures.count) failed · \(failure.message)", isError: true)
        } else {
            showToast("\(action) requested for \(accepted) processes")
        }
    }

    func revealProcess(_ group: ProcessGroup) {
        if let path = group.processes.first?.bundlePath ?? group.processes.first?.executablePath {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    func snapshotText(at timestamp: Date = .now) -> String {
        let memoryDescription =
            memoryTotal > 0
            ? "\(ByteFormatter.format(memoryUsed)) / \(ByteFormatter.format(memoryTotal)) · \(memoryBreakdown.pressure.rawValue) pressure estimate"
            : "Unavailable"
        return """
            SystemPulse · \(timestamp.formatted(date: .abbreviated, time: .standard))
            CPU: \(hasCPUReading ? String(format: "%.1f%%", cpuUsage) : "Unavailable — awaiting a measured interval")
            Memory: \(memoryDescription)
            Network: ↓ \(ByteFormatter.formatRate(netInRate)) · ↑ \(ByteFormatter.formatRate(netOutRate))
            Home volume: \(ByteFormatter.format(diskFree)) available / \(ByteFormatter.format(diskTotal))
            Power: \(power.stateLabel) · \(power.systemPowerWatts.map { String(format: "%.1f W", $0) } ?? "draw unavailable")
            Low Power Mode: \(power.lowPowerModeEnabled.map { $0 ? "enabled" : "disabled" } ?? "unavailable")
            """
    }

    func copySnapshot() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshotText(), forType: .string)
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

    private var canStartDiskScan: Bool {
        diskScanTask == nil && !isScanning && !isChoosingScanFolder && !isPerformingCleanup && pollingState != .stopped
    }

    func beginFolderSelection() -> UInt64? {
        guard canStartDiskScan else { return nil }
        folderSelectionRevision &+= 1
        isChoosingScanFolder = true
        return folderSelectionRevision
    }

    @discardableResult
    func completeFolderSelection(_ url: URL?, revision: UInt64) -> Bool {
        guard isChoosingScanFolder, folderSelectionRevision == revision else { return false }
        isChoosingScanFolder = false
        folderSelectionRevision &+= 1
        guard let url else { return false }
        return scanFolder(url)
    }

    @discardableResult
    func scanFolder(_ url: URL) -> Bool {
        guard canStartDiskScan else { return false }
        guard DiskScanScope.acceptsFolderURL(url) else {
            showToast("Choose a local folder, not a filesystem root or remote URL", isError: true)
            return false
        }
        let root = url.standardizedFileURL
        folderNavigation = [root]
        scanScope = .folder(root)
        scanDisk()
        return true
    }

    func scanCleanupLocations() {
        guard canStartDiskScan else { return }
        folderNavigation = []
        scanScope = .cleanupLocations
        scanDisk()
    }

    @discardableResult
    func drillIntoFolder(_ entry: FolderInventoryEntry) -> Bool {
        guard canStartDiskScan, folderNavigation.count < 64, entry.isDirectory,
            let inventory = folderInventory, inventory.root.path == scanScope.folderURL?.path,
            let url = FolderInventoryAccess.validatedURL(for: entry, in: inventory)
        else { return false }
        folderNavigation.append(url)
        scanScope = .folder(url)
        scanDisk()
        return true
    }

    @discardableResult
    func backToParentFolder() -> Bool {
        guard canStartDiskScan, folderNavigation.count > 1 else { return false }
        folderNavigation.removeLast()
        guard let parent = folderNavigation.last else { return false }
        scanScope = .folder(parent)
        scanDisk()
        return true
    }

    func inventoryActionURL(for entry: FolderInventoryEntry) -> URL? {
        guard !isScanning, !isChoosingScanFolder, pollingState != .stopped,
            let inventory = folderInventory, inventory.root.path == scanScope.folderURL?.path
        else { return nil }
        return FolderInventoryAccess.validatedURL(for: entry, in: inventory)
    }

    func scanDisk() {
        guard canStartDiskScan else { return }
        invalidateCleanupSelection()
        diskScanGeneration &+= 1
        let generation = diskScanGeneration
        isScanning = true
        isCancellingScan = false
        lastScanComplete = false
        lastScanCancelled = false
        scanSkippedLocationCount = 0
        diskCategories = []
        folderInventory = nil
        scanProgress = 0
        scanCurrentPath = ""
        let (updates, continuation) = AsyncStream<DiskScanner.ScanUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let runner = scanRunner
        let folderRunner = folderScanRunner
        let scope = scanScope
        // Synchronous filesystem walking must not inherit the main actor.
        // Cancellation is cooperative; keep ownership until the worker exits so
        // Cancel -> Rescan can never overlap two enumerations.
        let worker = Task.detached(priority: .utility) {
            if let root = scope.folderURL {
                folderRunner(root) { continuation.yield($0) }
            } else {
                runner { continuation.yield($0) }
            }
            continuation.finish()
        }
        continuation.onTermination = { termination in
            if case .cancelled = termination { worker.cancel() }
        }
        diskScanTask = worker
        diskScanObservationTask = Task { @MainActor [weak self] in
            var terminalUpdate: DiskScanner.ScanUpdate?
            for await update in updates {
                guard let self, self.diskScanGeneration == generation else {
                    worker.cancel()
                    break
                }
                if update.isComplete { terminalUpdate = update }
                guard !self.isCancellingScan, !update.isCancelled else { continue }
                self.diskCategories = update.categories
                if update.inventory?.root.path == scope.folderURL?.path { self.folderInventory = update.inventory }
                self.scanCurrentPath = update.currentPath
                self.scanProgress = update.progress.isFinite ? min(1, max(0, update.progress)) : 0
                self.scanSkippedLocationCount = max(0, update.skippedLocationCount)
            }
            await worker.value
            guard let self, self.diskScanGeneration == generation else { return }
            let cancelled = self.isCancellingScan || terminalUpdate?.isCancelled == true || terminalUpdate == nil
            self.isScanning = false
            self.isCancellingScan = false
            self.lastScanCancelled = cancelled
            self.lastScanComplete = !cancelled
            self.scanSkippedLocationCount = max(
                self.scanSkippedLocationCount, terminalUpdate?.skippedLocationCount ?? 0)
            self.scanCurrentPath = ""
            if !cancelled { self.scanProgress = 1 }
            self.diskScanTask = nil
            self.diskScanObservationTask = nil
        }
    }

    func cancelDiskScan() {
        guard isScanning, !isCancellingScan else { return }
        isCancellingScan = true
        diskScanTask?.cancel()
    }

    /// Join the observer as well as the worker; useful to await deterministic
    /// completion without a timer, busy loop or an extra filesystem scan.
    func waitForDiskScan() async {
        await diskScanObservationTask?.value
    }

    func revealInFinder(path: String) {
        DiskScanner.reveal(path: path)
    }

    func prepareDiskTrashReview(_ item: DiskItem) -> DiskTrashReview? {
        guard !cleanupIsBlocked, item.safeToDelete, diskCategories.flatMap(\.items).contains(item) else {
            showToast(
                "Cleanup unavailable · partial, selected-folder or protected results remain read-only", isError: true)
            return nil
        }
        let review = DiskTrashReview(id: UUID(), scanRevision: diskScanGeneration, item: item)
        cleanupReview = nil
        singleItemTrashReview = review
        return review
    }

    @discardableResult
    func deleteDiskItem(_ review: DiskTrashReview) -> Bool {
        guard singleItemTrashReview == review, review.scanRevision == diskScanGeneration else {
            showToast("Cleanup confirmation expired · review the current scan", isError: true)
            return false
        }
        singleItemTrashReview = nil
        let item = review.item
        guard !isScanning, !isPerformingCleanup else {
            showToast("Wait for the disk scan or cleanup to finish", isError: true)
            return false
        }
        guard !scanScope.isReadOnly, !isChoosingScanFolder, pollingState != .stopped else {
            showToast("Selected-folder scans are read-only · use cleanup locations separately", isError: true)
            return false
        }
        guard lastScanComplete, !scanResultsArePartial, pollingState != .suspended else {
            showToast("Partial or unavailable scan results are read-only · run a complete scan first", isError: true)
            return false
        }
        // Do not trust a stale/caller-created item or expose unsafe data deletion.
        guard item.safeToDelete,
            let scanned = diskCategories.flatMap(\.items).first(where: { $0 == item }),
            scanned.safeToDelete
        else {
            showToast("Protected data · review in Finder instead", isError: true)
            return false
        }
        let ok = trashItem(scanned)
        if ok {
            removeTrashedItem(scanned)
            cleanupQueue.removeAll { $0.id == scanned.id }
            cleanupReview = nil
            showToast("Moved to Trash · \(scanned.sizeFormatted)")
        } else {
            showToast("Could not delete item", isError: true)
        }
        return ok
    }

    // MARK: - Reviewed Cleanup Queue

    func canQueueCleanupItem(_ item: DiskItem) -> Bool {
        !cleanupIsBlocked && item.safeToDelete && item.isDirectory && item.id == item.path
            && diskCategories.flatMap(\.items).contains(item) && cleanupEligibility(item)
    }

    @discardableResult
    func queueCleanupItem(_ item: DiskItem) -> Bool {
        guard canQueueCleanupItem(item) else { return false }
        if cleanupQueue.contains(item) { return true }
        guard cleanupQueue.count < CleanupQueue.limit,
            !cleanupQueue.contains(where: { $0.path.hasPrefix(item.path + "/") || item.path.hasPrefix($0.path + "/") })
        else {
            showToast("Queue is full or contains an overlapping location", isError: true)
            return false
        }
        cleanupQueue.append(item)
        cleanupReview = nil
        return true
    }

    func removeQueuedCleanupItem(_ id: String) {
        guard !isPerformingCleanup else { return }
        cleanupQueue.removeAll { $0.id == id }
        cleanupReview = nil
    }

    func clearCleanupQueue() {
        guard !isPerformingCleanup else { return }
        cleanupQueue = []
        cleanupReview = nil
    }

    func prepareCleanupReview() -> CleanupReview? {
        guard !cleanupIsBlocked, !cleanupQueue.isEmpty,
            cleanupQueue.allSatisfy(canQueueCleanupItem)
        else { return nil }
        singleItemTrashReview = nil
        let review = CleanupReview(id: UUID(), scanRevision: diskScanGeneration, items: cleanupQueue)
        cleanupReview = review
        return review
    }

    func canConfirmCleanup(_ review: CleanupReview) -> Bool {
        !cleanupIsBlocked && cleanupReview == review && review.scanRevision == diskScanGeneration
            && review.items == cleanupQueue && !review.items.isEmpty
            && review.items.allSatisfy { $0.safeToDelete && diskCategories.flatMap(\.items).contains($0) }
    }

    func dismissCleanupReview(_ review: CleanupReview) {
        if !isPerformingCleanup, cleanupReview?.id == review.id { cleanupReview = nil }
    }

    @discardableResult
    func confirmCleanup(_ review: CleanupReview) -> Bool {
        guard canConfirmCleanup(review), review.items.allSatisfy(cleanupEligibility) else { return false }
        cleanupReview = nil  // One-shot authorization, never a retry capability.
        singleItemTrashReview = nil
        cleanupResults = []
        cleanupRunID = review.id
        isPerformingCleanup = true
        isStoppingCleanup = false
        let client = cleanupTrashClient
        cleanupTask = Task { @MainActor [self] in
            for item in review.items {
                guard !isStoppingCleanup, !Task.isCancelled, pollingState != .stopped,
                    pollingState != .suspended, review.scanRevision == diskScanGeneration
                else {
                    cleanupResults.append(.init(item: item, outcome: .notAttempted("Cleanup was stopped")))
                    continue
                }
                guard !scanScope.isReadOnly, lastScanComplete, !scanResultsArePartial,
                    diskCategories.flatMap(\.items).contains(item), cleanupEligibility(item)
                else {
                    cleanupResults.append(
                        .init(item: item, outcome: .notAttempted("Location changed or is no longer eligible")))
                    continue
                }
                // A filesystem call already in flight cannot be cancelled. Its
                // result is always accounted for, even if Stop/Quit/sleep arrives.
                let outcome = await Task.detached(priority: .userInitiated) { client.move(item) }.value
                cleanupResults.append(.init(item: item, outcome: outcome))
                if outcome == .movedToTrash {
                    removeTrashedItem(item)
                    cleanupQueue.removeAll { $0.id == item.id }
                }
            }
            isPerformingCleanup = false
            isStoppingCleanup = false
            cleanupTask = nil
            let moved = cleanupResults.filter { $0.outcome == .movedToTrash }.count
            if pollingState != .stopped {
                showToast(
                    "Cleanup finished · \(moved) of \(review.items.count) locations moved to Trash",
                    isError: moved != review.items.count)
            }
        }
        return true
    }

    func stopCleanup() {
        guard isPerformingCleanup else { return }
        isStoppingCleanup = true
        cleanupTask?.cancel()
    }

    func waitForCleanup() async { await cleanupTask?.value }

    func clearCleanupResults() {
        guard !isPerformingCleanup else { return }
        cleanupResults = []
    }

    private func invalidateCleanupSelection() {
        singleItemTrashReview = nil
        cleanupQueue = []
        cleanupReview = nil
        cleanupResults = []
        cleanupRunID = nil
    }

    private func removeTrashedItem(_ item: DiskItem) {
        for index in diskCategories.indices {
            diskCategories[index].items.removeAll { $0.id == item.id }
            diskCategories[index].bytes = CleanupQueue.totalBytes(diskCategories[index].items)
        }
        diskCategories.removeAll { $0.items.isEmpty }
    }

    // MARK: - Toast

    func showToast(_ text: String, isError: Bool = false) {
        guard pollingState != .stopped else { return }
        // Routine refresh/success statuses must not erase an unread failure.
        // Suppressed statuses are not queued or replayed after dismissal.
        guard isError || toast?.isError != true else { return }
        guard toast?.text != text || toast?.isError != isError else { return }
        toastClearTask?.cancel()
        toastClearTask = nil
        let message = ToastMessage(text: text, isError: isError)
        toast = message
        accessibilityStatusClient.announce(message)
        // Failure feedback remains until dismissed or superseded by a failure;
        // a fleeting 2.2s status cannot be its only accessible presentation.
        guard !isError, pollingState != .stopped, toast?.id == message.id else { return }
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            if self?.toast?.id == message.id { self?.toast = nil }
        }
    }

    func dismissToast(id: UUID) {
        guard toast?.id == id else { return }
        toastClearTask?.cancel()
        toastClearTask = nil
        toast = nil
    }
}
