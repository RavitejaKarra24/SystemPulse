import Foundation

/// One mounted volume, not a physical disk or an additive share of an APFS container.
struct MonitoredVolume: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let mountURL: URL
    let isInternal: Bool?
    let isReadOnly: Bool
    let totalBytes: UInt64?
    let availableBytes: UInt64?
    /// True when availableBytes comes from volumeAvailableCapacityForImportantUsage.
    /// False means ordinary filesystem availability (or unavailable metadata).
    var availableForImportantUsage = false
    /// Sampling resolves the home directory's actual volume, including APFS firmlinks.
    var isHomeVolume = false

    /// This is a capacity estimate, not allocated file bytes or cleanup scan results.
    var usedBytes: UInt64? {
        guard let totalBytes, let availableBytes else { return nil }
        return totalBytes > availableBytes ? totalBytes - availableBytes : 0
    }
}

enum VolumeSampler {
    /// Injectable resource metadata. Negative capacity readings are treated as unavailable.
    struct Metadata: Sendable {
        var mountURL: URL
        var uuid: String?
        var name: String?
        var isInternal: Bool?
        var isReadOnly: Bool?
        var isHidden: Bool?
        var isBrowsable: Bool?
        var totalBytes: Int64?
        var importantAvailableBytes: Int64?
        var ordinaryAvailableBytes: Int64?
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .volumeURLKey, .volumeUUIDStringKey, .volumeNameKey, .volumeIsInternalKey,
        .volumeIsReadOnlyKey, .isHiddenKey, .volumeIsBrowsableKey,
        .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey,
    ]

    /// Read-only public Foundation metadata; no traversal, mounting, or cleanup operations.
    /// Call from the sampler's worker, not from a SwiftUI body.
    static func sample() -> [MonitoredVolume] {
        let manager = FileManager.default
        let homeValues = try? manager.homeDirectoryForCurrentUser.resourceValues(
            forKeys: [.volumeURLKey, .volumeUUIDStringKey])
        var urls = manager.mountedVolumeURLs(includingResourceValuesForKeys: Array(resourceKeys), options: []) ?? []
        // The home data volume can be hidden from Finder on modern macOS.
        if let homeVolumeURL = homeValues?.volume {
            urls.append(homeVolumeURL)
        }
        // Foundation can present a firmlinked home as '/' and omit the Data mount
        // from enumeration. Include it only if public metadata confirms a volume root.
        let startupDataURL = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        if let dataValues = try? startupDataURL.resourceValues(forKeys: [.volumeURLKey]),
            dataValues.volume?.standardizedFileURL.path == startupDataURL.path
        {
            urls.append(startupDataURL)
        }
        let metadata = urls.map { url -> Metadata in
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                return Metadata(mountURL: url)
            }
            return Metadata(
                mountURL: values.volume ?? url,
                uuid: values.volumeUUIDString,
                name: values.volumeName,
                isInternal: values.volumeIsInternal,
                isReadOnly: values.volumeIsReadOnly,
                isHidden: values.isHidden,
                isBrowsable: values.volumeIsBrowsable,
                totalBytes: values.volumeTotalCapacity.map(Int64.init),
                importantAvailableBytes: values.volumeAvailableCapacityForImportantUsage,
                ordinaryAvailableBytes: values.volumeAvailableCapacity.map(Int64.init)
            )
        }
        return sample(
            metadata: metadata, homeVolumeURL: homeValues?.volume,
            homeVolumeUUID: homeValues?.volumeUUIDString)
    }

    /// Deterministic normalization seam for tests and injected metadata providers.
    /// Distinct APFS user volumes remain selectable: Foundation exposes no container ID,
    /// and equal capacities do not prove two volumes share a container. Never sum them.
    static func sample(
        metadata: [Metadata], homeVolumeURL: URL? = nil, homeVolumeUUID: String? = nil
    ) -> [MonitoredVolume] {
        let homePath = homeVolumeURL.map { canonicalURL($0).path }
        let homeUUID = normalizedUUID(homeVolumeUUID)
        var candidates: [MonitoredVolume] = []
        for item in metadata {
            guard item.mountURL.isFileURL else { continue }
            let url = canonicalURL(item.mountURL)
            let path = url.path
            let uuid = normalizedUUID(item.uuid)
            let isHome = (homeUUID != nil && uuid == homeUUID) || path == homePath
            let isStartup = path == "/" || path == "/System/Volumes/Data"
            // Do not filter by display name: an external user volume can be named Preboot.
            // Canonicalization may expose /private aliases as /var, /tmp, or /etc.
            let isHelper = ["/System", "/dev", "/private", "/var", "/tmp", "/etc"].contains {
                path == $0 || path.hasPrefix($0 + "/")
            }
            guard !isHelper || path == "/System/Volumes/Data" else { continue }
            let isHidden = item.isHidden == true || url.lastPathComponent.hasPrefix(".")
            guard isHome || isStartup || (!isHidden && item.isBrowsable != false) else { continue }

            let important = capacity(item.importantAvailableBytes)
            let rawName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name =
                rawName.flatMap { $0.isEmpty ? nil : $0 } ?? (path == "/" ? "Startup volume" : url.lastPathComponent)
            candidates.append(
                MonitoredVolume(
                    id: uuid.map { "uuid:\($0)" } ?? "mount:\(url.absoluteString)",
                    name: name, mountURL: url, isInternal: item.isInternal,
                    isReadOnly: item.isReadOnly ?? false,
                    totalBytes: capacity(item.totalBytes),
                    availableBytes: important ?? capacity(item.ordinaryAvailableBytes),
                    availableForImportantUsage: important != nil,
                    isHomeVolume: isHome
                ))
        }
        // The sealed startup System volume and its Data partner are one user-facing choice.
        if candidates.contains(where: { $0.mountURL.path == "/System/Volumes/Data" }) {
            candidates.removeAll { $0.mountURL.path == "/" }
        }
        // Prefer the real home mount, stable UUID identity, then complete metadata.
        candidates.sort {
            if $0.isHomeVolume != $1.isHomeVolume { return $0.isHomeVolume }
            if $0.id.hasPrefix("uuid:") != $1.id.hasPrefix("uuid:") { return $0.id.hasPrefix("uuid:") }
            let left = completeness($0)
            let right = completeness($1)
            if left != right { return left > right }
            return orderedBefore($0, $1)
        }
        var ids: Set<String> = []
        var paths: Set<String> = []
        return candidates.filter {
            guard !ids.contains($0.id), !paths.contains($0.mountURL.path) else { return false }
            ids.insert($0.id)
            paths.insert($0.mountURL.path)
            return true
        }.sorted(by: orderedBefore)
    }

    private static func capacity(_ value: Int64?) -> UInt64? {
        guard let value, value >= 0 else { return nil }
        return UInt64(value)
    }

    private static func normalizedUUID(_ uuid: String?) -> String? {
        guard let value = uuid?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value.lowercased()
    }

    private static func canonicalURL(_ url: URL) -> URL {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        // Mount roots are directories; URL trailing-slash hints must not change identity.
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func completeness(_ volume: MonitoredVolume) -> Int {
        (volume.totalBytes == nil ? 0 : 1) + (volume.availableBytes == nil ? 0 : 1)
            + (volume.isInternal == nil ? 0 : 1) + (volume.availableForImportantUsage ? 1 : 0)
    }

    static func orderedBefore(_ lhs: MonitoredVolume, _ rhs: MonitoredVolume) -> Bool {
        if lhs.isHomeVolume != rhs.isHomeVolume { return lhs.isHomeVolume }
        if (lhs.isInternal == true) != (rhs.isInternal == true) { return lhs.isInternal == true }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        if lhs.mountURL.path != rhs.mountURL.path { return lhs.mountURL.path < rhs.mountURL.path }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        // Conflicting duplicate samples still have an enumeration-independent winner.
        if lhs.isReadOnly != rhs.isReadOnly { return lhs.isReadOnly }
        if lhs.availableForImportantUsage != rhs.availableForImportantUsage { return lhs.availableForImportantUsage }
        if (lhs.isInternal == nil) != (rhs.isInternal == nil) { return lhs.isInternal != nil }
        if (lhs.totalBytes == nil) != (rhs.totalBytes == nil) { return lhs.totalBytes != nil }
        if lhs.totalBytes != rhs.totalBytes { return (lhs.totalBytes ?? 0) > (rhs.totalBytes ?? 0) }
        if (lhs.availableBytes == nil) != (rhs.availableBytes == nil) { return lhs.availableBytes != nil }
        return (lhs.availableBytes ?? 0) > (rhs.availableBytes ?? 0)
    }
}

struct VolumeSelection {
    /// Does not mutate selectedID. The owner can detect a removed ID before persisting
    /// the fallback and presenting feedback; a disconnected volume never retains readings.
    static func resolve(selectedID: String?, in volumes: [MonitoredVolume]) -> MonitoredVolume? {
        resolve(selectedID: selectedID, in: volumes, homeURL: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Injectable home path; sampled isHomeVolume also handles startup APFS firmlinks.
    static func resolve(
        selectedID: String?, in volumes: [MonitoredVolume], homeURL: URL
    ) -> MonitoredVolume? {
        if let selectedID, let selected = volumes.first(where: { $0.id == selectedID }) { return selected }
        let ordered = volumes.sorted(by: VolumeSampler.orderedBefore)
        if let home = ordered.first(where: \.isHomeVolume) { return home }
        let homePath = homeURL.standardizedFileURL.path
        // Longest mount-prefix match, on a path-component boundary (not /Volumes/Home2).
        if let home = ordered.filter({
            let path = $0.mountURL.standardizedFileURL.path
            return path != "/" && (homePath == path || homePath.hasPrefix(path + "/"))
        }).sorted(by: { $0.mountURL.path.count > $1.mountURL.path.count }).first {
            return home
        }
        if let data = ordered.first(where: { $0.mountURL.path == "/System/Volumes/Data" }) { return data }
        if let startup = ordered.first(where: { $0.mountURL.path == "/" }) { return startup }
        return ordered.first
    }
}
