import Foundation

/// Persisted identifiers stay independent of localized/display titles.
enum MenuBarMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpu, memory, network, disk, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .network: return "Network"
        case .disk: return "Disk"
        case .battery: return "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery: return "battery.100percent"
        }
    }

    /// Keep the first occurrence in user order. Bound work even for malformed persisted arrays.
    static func normalized(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        var seen = Set<MenuBarMetric>()
        let result = metrics.prefix(64).filter { seen.insert($0).inserted }
        return result.isEmpty ? [.cpu] : result
    }
}

/// A snapshot, not a source of telemetry. Nil means unavailable (including desktops without a battery).
/// Network callers supply aggregate rates, irrespective of the network page's selected interface.
struct MenuBarReadings: Sendable {
    let cpuPercent: Double?
    let memoryPercent: Double?
    let networkDownloadBps: Double?
    let networkUploadBps: Double?
    let diskUsedPercent: Double?
    let diskAvailableBytes: UInt64?
    let batteryChargePercent: Double?

    init(
        cpuPercent: Double? = nil,
        memoryPercent: Double? = nil,
        networkDownloadBps: Double? = nil,
        networkUploadBps: Double? = nil,
        diskUsedPercent: Double? = nil,
        diskAvailableBytes: UInt64? = nil,
        batteryChargePercent: Double? = nil
    ) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.networkDownloadBps = networkDownloadBps
        self.networkUploadBps = networkUploadBps
        self.diskUsedPercent = diskUsedPercent
        self.diskAvailableBytes = diskAvailableBytes
        self.batteryChargePercent = batteryChargePercent
    }
}
