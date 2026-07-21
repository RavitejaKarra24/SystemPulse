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

    // MARK: - Private
    private let sampler = SystemSampler()
    private var timer: Timer?
    private var prevNet: NetworkSnapshot?
    private var sessionOriginNet: NetworkSnapshot?
    private var tick = 0
    private var toastClearTask: Task<Void, Never>?
    private let preferences = Preferences.shared

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
            Task { @MainActor in
                self?.sample()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        tick += 1

        cpuUsage = sampler.overallCPU()
        perCoreCPU = sampler.perCoreCPU()
        appendHistory(&cpuHistory, value: cpuUsage)
        cpuPeak = max(cpuPeak, cpuUsage)

        memoryBreakdown = sampler.memoryBreakdown()
        appendHistory(&memoryHistory, value: Double(memoryBreakdown.used))
        memoryPeakPercent = max(memoryPeakPercent, memoryUsage)

        let dsk = sampler.diskUsage()
        diskUsed = dsk.used
        diskFree = dsk.free
        diskTotal = dsk.total
        diskUsage = dsk.total > 0 ? Double(dsk.used) / Double(dsk.total) * 100 : 0

        let net = sampler.networkSnapshot()
        if sessionOriginNet == nil {
            sessionOriginNet = net
        }
        if let origin = sessionOriginNet {
            sessionBytesIn = net.bytesIn &- origin.bytesIn
            sessionBytesOut = net.bytesOut &- origin.bytesOut
        }
        if let prev = prevNet {
            let dt = net.timestamp.timeIntervalSince(prev.timestamp)
            if dt > 0 {
                netInRate = Double(net.bytesIn &- prev.bytesIn) / dt
                netOutRate = Double(net.bytesOut &- prev.bytesOut) / dt
            }
        }
        prevNet = net
        appendHistory(&netHistory, value: netInRate + netOutRate)
        appendHistory(&netInHistory, value: netInRate)
        appendHistory(&netOutHistory, value: netOutRate)
        netInPeak = max(netInPeak, netInRate)
        netOutPeak = max(netOutPeak, netOutRate)

        systemInfo = sampler.systemInfo()

        // Process grouping is heavier — refresh every other tick.
        if tick % 2 == 0 {
            Task.detached(priority: .utility) { [sampler] in
                let groups = sampler.groupedProcesses()
                let top = groups.first
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.processGroups = groups
                    self.topProcessName = top?.name ?? "—"
                    self.topProcessCPU = top?.totalCPU ?? 0
                }
            }
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
