import AppKit
import Foundation

/// Scans well-known cache / support directories and produces categorized,
/// progressively-reported disk usage — so the UI can update as data comes in
/// instead of blocking on one giant synchronous walk.
enum DiskScanner {

    struct ScanUpdate: Sendable {
        let currentPath: String
        let categories: [DiskCategory]
        let progress: Double
        let isComplete: Bool
        var isCancelled = false
        var skippedLocationCount = 0
        var inventory: FolderInventory? = nil
    }

    private struct Spec {
        let categoryId: String
        let categoryName: String
        let categoryIcon: String
        let path: String
        let displayName: String
        let safe: Bool
        let note: String
    }

    /// Runs the scan synchronously on the calling thread (call from a background task),
    /// invoking `onUpdate` after each item is measured so the UI can render incrementally.
    static func scan(
        home homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        isCancelled: @escaping () -> Bool = { Task.isCancelled },
        onUpdate: @escaping @Sendable (ScanUpdate) -> Void
    ) {
        let home = homeURL.path
        let fm = FileManager.default
        var skippedLocationCount = 0

        let devNote = "Regenerated automatically by developer tools on next build/run."
        let appNote =
            "Application data may include documents, databases, and settings. Review in Finder; cleanup is disabled."
        let sysNote = "Safe to clear; macOS and apps will recreate what they still need."
        let containerNote = "Container/image data. Only delete if you know you don't need it."

        var specs: [Spec] = [
            // Development
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Developer/Xcode/DerivedData", displayName: "Xcode DerivedData",
                safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Developer/Xcode/Archives", displayName: "Xcode Archives",
                safe: false, note: "Contains archived app builds you may still need for distribution."),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", displayName: "iOS DeviceSupport",
                safe: true, note: "Symbol files for connected devices. Regenerated when you plug devices in."),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Developer/CoreSimulator/Caches", displayName: "Simulator Caches",
                safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Developer/CoreSimulator/Devices", displayName: "Simulator Devices",
                safe: false, note: "All simulator runtimes and app data. Deleting wipes simulators."),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/org.swift.swiftpm", displayName: "Swift Package Manager",
                safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/.npm/_cacache", displayName: "npm Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/Yarn", displayName: "Yarn Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/pnpm", displayName: "pnpm Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/.cache/deno", displayName: "Deno Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/.gradle/caches", displayName: "Gradle Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/.cargo/registry", displayName: "Cargo Registry", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/pip", displayName: "pip Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/CocoaPods", displayName: "CocoaPods Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/Homebrew", displayName: "Homebrew Cache", safe: true, note: devNote),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/Library/Caches/com.apple.dt.Xcode", displayName: "Xcode Cache", safe: true, note: devNote
            ),
            Spec(
                categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                path: "\(home)/.bun/install/cache", displayName: "Bun Cache", safe: true, note: devNote),

            // Containers / VMs
            Spec(
                categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                path: "\(home)/Library/Containers/com.docker.docker", displayName: "Docker Desktop",
                safe: false, note: containerNote),
            Spec(
                categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                path: "\(home)/.docker", displayName: "Docker Data",
                safe: false, note: containerNote),
            Spec(
                categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                path: "\(home)/.local/share/containers", displayName: "Podman/Containers",
                safe: false, note: containerNote),
            Spec(
                categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                path: "\(home)/Library/Application Support/OrbStack", displayName: "OrbStack",
                safe: false, note: containerNote),

            // System
            Spec(
                categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                path: "\(home)/Library/Logs", displayName: "User Logs", safe: true, note: sysNote),
            Spec(
                categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                path: "\(home)/Library/Saved Application State", displayName: "Saved App States",
                safe: false, note: "May contain unsaved window/document restoration data. Review in Finder."),
            Spec(
                categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                path: "\(home)/Library/Caches/CloudKit", displayName: "CloudKit Cache", safe: true, note: sysNote),
            Spec(
                categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                path: "\(home)/Library/Caches/com.apple.python", displayName: "Python System Cache", safe: true,
                note: sysNote),
            Spec(
                categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                path: "\(home)/.Trash", displayName: "Trash",
                safe: false,
                note: "Already in Trash. Review or empty using Finder; this app never permanently deletes files."),
        ]

        // Applications: every subfolder under ~/Library/Application Support and
        // ~/Library/Caches that isn't already claimed.
        let claimed = Set(specs.map { $0.path })
        for base in ["\(home)/Library/Application Support", "\(home)/Library/Caches"] {
            guard !isCancelled() else { break }
            let baseURL = URL(fileURLWithPath: base)
            // Validate discovery roots too; do not list a substituted ancestor.
            guard isUnredirectedDirectory(baseURL, home: homeURL) else {
                if !isMissingLocation(baseURL) { skippedLocationCount += 1 }
                continue
            }
            do {
                let entries = try fm.contentsOfDirectory(atPath: base)
                for entry in entries.sorted() {
                    guard !isCancelled() else { break }
                    if entry.hasPrefix(".") { continue }
                    let full = "\(base)/\(entry)"
                    if claimed.contains(full) { continue }
                    if entry.hasPrefix("com.apple.") || entry == "CloudKit" { continue }
                    // Skip huge/system-ish folders we already cover elsewhere
                    if entry == "MobileSync" || entry == "CallHistoryDB" { continue }
                    specs.append(
                        Spec(
                            categoryId: "applications", categoryName: "Applications", categoryIcon: "app.badge.fill",
                            path: full, displayName: prettyAppName(entry),
                            safe: base.hasSuffix("/Caches"),
                            note: base.hasSuffix("/Caches")
                                ? "Cache data. Quit the owning app before clearing; it may be rebuilt." : appNote
                        ))
                }
            } catch {
                skippedLocationCount += 1
            }
        }

        var categories: [String: DiskCategory] = [:]
        let order: [(String, String, String)] = [
            ("applications", "Applications", "app.badge.fill"),
            ("development", "Development", "hammer.fill"),
            ("containers", "Containers", "shippingbox.fill"),
            ("system", "System", "gearshape.fill"),
        ]
        for (id, name, icon) in order {
            categories[id] = DiskCategory(id: id, name: name, icon: icon, bytes: 0, items: [])
        }

        let totalSpecs = max(specs.count, 1)

        for (index, spec) in specs.enumerated() {
            guard !isCancelled() else { break }
            let progress = Double(index) / Double(totalSpecs)
            onUpdate(
                ScanUpdate(
                    currentPath: spec.path,
                    categories: sortedCategories(categories),
                    progress: progress,
                    isComplete: false
                ))

            // Never follow a symlink substituted for a scan root/ancestor.
            guard isUnredirectedDirectory(URL(fileURLWithPath: spec.path), home: homeURL) else {
                // Absent optional tools are expected, not failed measurements.
                if !isMissingLocation(URL(fileURLWithPath: spec.path)) { skippedLocationCount += 1 }
                continue
            }
            let measurement = directorySize(at: spec.path, isCancelled: isCancelled) { currentFile in
                onUpdate(
                    ScanUpdate(
                        currentPath: currentFile,
                        categories: sortedCategories(categories),
                        progress: progress,
                        isComplete: false
                    ))
            }
            skippedLocationCount += measurement.skippedLocationCount
            guard !measurement.isCancelled, !isCancelled() else { break }
            let bytes = measurement.bytes
            let fileCount = measurement.fileCount
            guard bytes > 4096 else { continue }

            let item = DiskItem(
                id: spec.path,
                name: spec.displayName,
                path: spec.path,
                bytes: bytes,
                fileCount: fileCount,
                isDirectory: true,
                categoryName: spec.categoryName,
                safeToDelete: spec.safe,
                safetyNote: spec.note
            )

            var cat =
                categories[spec.categoryId]
                ?? DiskCategory(
                    id: spec.categoryId,
                    name: spec.categoryName,
                    icon: spec.categoryIcon,
                    bytes: 0,
                    items: []
                )
            cat.items.append(item)
            cat.bytes += bytes
            categories[spec.categoryId] = cat

            onUpdate(
                ScanUpdate(
                    currentPath: spec.path,
                    categories: sortedCategories(categories),
                    progress: Double(index + 1) / Double(totalSpecs),
                    isComplete: false
                ))
        }

        let cancelled = isCancelled()
        onUpdate(
            ScanUpdate(
                currentPath: "",
                categories: sortedCategories(categories),
                progress: cancelled ? 0 : 1,
                isComplete: true,
                isCancelled: cancelled,
                skippedLocationCount: skippedLocationCount
            ))
    }

    /// Explicitly selected folder inventory, never a cleanup authorization.
    /// Root/ancestor symlinks are rejected; Foundation does not descend into
    /// child symlinks. Revalidate containment of every visited entry as well.
    static func scanFolder(
        at root: URL, isCancelled: @escaping () -> Bool = { Task.isCancelled },
        onUpdate: @escaping @Sendable (ScanUpdate) -> Void
    ) {
        guard !isCancelled() else {
            onUpdate(.init(currentPath: "", categories: [], progress: 0, isComplete: true, isCancelled: true))
            return
        }
        guard DiskScanScope.acceptsFolderURL(root),
            root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path,
            let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true, values.isSymbolicLink != true
        else {
            onUpdate(.init(currentPath: "", categories: [], progress: 1, isComplete: true, skippedLocationCount: 1))
            return
        }
        let root = root.standardizedFileURL
        let makeCategories: @Sendable (UInt64, Int) -> [DiskCategory] = { bytes, count in
            let item = DiskItem(
                id: root.path, name: root.lastPathComponent, path: root.path, bytes: bytes, fileCount: count,
                isDirectory: true, categoryName: "Selected folder", safeToDelete: false,
                safetyNote:
                    "Read-only folder inventory. Logical sizes include hidden and package files; incomplete scans show only observed data. APFS clones, sparse files and hard links are not physical space-recovery estimates."
            )
            return [
                DiskCategory(
                    id: "selected-folder", name: "Selected folder", icon: "folder", bytes: bytes, items: [item])
            ]
        }
        onUpdate(.init(currentPath: root.path, categories: [], progress: 0, isComplete: false))
        var inventory = FolderInventoryAccumulator(root: root)
        let result = directorySize(
            at: root.path, isCancelled: isCancelled, expectedRoot: root,
            onEntry: { url, directory, bytes, allocation in
                inventory.record(url: url, isDirectory: directory, logicalBytes: bytes, allocatedBytes: allocation)
            },
            onProgress: { bytes, count in
                onUpdate(
                    .init(
                        currentPath: root.path, categories: makeCategories(bytes, count), progress: 0,
                        isComplete: false,
                        inventory: inventory.snapshot
                    ))
            }, onFile: { _ in })
        // A root can disappear after validation but before enumeration. No
        // successful files plus an error/cancellation is unknown, not empty.
        let measured = result.fileCount > 0 || (!result.isCancelled && result.skippedLocationCount == 0)
        onUpdate(
            .init(
                currentPath: "", categories: measured ? makeCategories(result.bytes, result.fileCount) : [],
                progress: result.isCancelled ? 0 : 1, isComplete: true, isCancelled: result.isCancelled,
                skippedLocationCount: result.skippedLocationCount, inventory: measured ? inventory.snapshot : nil))
    }

    private static func sortedCategories(_ categories: [String: DiskCategory]) -> [DiskCategory] {
        categories.values
            .filter { !$0.items.isEmpty }
            .map { cat -> DiskCategory in
                var c = cat
                c.items.sort { $0.bytes > $1.bytes }
                return c
            }
            .sorted { $0.bytes > $1.bytes }
    }

    private static func prettyAppName(_ entry: String) -> String {
        // com.foo.Bar → Bar, leave human names alone
        if entry.contains("."), let last = entry.split(separator: ".").last {
            return String(last)
        }
        return entry
    }

    /// Recursively sums file sizes under `path`, periodically reporting the current file.
    static func directorySize(
        at path: String, isCancelled: @escaping () -> Bool = { Task.isCancelled },
        expectedRoot: URL? = nil,
        onEntry: (URL, Bool, UInt64, UInt64?) -> Void = { _, _, _, _ in },
        onProgress: (UInt64, Int) -> Void = { _, _ in }, onFile: (String) -> Void
    ) -> (bytes: UInt64, fileCount: Int, skippedLocationCount: Int, isCancelled: Bool) {
        guard !isCancelled() else { return (0, 0, 0, true) }
        let fm = FileManager.default
        let resolvedRoot = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        guard expectedRoot == nil || expectedRoot?.standardizedFileURL.path == resolvedRoot else {
            return (0, 0, 1, isCancelled())
        }
        let canonicalRoot = expectedRoot?.standardizedFileURL.path ?? resolvedRoot
        var skippedLocationCount = 0
        guard
            let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [
                    .fileSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
                ],
                options: [],
                errorHandler: { _, _ in
                    skippedLocationCount += 1
                    return !isCancelled()
                }
            )
        else { return (0, 0, 1, isCancelled()) }

        var total: UInt64 = 0
        var fileCount = 0
        var counter = 0
        var lastProgressUptime: TimeInterval?
        for case let fileURL as URL in enumerator {
            guard !isCancelled() else { return (total, fileCount, skippedLocationCount, true) }
            counter += 1
            if counter % 80 == 0 {
                let uptime = ProcessInfo.processInfo.systemUptime
                if lastProgressUptime.map({ uptime - $0 >= 0.2 }) ?? true {
                    onProgress(total, fileCount)
                    onFile(fileURL.path)
                    lastProgressUptime = uptime
                }
            }
            guard !isCancelled() else { return (total, fileCount, skippedLocationCount, true) }
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
                ])
                // Foundation does not descend into symlinks. Calling
                // skipDescendants on a link leaf can suppress unrelated siblings.
                if values.isSymbolicLink == true { continue }
                let resolved = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                guard resolved.hasPrefix(canonicalRoot + "/") else {
                    skippedLocationCount += 1
                    if values.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                if values.isDirectory == true {
                    onEntry(fileURL, true, 0, nil)
                    continue
                }
                guard values.isRegularFile == true else { continue }
                guard let size = values.fileSize, size >= 0 else {
                    skippedLocationCount += 1
                    continue
                }
                let sum = total.addingReportingOverflow(UInt64(size))
                guard !sum.overflow else {
                    skippedLocationCount += 1
                    continue
                }
                total = sum.partialValue
                fileCount += 1
                let allocated =
                    expectedRoot == nil
                    ? nil : (try? fileURL.resourceValues(forKeys: [.fileAllocatedSizeKey]))?.fileAllocatedSize
                onEntry(fileURL, false, UInt64(size), allocated.flatMap { $0 >= 0 ? UInt64($0) : nil })
            } catch {
                skippedLocationCount += 1
            }
        }
        return (total, fileCount, skippedLocationCount, isCancelled())
    }

    // MARK: - Actions

    @MainActor
    static func reveal(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    /// Only measured cache roots are eligible. Safety labels alone are not
    /// authorization: forged paths, ancestors, support data, and links fail closed.
    static func canDelete(_ item: DiskItem, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        guard item.safeToDelete, item.isDirectory, item.id == item.path,
            item.path.hasPrefix("/"), !item.path.contains("\0")
        else { return false }
        let url = URL(fileURLWithPath: item.path)
        let normalized = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard normalized == item.path, normalized.hasPrefix(homePath + "/") else { return false }
        let relative = String(normalized.dropFirst(homePath.count + 1))
        let knownCaches: Set<String> = [
            "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Developer/CoreSimulator/Caches", ".npm/_cacache", ".cache/deno",
            ".gradle/caches", ".cargo/registry", ".bun/install/cache", "Library/Logs",
        ]
        let parts = relative.split(separator: "/")
        let cacheChild =
            parts.count == 3 && parts[0] == "Library" && parts[1] == "Caches"
            && !parts[2].hasPrefix(".")
        guard knownCaches.contains(relative) || cacheChild else { return false }
        return isUnredirectedDirectory(url, home: home)
    }

    private static func isMissingLocation(_ url: URL) -> Bool {
        do {
            _ = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return false
        } catch {
            let error = error as NSError
            return error.domain == NSCocoaErrorDomain
                && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code)
        }
    }

    private static func isUnredirectedDirectory(_ url: URL, home: URL) -> Bool {
        let homePath = home.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return false }
        let relative = String(path.dropFirst(homePath.count + 1))
        let expected = home.resolvingSymlinksInPath().appendingPathComponent(relative).standardizedFileURL
        guard url.resolvingSymlinksInPath().standardizedFileURL == expected,
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
            values.isDirectory == true, values.isSymbolicLink != true
        else { return false }
        // Also reject links to another location *inside* the home directory.
        var ancestor = url.standardizedFileURL
        while ancestor.path != homePath {
            guard let values = try? ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]),
                values.isSymbolicLink != true
            else { return false }
            ancestor.deleteLastPathComponent()
        }
        return true
    }

    static func moveToTrash(
        item: DiskItem, home: URL = FileManager.default.homeDirectoryForCurrentUser,
        trash: (URL) throws -> Void = { url in
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        }
    ) -> CleanupItemResult.Outcome {
        guard canDelete(item, home: home) else {
            return .failed("Location is missing, redirected or not an eligible cache root")
        }
        do {
            try trash(URL(fileURLWithPath: item.path))
            return .movedToTrash
        } catch {
            // Avoid raw Foundation descriptions (user paths) in a retained
            // result. These messages don't infer permission or success.
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                return .failed("macOS refused access; no elevation was attempted")
            }
            if error.domain == NSCocoaErrorDomain
                && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
            {
                return .failed("Location disappeared before it could be moved")
            }
            return .failed("macOS could not move this location to Trash")
        }
    }

    static func delete(
        item: DiskItem, home: URL = FileManager.default.homeDirectoryForCurrentUser,
        trash: (URL) throws -> Void = { url in
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        }
    ) -> Bool {
        guard canDelete(item, home: home) else { return false }
        do {
            try trash(URL(fileURLWithPath: item.path))
            return true
        } catch {
            return false
        }
    }
}
