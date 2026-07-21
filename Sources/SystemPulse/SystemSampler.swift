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

    deinit {
        if let prev = prevCPUInfo {
            let prevSize = vm_size_t(prevCPUCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }
    }

    // MARK: - Overall CPU

    func overallCPU() -> Double {
        let cores = perCoreCPU()
        guard !cores.isEmpty else { return 0 }
        return cores.reduce(0, +) / Double(cores.count)
    }

    // MARK: - Per-core CPU

    func perCoreCPU() -> [Double] {
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
        guard result == KERN_SUCCESS, let info = cpuInfo else { return [] }

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

        return usages
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

        let pageSize   = UInt64(vm_kernel_page_size)
        let active     = UInt64(stats.active_count) * pageSize
        let wired      = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let inactive   = UInt64(stats.inactive_count) * pageSize
        let free       = UInt64(stats.free_count) * pageSize

        return MemoryBreakdown(
            app: active,
            wired: wired,
            compressed: compressed,
            cached: inactive,
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

    func diskUsage() -> DiskUsage {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let total = attrs[.systemSize] as? UInt64 ?? 0
            let free  = attrs[.systemFreeSize] as? UInt64 ?? 0
            return DiskUsage(total: total, used: total > free ? total - free : 0, free: free)
        } catch {
            return DiskUsage(total: 0, used: 0, free: 0)
        }
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
                    // pti_total_user / pti_total_system are nanoseconds on modern macOS.
                    let totalNs = dUser + dSystem
                    cpuPercent = (Double(totalNs) / (dt * 1_000_000_000)) * 100
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
