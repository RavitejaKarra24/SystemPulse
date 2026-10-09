import Darwin
import Foundation

/// Collects real-time system metrics via Mach and BSD APIs.
final class SystemSampler: @unchecked Sendable {

    // MARK: - CPU state

    private var prevCPUInfo: processor_info_array_t?
    private var prevCPUCount: mach_msg_type_number_t = 0
    private let lock = NSLock()

    // Per-process CPU tracking
    private var prevProcessCPU: [pid_t: (user: UInt64, system: UInt64, timestamp: Date)] = [:]

    /// `proc_taskinfo` reports CPU time in mach absolute units, not nanoseconds.
    /// The two happen to be 1:1 on Intel, but Apple Silicon uses a 125/3
    /// timebase — treating the raw value as nanoseconds under-reports every
    /// process by ~41x there.
    private static let machTimebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else {
            return (1, 1)
        }
        return (UInt64(info.numer), UInt64(info.denom))
    }()

    private static func machTicksToNanoseconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(machTimebase.numer) / Double(machTimebase.denom)
    }

    deinit {
        if let prev = prevCPUInfo {
            let prevSize = vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
    }

    // MARK: - CPU

    struct CPUSample: Sendable {
        let perCore: [Double]
        /// A first/reset sample is a counter baseline, not proof of recovery.
        var hasInterval = true

        var overall: Double {
            guard !perCore.isEmpty else { return 0 }
            return perCore.reduce(0, +) / Double(perCore.count)
        }
    }

    /// Samples every core once and derives the overall figure from it.
    ///
    /// Each call consumes the previous tick counters, so calling it twice per
    /// refresh would make the second call measure a microsecond-wide window.
    /// Callers take one sample per tick and read both values off it.
    func cpuSample(resetBaseline: Bool = false) -> CPUSample {
        lock.lock()
        defer { lock.unlock() }
        if resetBaseline, let previous = prevCPUInfo {
            let size = vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previous), size)
            prevCPUInfo = nil
            prevCPUCount = 0
        }

        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return CPUSample(perCore: []) }

        let hasInterval = prevCPUInfo != nil && prevCPUCount == numCPUInfo
        var usages: [Double] = []
        usages.reserveCapacity(Int(numCPUs))

        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let current = Array(UnsafeBufferPointer(start: info + offset, count: Int(CPU_STATE_MAX)))
            let previous: [Int32]?
            if let prev = prevCPUInfo, prevCPUCount == numCPUInfo {
                previous = Array(UnsafeBufferPointer(start: prev + offset, count: Int(CPU_STATE_MAX)))
            } else {
                previous = nil
            }
            usages.append(Self.cpuUsage(current: current, previous: previous))
        }

        if let prev = prevCPUInfo {
            let prevSize = vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
        prevCPUInfo = cpuInfo
        prevCPUCount = numCPUInfo

        return CPUSample(perCore: usages, hasInterval: hasInterval)
    }

    /// Mach exposes unsigned 32-bit tick counters through a signed integer
    /// pointer. Wrapping subtraction handles crossing the sign bit and wraparound.
    /// The first sample establishes a baseline, not a since-boot average.
    static func cpuUsage(current: [Int32], previous: [Int32]?) -> Double {
        guard current.count == Int(CPU_STATE_MAX), let previous,
            previous.count == current.count
        else { return 0 }
        let deltas = zip(current, previous).map { Double(UInt32(bitPattern: $0) &- UInt32(bitPattern: $1)) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return 0 }
        return (total - deltas[Int(CPU_STATE_IDLE)]) / total * 100
    }

    // MARK: - Memory

    /// Public BSD API. Distinguish unavailable readings from a real zero-byte result.
    static func swapUsed(
        query: (inout xsw_usage, inout Int) -> Int32 = { usage, size in
            sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        }
    ) -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        guard query(&usage, &size) == 0, size == MemoryLayout<xsw_usage>.stride else { return nil }
        return usage.xsu_used
    }

    func memoryBreakdown(
        query: (inout vm_statistics64, inout mach_msg_type_number_t) -> kern_return_t = { stats, count in
            withUnsafeMutablePointer(to: &stats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
                }
            }
        }
    ) -> MemoryBreakdown {
        let total = UInt64(Foundation.ProcessInfo.processInfo.physicalMemory)
        let swap = Self.swapUsed()

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let expectedCount = count
        let result = query(&stats, &count)
        guard result == KERN_SUCCESS, count == expectedCount else {
            // A known physical capacity is not a valid usage/headroom reading.
            // Zero total is the existing unavailable marker throughout the UI,
            // exports and alert boundary; never synthesize 0% headroom.
            return MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: 0)
        }

        // Mirrors Activity Monitor's accounting: "App Memory" is anonymous
        // (internal) memory minus what's purgeable, and file-backed pages plus
        // purgeable pages are the reclaimable cache — not app footprint.
        let pageSize = UInt64(vm_kernel_page_size)
        let purgeable = UInt64(stats.purgeable_count)
        let internalP = UInt64(stats.internal_page_count)
        let externalP = UInt64(stats.external_page_count)

        let app = (internalP > purgeable ? internalP - purgeable : 0) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached = (externalP + purgeable) * pageSize
        let free = UInt64(stats.free_count) * pageSize

        return MemoryBreakdown(
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            free: free,
            total: total,
            swapUsed: swap
        )
    }

    // MARK: - Disk

    struct DiskUsage: Sendable {
        let total: UInt64
        let used: UInt64
        let free: UInt64
    }

    /// Reports capacity the way Finder does. On APFS, raw `statfs` free space
    /// understates what's actually available because it ignores purgeable
    /// (snapshot / cache) bytes macOS will reclaim on demand.
    func diskUsage() -> DiskUsage {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        {
            let totalBytes = UInt64(max(0, total))
            let freeBytes = min(UInt64(max(0, available)), totalBytes)
            return DiskUsage(total: totalBytes, used: totalBytes - freeBytes, free: freeBytes)
        }

        // Fall back to statfs on volumes that don't publish the modern keys.
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) else {
            return DiskUsage(total: 0, used: 0, free: 0)
        }
        let total = attrs[.systemSize] as? UInt64 ?? 0
        let free = attrs[.systemFreeSize] as? UInt64 ?? 0
        return DiskUsage(total: total, used: total > free ? total - free : 0, free: free)
    }

    // MARK: - Network

    /// One AF_LINK reading per physical interface. IP address entries must not
    /// be counted again; bridge/loopback/tunnel traffic duplicates physical I/O.
    func networkSnapshot() -> NetworkSnapshot {
        var snapshot = NetworkSnapshot()
        let interfaces = NetworkInterfaceSampler.sample()
        snapshot.interfaces = interfaces
        var counters: [String: ByteCounters] = [:]
        for interface in interfaces {
            counters[interface.id] = ByteCounters(first: interface.bytesIn, second: interface.bytesOut)
            let received = snapshot.bytesIn.addingReportingOverflow(interface.bytesIn)
            let sent = snapshot.bytesOut.addingReportingOverflow(interface.bytesOut)
            snapshot.bytesIn = received.overflow ? .max : received.partialValue
            snapshot.bytesOut = sent.overflow ? .max : sent.partialValue
        }
        snapshot.interfaceCounters = counters
        return snapshot
    }

    static func isPhysicalNetworkInterface(_ name: String, family: UInt8?) -> Bool {
        family == UInt8(AF_LINK) && NetworkInterfaceSampler.isPhysicalName(name)
    }

    // MARK: - System info

    func systemInfo() -> SystemInfo {
        var info = SystemInfo()

        var loads: [Double] = [0, 0, 0]
        if getloadavg(&loads, 3) == 3 {
            info.loadAverage1 = loads[0]
            info.loadAverage5 = loads[1]
            info.loadAverage15 = loads[2]
        }

        info.processCount = Self.processIDs().count

        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &boottime, &size, nil, 0) == 0, boottime.tv_sec != 0 {
            let boot = Date(timeIntervalSince1970: TimeInterval(boottime.tv_sec))
            info.uptime = Date().timeIntervalSince(boot)
        }

        info.thermalState = ProcessInfo.processInfo.thermalState
        info.coreCount = ProcessInfo.processInfo.activeProcessorCount
        return info
    }

    // MARK: - Processes

    /// Unlike proc_listpids, proc_listallpids returns a PID *count*, not bytes.
    /// Its sizing pass includes padding; count the populated buffer for telemetry.
    static func processIDs(list: (UnsafeMutableRawPointer?, Int32) -> Int32 = { proc_listallpids($0, $1) }) -> [pid_t] {
        let estimate = list(nil, 0)
        guard estimate > 0 else { return [] }
        var capacity = Int(estimate) + 16
        for attempt in 0..<3 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes { list($0.baseAddress, Int32($0.count)) }
            guard count > 0 else { return [] }
            if Int(count) < capacity || attempt == 2 {
                return Array(pids.prefix(min(Int(count), capacity)))
            }
            capacity *= 2
        }
        return []
    }

    /// Builds a flat list of live process stats (real-time CPU %, resident memory, bundle metadata).
    func processStats() -> [ProcessStat] {
        lock.lock()
        defer { lock.unlock() }

        let pids = Self.processIDs()
        guard !pids.isEmpty else { return [] }
        let pidCount = pids.count
        let now = Date()
        var results: [ProcessStat] = []
        results.reserveCapacity(min(pidCount, 256))
        let myPid = getpid()

        for i in 0..<pidCount {
            let pid = pids[i]
            if pid <= 0 || pid == myPid { continue }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard ret == taskInfoSize else { continue }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
            let path = String(
                decoding: pathBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let rawName = (path as NSString).lastPathComponent
            if rawName.isEmpty { continue }

            let currentUser = UInt64(taskInfo.pti_total_user)
            let currentSystem = UInt64(taskInfo.pti_total_system)
            var cpuPercent = 0.0

            if let prev = prevProcessCPU[pid] {
                let dt = now.timeIntervalSince(prev.timestamp)
                if dt > 0 {
                    let dUser = currentUser > prev.user ? currentUser - prev.user : 0
                    let dSystem = currentSystem > prev.system ? currentSystem - prev.system : 0
                    let totalNs = Self.machTicksToNanoseconds(dUser + dSystem)
                    cpuPercent = (totalNs / (dt * 1_000_000_000)) * 100
                }
            }
            prevProcessCPU[pid] = (user: currentUser, system: currentSystem, timestamp: now)

            let resident = UInt64(taskInfo.pti_resident_size)
            let threads = Int(taskInfo.pti_threadnum)
            let bundle = ProcessMetadataProvider.bundleInfo(for: path)
            let iconKey = bundle.bundlePath ?? path
            let displayName = bundle.displayName ?? rawName

            results.append(
                ProcessStat(
                    id: pid,
                    name: displayName,
                    executablePath: path,
                    bundlePath: bundle.bundlePath,
                    bundleIdentifier: bundle.bundleIdentifier,
                    cpu: max(0, cpuPercent),
                    memory: resident,
                    threadCount: threads,
                    iconKey: iconKey
                ))
        }

        let activePids = Set(pids[0..<pidCount])
        prevProcessCPU = prevProcessCPU.filter { activePids.contains($0.key) }

        return results
    }

    /// Groups processes by their owning app bundle. Processes with no enclosing
    /// `.app` (daemons, kernel tasks, helpers) are rolled into one "System" group.
    func groupedProcesses(resetBaseline: Bool = false) -> [ProcessGroup] {
        // The store allows only one process pass in flight; reset on that same
        // sampling path, never concurrently from a main-actor wake callback.
        if resetBaseline { prevProcessCPU.removeAll() }
        let stats = processStats()
        var buckets: [String: [ProcessStat]] = [:]
        var names: [String: String] = [:]

        for stat in stats {
            let key = stat.bundlePath ?? "system"
            buckets[key, default: []].append(stat)
            if names[key] == nil {
                names[key] = stat.bundlePath != nil ? stat.name : "System"
            }
        }

        var groups: [ProcessGroup] = []
        groups.reserveCapacity(buckets.count)
        for (key, procs) in buckets {
            let sorted = procs.sorted { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.memory > $1.memory }
            let isSystem = (key == "system")
            groups.append(
                ProcessGroup(
                    id: key,
                    name: names[key] ?? "System",
                    iconKey: isSystem ? nil : key,
                    isSystemGroup: isSystem,
                    processes: sorted
                ))
        }

        return groups.sorted {
            $0.totalCPU != $1.totalCPU ? $0.totalCPU > $1.totalCPU : $0.totalMemory > $1.totalMemory
        }
    }
}
