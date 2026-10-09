import Darwin
import Foundation
import SystemConfiguration

public enum NetworkInterfaceKind: String, Sendable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case physical = "Physical interface"
}

/// One physical BSD interface, not one entry per IP address. Counters are cumulative, not session totals.
public struct NetworkInterfaceSnapshot: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let displayName: String
    public let addresses: [String]
    /// Both IFF_UP and IFF_RUNNING. This does not imply Internet reachability.
    public let isActive: Bool
    public let kind: NetworkInterfaceKind
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(
        name: String, displayName: String, addresses: [String], isActive: Bool,
        kind: NetworkInterfaceKind, bytesIn: UInt64, bytesOut: UInt64
    ) {
        self.name = name
        self.displayName = displayName
        self.addresses = addresses
        self.isActive = isActive
        self.kind = kind
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Public, read-only local APIs only: no sockets, DNS, SSID queries or location authorization.
public enum NetworkInterfaceSampler {
    public static func sample() -> [NetworkInterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }

        var records: [Record] = []
        var cursor = head
        while let pointer = cursor {
            let entry = pointer.pointee
            cursor = entry.ifa_next
            guard let namePointer = entry.ifa_name, let address = entry.ifa_addr else { continue }
            let name = String(cString: namePointer)
            guard isPhysicalName(name) else { continue }
            let family = address.pointee.sa_family
            var counters: ByteCounters?
            if family == UInt8(AF_LINK), let data = entry.ifa_data {
                let link = data.assumingMemoryBound(to: if_data.self).pointee
                counters = ByteCounters(first: UInt64(link.ifi_ibytes), second: UInt64(link.ifi_obytes))
            }
            records.append(
                Record(
                    name: name, family: family, flags: entry.ifa_flags, counters: counters,
                    address: localAddress(UnsafePointer(address), interfaceName: name)
                )
            )
        }
        return snapshots(from: records, metadata: interfaceMetadata())
    }

    static func isPhysicalName(_ name: String) -> Bool {
        // Preserve the aggregate's en* scope; exclude bridges, tunnels, loopback and peer-to-peer links.
        name.hasPrefix("en")
    }

    struct Metadata {
        let displayName: String
        let kind: NetworkInterfaceKind
    }

    /// Value-based seam for deterministic tests of the same grouping used by getifaddrs.
    struct Record {
        let name: String
        let family: UInt8
        let flags: UInt32
        let counters: ByteCounters?
        let address: String?
    }

    static func snapshots(from records: [Record], metadata: [String: Metadata] = [:]) -> [NetworkInterfaceSnapshot] {
        var links: [String: Record] = [:]
        var addresses: [String: Set<String>] = [:]
        for record in records where isPhysicalName(record.name) {
            if record.family == UInt8(AF_LINK), record.counters != nil, links[record.name] == nil {
                links[record.name] = record
            } else if record.family == UInt8(AF_INET) || record.family == UInt8(AF_INET6), let address = record.address
            {
                addresses[record.name, default: []].insert(address)
            }
        }
        return links.keys.sorted().compactMap { name in
            guard let link = links[name], let counters = link.counters else { return nil }
            let info = metadata[name]
            let activeFlags = UInt32(IFF_UP | IFF_RUNNING)
            return NetworkInterfaceSnapshot(
                name: name, displayName: info?.displayName ?? name,
                addresses: (addresses[name] ?? []).sorted(),
                isActive: link.flags & activeFlags == activeFlags,
                kind: info?.kind ?? .physical, bytesIn: counters.first, bytesOut: counters.second
            )
        }
    }

    static func localAddress(_ address: UnsafePointer<sockaddr>, interfaceName: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let family = Int32(address.pointee.sa_family)
        switch family {
        case AF_INET:
            var value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            guard inet_ntop(AF_INET, &value, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            return String(cString: buffer)
        case AF_INET6:
            let value = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in6.self).pointee
            var ip = value.sin6_addr
            guard inet_ntop(AF_INET6, &ip, &buffer, socklen_t(buffer.count)) != nil else { return nil }
            let text = String(cString: buffer)
            // Keep the local scope so link-local addresses on different interfaces remain meaningful.
            return value.sin6_scope_id == 0 ? text : "\(text)%\(interfaceName)"
        default:
            return nil
        }
    }

    private static func interfaceMetadata() -> [String: Metadata] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [:] }
        var result: [String: Metadata] = [:]
        for interface in interfaces {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?, isPhysicalName(bsdName) else {
                continue
            }
            let type = SCNetworkInterfaceGetInterfaceType(interface)
            let kind: NetworkInterfaceKind
            if type == kSCNetworkInterfaceTypeIEEE80211 {
                kind = .wifi
            } else if type == kSCNetworkInterfaceTypeEthernet {
                kind = .ethernet
            } else {
                kind = .physical
            }
            result[bsdName] = Metadata(
                displayName: SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? bsdName,
                kind: kind
            )
        }
        return result
    }
}

public struct NetworkInterfaceReading: Identifiable, Sendable {
    public let snapshot: NetworkInterfaceSnapshot
    /// False means bounded, retained metadata for a removed interface, not a live reading.
    public let isPresent: Bool
    public let inRate: Double
    public let outRate: Double
    public let sessionBytesIn: UInt64
    public let sessionBytesOut: UInt64

    public var id: String { snapshot.id }
    public var name: String { snapshot.name }
    public var displayName: String { snapshot.displayName }
    public var addresses: [String] { snapshot.addresses }
    public var isActive: Bool { isPresent && snapshot.isActive }
    public var kind: NetworkInterfaceKind { snapshot.kind }
    public var bytesIn: UInt64 { snapshot.bytesIn }
    public var bytesOut: UInt64 { snapshot.bytesOut }

    public init(
        snapshot: NetworkInterfaceSnapshot, isPresent: Bool = true, inRate: Double = 0, outRate: Double = 0,
        sessionBytesIn: UInt64 = 0, sessionBytesOut: UInt64 = 0
    ) {
        self.snapshot = snapshot
        self.isPresent = isPresent
        self.inRate = isPresent && snapshot.isActive ? inRate : 0
        self.outRate = isPresent && snapshot.isActive ? outRate : 0
        self.sessionBytesIn = sessionBytesIn
        self.sessionBytesOut = sessionBytesOut
    }
}

/// Single-owner value tracker, independent of the aggregate tracker. First/reconnected samples establish baselines.
public struct NetworkInterfaceTracker {
    private struct Entry {
        var snapshot: NetworkInterfaceSnapshot
        var counters = CounterRateTracker()
        var lastSeen: Date
        var isPresent = true
    }

    private var entries: [String: Entry] = [:]
    private var lastTimestamp: Date?
    private let disconnectedRetention: TimeInterval
    private let maxDisconnectedInterfaces: Int

    /// Missing interfaces retain session totals for at most five minutes and at most 16 entries by default.
    /// After eviction, a reappearing interface starts a new session baseline.
    public init(disconnectedRetention: TimeInterval = 300, maxDisconnectedInterfaces: Int = 16) {
        self.disconnectedRetention = disconnectedRetention.isFinite ? max(0, disconnectedRetention) : 300
        self.maxDisconnectedInterfaces = max(0, maxDisconnectedInterfaces)
    }

    public var interfaces: [NetworkInterfaceReading] {
        entries.keys.sorted().compactMap { id in
            guard let entry = entries[id] else { return nil }
            return NetworkInterfaceReading(
                snapshot: entry.snapshot, isPresent: entry.isPresent,
                inRate: entry.counters.firstRate, outRate: entry.counters.secondRate,
                sessionBytesIn: entry.counters.firstTotal, sessionBytesOut: entry.counters.secondTotal
            )
        }
    }

    mutating func resetBaselines() {
        lastTimestamp = nil
        for id in entries.keys {
            entries[id]?.counters.resetBaseline()
        }
    }

    public mutating func apply(_ snapshots: [NetworkInterfaceSnapshot], at timestamp: Date) {
        // Clear displayed rates on invalid time without consuming metadata, totals or the baseline.
        let elapsed = lastTimestamp.map { timestamp.timeIntervalSince($0) }
        guard timestamp.timeIntervalSince1970.isFinite,
            elapsed.map({ $0.isFinite && $0 > 0 }) ?? true
        else {
            if let lastTimestamp {
                for id in Array(entries.keys) {
                    entries[id]?.counters.apply([:], at: lastTimestamp)
                }
            }
            return
        }
        lastTimestamp = timestamp
        evictDisconnected(at: timestamp)

        var seen = Set<String>()
        for snapshot in snapshots where seen.insert(snapshot.id).inserted {
            var entry = entries[snapshot.id] ?? Entry(snapshot: snapshot, lastSeen: timestamp)
            entry.snapshot = snapshot
            entry.lastSeen = timestamp
            entry.isPresent = true
            let counters =
                snapshot.isActive
                ? [snapshot.id: ByteCounters(first: snapshot.bytesIn, second: snapshot.bytesOut)] : [:]
            entry.counters.apply(counters, at: timestamp)
            entries[snapshot.id] = entry
        }
        for id in Array(entries.keys) where !seen.contains(id) {
            guard var entry = entries[id] else { continue }
            entry.isPresent = false
            let old = entry.snapshot
            entry.snapshot = NetworkInterfaceSnapshot(
                name: old.name, displayName: old.displayName, addresses: [], isActive: false,
                kind: old.kind, bytesIn: old.bytesIn, bytesOut: old.bytesOut
            )
            entry.counters.apply([:], at: timestamp)
            entries[id] = entry
        }
        evictDisconnected(at: timestamp)
    }

    private mutating func evictDisconnected(at timestamp: Date) {
        entries = entries.filter {
            $0.value.isPresent || timestamp.timeIntervalSince($0.value.lastSeen) < disconnectedRetention
        }
        let missing = entries.filter { !$0.value.isPresent }.sorted {
            $0.value.lastSeen != $1.value.lastSeen ? $0.value.lastSeen > $1.value.lastSeen : $0.key < $1.key
        }
        for entry in missing.dropFirst(maxDisconnectedInterfaces) {
            entries.removeValue(forKey: entry.key)
        }
    }
}
