import Foundation

struct FolderInventoryEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let isDirectory: Bool
    var logicalBytes: UInt64
    /// File allocation is optional, not a prediction of physically recoverable space.
    var allocatedBytes: UInt64?
    var fileCount: Int
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct FolderInventory: Equatable, Sendable {
    static let fileLimit = 100
    static let directoryLimit = 256
    let root: URL
    var largestFiles: [FolderInventoryEntry] = []
    var directories: [FolderInventoryEntry] = []
    var observedFileCount = 0
    var omittedDirectoryCount = 0

    enum Filter: String, CaseIterable {
        case all = "All"
        case files = "Files"
        case folders = "Folders"
    }

    func rows(search: String = "", filter: Filter = .all) -> [FolderInventoryEntry] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let entries = (filter == .folders ? [] : largestFiles) + (filter == .files ? [] : directories)
        return entries.filter { entry in
            words.allSatisfy { entry.url.path.localizedCaseInsensitiveContains($0) }
        }.sorted(by: Self.precedes)
    }

    static func precedes(_ left: FolderInventoryEntry, _ right: FolderInventoryEntry) -> Bool {
        left.logicalBytes == right.logicalBytes ? left.id < right.id : left.logicalBytes > right.logicalBytes
    }

    func contains(_ entry: FolderInventoryEntry) -> Bool {
        largestFiles.contains(entry) || directories.contains(entry)
    }
}

/// One synchronous worker owns this bounded accumulator. It never retains every
/// file/path. Global top files are exact among successfully measured observations;
/// child-directory summaries cover only the first 256 discovered children.
struct FolderInventoryAccumulator {
    let root: URL
    private var files: [FolderInventoryEntry] = []
    private var directories: [String: FolderInventoryEntry] = [:]
    private var observedFileCount = 0
    private var omittedDirectoryCount = 0

    init(root: URL) { self.root = root.standardizedFileURL }

    mutating func record(url: URL, isDirectory: Bool, logicalBytes: UInt64, allocatedBytes: UInt64?) {
        let url = url.standardizedFileURL
        let path = url.path
        guard path.hasPrefix(root.path + "/") else { return }
        let relative = String(path.dropFirst(root.path.count + 1))
        guard let first = relative.split(separator: "/").first else { return }
        let child = root.appendingPathComponent(String(first), isDirectory: true)
        if isDirectory {
            // Descendants don't create new summaries. Each immediate directory
            // is observed once by the enumerator, so omission counts need no set.
            guard path == child.path else { return }
            guard directories.count < FolderInventory.directoryLimit else {
                omittedDirectoryCount += 1
                return
            }
            directories[path] = FolderInventoryEntry(
                url: url, isDirectory: true, logicalBytes: 0,
                allocatedBytes: nil, fileCount: 0)
            return
        }
        observedFileCount += 1
        let entry = FolderInventoryEntry(
            url: url, isDirectory: false, logicalBytes: logicalBytes,
            allocatedBytes: allocatedBytes, fileCount: 1)
        if files.count < FolderInventory.fileLimit || files.last.map({ FolderInventory.precedes(entry, $0) }) == true {
            files.append(entry)
            files.sort(by: FolderInventory.precedes)
            if files.count > FolderInventory.fileLimit { files.removeLast() }
        }
        if var directory = directories[child.path] {
            let sum = directory.logicalBytes.addingReportingOverflow(logicalBytes)
            directory.logicalBytes = sum.overflow ? UInt64.max : sum.partialValue
            directory.fileCount += 1
            directories[child.path] = directory
        }
    }

    var snapshot: FolderInventory {
        FolderInventory(
            root: root, largestFiles: files,
            directories: directories.values.sorted(by: FolderInventory.precedes),
            observedFileCount: observedFileCount, omittedDirectoryCount: omittedDirectoryCount)
    }
}

/// Folder-scoped file actions revalidate both lexical and resolved containment.
/// Not an atomic handle-based snapshot: mutation between validation and use is
/// still possible. No symlink target or path outside the current scope is allowed.
enum FolderInventoryAccess {
    static func validatedURL(for entry: FolderInventoryEntry, in inventory: FolderInventory) -> URL? {
        guard inventory.contains(entry), DiskScanScope.acceptsFolderURL(inventory.root) else { return nil }
        let root = inventory.root.standardizedFileURL
        let url = entry.url.standardizedFileURL
        guard DiskScanScope.acceptsFolderURL(entry.url), entry.url.path == url.path,
            url.path.hasPrefix(root.path + "/"),
            root.resolvingSymlinksInPath().standardizedFileURL.path == root.path,
            url.resolvingSymlinksInPath().standardizedFileURL.path == url.path,
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]),
            values.isSymbolicLink != true,
            entry.isDirectory ? values.isDirectory == true : values.isRegularFile == true
        else { return nil }
        return url
    }
}
