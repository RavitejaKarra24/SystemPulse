import Foundation

/// Scope is session-only. Monitoring-volume selection and diagnostic export
/// never control or serialize it; arbitrary folders never authorize cleanup.
enum DiskScanScope: Equatable, Sendable {
    case cleanupLocations
    case folder(URL)

    var isReadOnly: Bool {
        if case .folder = self { return true }
        return false
    }

    var folderURL: URL? {
        if case .folder(let url) = self { return url }
        return nil
    }

    static func acceptsFolderURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return url.isFileURL && (host.isEmpty || host == "localhost") && url.path.hasPrefix("/")
            && url.standardizedFileURL.path != "/" && !url.path.contains("\0")
    }
}
