import AppKit
import Foundation

/// Resolves bundle metadata (name, identifier, icon, launch date) for running processes.
enum ProcessMetadataProvider {

    struct BundleInfo {
        let bundlePath: String?
        let bundleIdentifier: String?
        let displayName: String?
    }

    /// Walks up from an executable path to find the enclosing `.app` bundle, if any.
    static func bundleInfo(for executablePath: String) -> BundleInfo {
        let nsPath = executablePath as NSString
        var components = nsPath.pathComponents

        while !components.isEmpty {
            let joined = NSString.path(withComponents: components)
            if joined.hasSuffix(".app") {
                let bundle = Bundle(path: joined)
                let name = bundle?.infoDictionary?["CFBundleName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? (joined as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                return BundleInfo(
                    bundlePath: joined,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    displayName: name
                )
            }
            components.removeLast()
        }
        return BundleInfo(bundlePath: nil, bundleIdentifier: nil, displayName: nil)
    }

    /// Returns the best icon for a given cache key (bundle path preferred, else executable path).
    static func icon(forKey key: String) -> NSImage? {
        if let cached = IconCache.shared.get(key) {
            return cached
        }

        let icon: NSImage
        if key.hasSuffix(".app"), FileManager.default.fileExists(atPath: key) {
            icon = NSWorkspace.shared.icon(forFile: key)
        } else if FileManager.default.fileExists(atPath: key) {
            icon = NSWorkspace.shared.icon(forFile: key)
        } else {
            icon = NSWorkspace.shared.icon(for: .unixExecutable)
        }
        icon.size = NSSize(width: 32, height: 32)
        IconCache.shared.set(icon, for: key)
        return icon
    }

    /// Returns the process start date via BSD process info.
    static func startDate(for pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return nil }

        let ts = info.kp_proc.p_un.__p_starttime
        let interval = TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_usec) / 1_000_000
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }
}
