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

    struct CPUSample {
        let perCore: [Double]

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
    func cpuSample() -> CPUSample {
        lock.lock()
        defer { lock.unlock() }

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

        var usages: [Double] = []
        usages.reserveCapacity(Int(numCPUs))

        for i in 0 ..< Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user   = Int64(info[offset + Int(CPU_STATE_USER)])
            let system = Int64(info[offset + Int(CPU_STATE_SYSTEM)])
            let nice   = Int64(info[offset + Int(CPU_STATE_NICE)])
            let idle   = Int64(info[offset + Int(CPU_STATE_IDLE)])

            if let prev = prevCPUInfo {
                let pUser   = Int64(prev[offset + Int(CPU_STATE_USER)])
                let pSystem = Int64(prev[offset + Int(CPU_STATE_SYSTEM)])
                let pNice   = Int64(prev[offset + Int(CPU_STATE_NICE)])
                let pIdle   = Int64(prev[offset + Int(CPU_STATE_IDLE)])

                let dUser   = user - pUser
                let dSystem = system - pSystem
                let dNice   = nice - pNice
                let dIdle   = idle - pIdle
                let total   = dUser + dSystem + dNice + dIdle

                let usage = total > 0 ? Double(dUser + dSystem + dNice) / Double(total) * 100 : 0
                usages.append(min(100, max(0, usage)))
            } else {
                let total = user + system + nice + idle
                let usage = total > 0 ? Double(user + system + nice) / Double(total) * 100 : 0
                usages.append(min(100, max(0, usage)))
            }
        }

        if let prev = prevCPUInfo {
            let prevSize = vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
        prevCPUInfo = cpuInfo
        prevCPUCount = numCPUInfo

        return CPUSample(perCore: usages)
    }

    // MARK: - Memory

    func memoryBreakdown() -> MemoryBreakdown {
        let total = UInt64(Foundation.ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: total)
        }

        // Mirrors Activity Monitor's accounting: "App Memory" is anonymous
        // (internal) memory minus what's purgeable, and file-backed pages plus
        // purgeable pages are the reclaimable cache — not app footprint.
        let pageSize   = UInt64(vm_kernel_page_size)
        let purgeable  = UInt64(stats.purgeable_count)
        let internalP  = UInt64(stats.internal_page_count)
        let externalP  = UInt64(stats.external_page_count)

        let app        = (internalP > purgeable ? internalP - purgeable : 0) * pageSize
        let wired      = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let cached     = (externalP + purgeable) * pageSize
        let free       = UInt64(stats.free_count) * pageSize

        return MemoryBreakdown(
            app: app,
            wired: wired,
            compressed: compressed,
            cached: cached,
            free: free,
            total: total
        )
    }

    // MARK: - Disk

    struct DiskUsage {
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
            .volumeAvailableCapacityForImportantUsageKey
        ]),
           let total = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacityForImportantUsage {
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

    /// Sums bytes across physical interfaces only — explicitly excludes the
    /// loopback (`lo0`) interface so local traffic doesn't inflate stats.
    func networkSnapshot() -> NetworkSnapshot {
        var snapshot = NetworkSnapshot()
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return snapshot
        }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            let name = String(cString: ifa.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("pdp_ip") {
                if let data = ifa.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    snapshot.bytesIn  += UInt64(networkData.ifi_ibytes)
                    snapshot.bytesOut += UInt64(networkData.ifi_obytes)
                }
            }
            cursor = ifa.pointee.ifa_next
        }
        return snapshot
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

        let bufferSize = proc_listallpids(nil, 0)
        if bufferSize > 0 {
            info.processCount = Int(bufferSize) / MemoryLayout<pid_t>.size
        }

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

    /// Builds a flat list of live process stats (real-time CPU %, resident memory, bundle metadata).
    func processStats() -> [ProcessStat] {
        lock.lock()
        defer { lock.unlock() }

        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(bufferSize) / MemoryLayout<pid_t>.size + 16)
        let actualSize = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard actualSize > 0 else { return [] }

        let pidCount = Int(actualSize) / MemoryLayout<pid_t>.size
        let now = Date()
        var results: [ProcessStat] = []
        results.reserveCapacity(min(pidCount, 256))
        let myPid = getpid()

        for i in 0 ..< pidCount {
            let pid = pids[i]
            if pid <= 0 || pid == myPid { continue }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard ret == taskInfoSize else { continue }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            proc_pidpath(pid, &pathBuffer, UInt32(MAXPATHLEN))
            let path = String(decoding: pathBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
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

            results.append(ProcessStat(
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
    func groupedProcesses() -> [ProcessGroup] {
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
            groups.append(ProcessGroup(
                id: key,
                name: names[key] ?? "System",
                iconKey: isSystem ? nil : key,
                isSystemGroup: isSystem,
                processes: sorted
            ))
        }

        return groups.sorted { $0.totalCPU != $1.totalCPU ? $0.totalCPU > $1.totalCPU : $0.totalMemory > $1.totalMemory }
    }
}
