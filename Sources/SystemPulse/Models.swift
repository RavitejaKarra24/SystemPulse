import AppKit
import Foundation

// MARK: - Process

struct ProcessStat: Identifiable, Sendable, Hashable {
    let id: pid_t
    let name: String
    let executablePath: String
    let bundlePath: String?
    let bundleIdentifier: String?
    let cpu: Double  // real-time percentage (0-100 per core * n)
    let memory: UInt64  // resident bytes
    let threadCount: Int
    let iconKey: String  // cache key for icon lookup

    static func == (lhs: ProcessStat, rhs: ProcessStat) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var memoryMB: Double { Double(memory) / 1_048_576 }
    var memoryFormatted: String { ByteFormatter.format(memory) }
    var cpuFormatted: String { String(format: "%.2f %%", cpu) }
}

/// A group of processes rolled up under one app (or the synthetic "System" group).
struct ProcessGroup: Identifiable, Sendable {
    let id: String
    let name: String
    let iconKey: String?
    let isSystemGroup: Bool
    let processes: [ProcessStat]  // sorted desc by relevance; processes[0] is the representative

    var totalCPU: Double { processes.reduce(0) { $0 + $1.cpu } }
    var totalMemory: UInt64 { processes.reduce(0) { $0 + $1.memory } }
    var totalThreads: Int { processes.reduce(0) { $0 + $1.threadCount } }
    var extraCount: Int { max(0, processes.count - 1) }
    var main: ProcessStat? { processes.first }
}

// MARK: - Disk

struct DiskCategory: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    var bytes: UInt64
    var items: [DiskItem]

    var sizeFormatted: String { ByteFormatter.format(bytes) }
}

struct DiskItem: Identifiable, Equatable, Sendable {
    let id: String  // full path, unique
    let name: String
    let path: String
    let bytes: UInt64
    let fileCount: Int
    let isDirectory: Bool
    let categoryName: String
    let safeToDelete: Bool
    let safetyNote: String

    var sizeFormatted: String { ByteFormatter.format(bytes) }
}

// MARK: - Network

struct NetworkSnapshot: Sendable {
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0
    var timestamp: Date = .now
    /// Per-interface counters avoid spikes when links appear/disappear. `nil`
    /// preserves compatibility with callers providing only aggregate counters.
    var interfaceCounters: [String: ByteCounters]? = nil
    /// The same interface reading used by aggregate counters, avoiding a second OS query.
    var interfaces: [NetworkInterfaceSnapshot]? = nil
}

// MARK: - Memory Breakdown

struct MemoryBreakdown: Sendable {
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let free: UInt64
    let total: UInt64
    /// Bytes currently used by swap, not cumulative page-outs or compressed RAM.
    let swapUsed: UInt64?

    init(
        app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64,
        free: UInt64, total: UInt64, swapUsed: UInt64? = nil
    ) {
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.cached = cached
        self.free = free
        self.total = total
        self.swapUsed = swapUsed
    }

    var used: UInt64 { app + wired + compressed }
    var usedPercent: Double {
        total > 0 ? Double(used) / Double(total) * 100 : 0
    }

    /// Rough memory pressure signal derived from free+cached headroom.
    var pressure: MemoryPressure {
        let reclaimable = Double(free + cached)
        let totalD = Double(max(total, 1))
        let headroom = reclaimable / totalD
        if headroom < 0.08 { return .critical }
        if headroom < 0.18 { return .warning }
        return .normal
    }
}

enum MemoryPressure: String, Sendable {
    case normal = "Normal"
    case warning = "Elevated"
    case critical = "Critical"

    var colorName: String {
        switch self {
        case .normal: return "green"
        case .warning: return "orange"
        case .critical: return "red"
        }
    }
}

// MARK: - Power

struct PowerInfo: Sendable {
    var hasBattery = false
    var chargePercent: Double = 0
    var hasChargeReading = false
    var lowPowerModeEnabled: Bool?
    var isCharging = false
    var isFullyCharged = false
    var isPluggedIn = false
    /// Seconds until empty (or until full while charging). `nil` while macOS calibrates.
    var timeRemaining: TimeInterval?
    var cycleCount: Int = 0
    var hasCycleCountReading = false
    var designCycleCount: Int = 0
    /// Full-charge capacity as a share of design capacity.
    var healthPercent: Double = 0
    var fullChargeCapacity: Int = 0
    var designCapacity: Int = 0
    var temperatureC: Double?
    var adapterName: String?
    var adapterWatts: Int?
    /// Hardware-reported system input; not a calibrated wall-power measurement.
    var systemPowerWatts: Double?
    /// Battery flow: positive while charging, negative while discharging.
    var batteryPowerWatts: Double?
    var condition: String = "Normal"

    var stateLabel: String {
        guard hasBattery else { return isPluggedIn ? "AC Power" : "—" }
        if isCharging { return "Charging" }
        if isFullyCharged { return "Fully Charged" }
        if isPluggedIn { return "Plugged In" }
        return hasChargeReading ? "On Battery" : "Battery state unavailable"
    }

    /// Describes observed state, never claims to know an optimized-charging limit.
    var chargingExplanation: String {
        guard hasBattery else { return "No internal battery readings are available." }
        if isCharging { return "macOS is charging the battery. The time estimate may change with workload." }
        if isFullyCharged { return "The battery is fully charged; no time-to-full estimate is needed." }
        if isPluggedIn {
            return
                "Connected, not charging. macOS may pause charging for optimization or temperature; the exact reason and charge limit are not exposed here."
        }
        guard hasChargeReading else { return "Battery charging state is unavailable from macOS." }
        return "Running on battery. Time remaining is a macOS estimate, not a guaranteed runtime."
    }

    /// Apple treats a battery below 80% of design capacity as needing service.
    var isHealthy: Bool { healthPercent == 0 || healthPercent >= 80 }

    var timeRemainingFormatted: String {
        guard let timeRemaining, timeRemaining.isFinite, timeRemaining > 0,
            timeRemaining < Double(Int.max)
        else {
            if isFullyCharged { return "Fully charged" }
            // On AC but not charging is the steady state under optimized
            // charging — macOS publishes no estimate, and none is being made.
            if isPluggedIn && !isCharging { return "Not charging" }
            return "Estimating…"
        }
        let total = Int(timeRemaining)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let span = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return isCharging ? "\(span) to full" : "\(span) left"
    }
}

// MARK: - System Info

struct SystemInfo: Sendable {
    var loadAverage1: Double = 0
    var loadAverage5: Double = 0
    var loadAverage15: Double = 0
    var processCount: Int = 0
    var uptime: TimeInterval = 0
    var thermalState: ProcessInfo.ThermalState = .nominal
    var coreCount: Int = ProcessInfo.processInfo.activeProcessorCount
}

// MARK: - History

/// A single point in one of the rolling history graphs.
struct HistoryPoint: Identifiable, Sendable {
    let id = UUID()
    let value: Double
    let date: Date
}

// MARK: - Toast

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

// MARK: - Byte Formatter

enum ByteFormatter {
    static func format(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 100 {
            return String(format: "%.0f GB", gb)
        }
        if gb >= 1.0 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        let kb = Double(bytes) / 1024
        return String(format: "%.0f KB", kb)
    }

    static func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bytesPerSec / 1_073_741_824)
        } else if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f B/s", max(0, bytesPerSec))
        }
    }

    static func formatUptime(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Load coloring

enum LoadColor {
    static func forPercent(_ value: Double) -> ColorToken {
        if value >= 85 { return .critical }
        if value >= 65 { return .warning }
        return .normal
    }

    enum ColorToken {
        case normal, warning, critical
    }
}
