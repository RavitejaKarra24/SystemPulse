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
    static func scan(onUpdate: @escaping @Sendable (ScanUpdate) -> Void) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        let devNote = "Regenerated automatically by developer tools on next build/run."
        let appNote = "Cache and support data — most apps rebuild this automatically."
        let sysNote = "Safe to clear; macOS and apps will recreate what they still need."
        let containerNote = "Container/image data. Only delete if you know you don't need it."

        var specs: [Spec] = [
            // Development
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Developer/Xcode/DerivedData", displayName: "Xcode DerivedData",
                 safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Developer/Xcode/Archives", displayName: "Xcode Archives",
                 safe: false, note: "Contains archived app builds you may still need for distribution."),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Developer/Xcode/iOS DeviceSupport", displayName: "iOS DeviceSupport",
                 safe: true, note: "Symbol files for connected devices. Regenerated when you plug devices in."),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Developer/CoreSimulator/Caches", displayName: "Simulator Caches",
                 safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Developer/CoreSimulator/Devices", displayName: "Simulator Devices",
                 safe: false, note: "All simulator runtimes and app data. Deleting wipes simulators."),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/org.swift.swiftpm", displayName: "Swift Package Manager",
                 safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/.npm", displayName: "npm Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/Yarn", displayName: "Yarn Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/pnpm", displayName: "pnpm Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/.cache/deno", displayName: "Deno Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/.gradle/caches", displayName: "Gradle Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/.cargo/registry", displayName: "Cargo Registry", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/pip", displayName: "pip Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/CocoaPods", displayName: "CocoaPods Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/Homebrew", displayName: "Homebrew Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/Library/Caches/com.apple.dt.Xcode", displayName: "Xcode Cache", safe: true, note: devNote),
            Spec(categoryId: "development", categoryName: "Development", categoryIcon: "hammer.fill",
                 path: "\(home)/.bun/install/cache", displayName: "Bun Cache", safe: true, note: devNote),

            // Containers / VMs
            Spec(categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                 path: "\(home)/Library/Containers/com.docker.docker", displayName: "Docker Desktop",
                 safe: false, note: containerNote),
            Spec(categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                 path: "\(home)/.docker", displayName: "Docker Data",
                 safe: false, note: containerNote),
            Spec(categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                 path: "\(home)/.local/share/containers", displayName: "Podman/Containers",
                 safe: false, note: containerNote),
            Spec(categoryId: "containers", categoryName: "Containers", categoryIcon: "shippingbox.fill",
                 path: "\(home)/Library/Application Support/OrbStack", displayName: "OrbStack",
                 safe: false, note: containerNote),

            // System
            Spec(categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                 path: "\(home)/Library/Logs", displayName: "User Logs", safe: true, note: sysNote),
            Spec(categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                 path: "\(home)/Library/Saved Application State", displayName: "Saved App States",
                 safe: true, note: sysNote),
            Spec(categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                 path: "\(home)/Library/Caches/CloudKit", displayName: "CloudKit Cache", safe: true, note: sysNote),
            Spec(categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                 path: "\(home)/Library/Caches/com.apple.python", displayName: "Python System Cache", safe: true, note: sysNote),
            Spec(categoryId: "system", categoryName: "System", categoryIcon: "gearshape.fill",
                 path: "\(home)/.Trash", displayName: "Trash",
                 safe: true, note: "Items already in the Trash. Emptying frees space permanently."),
        ]

        // Applications: every subfolder under ~/Library/Application Support and
        // ~/Library/Caches that isn't already claimed.
        let claimed = Set(specs.map { $0.path })
        for base in ["\(home)/Library/Application Support", "\(home)/Library/Caches"] {
            if let entries = try? fm.contentsOfDirectory(atPath: base) {
                for entry in entries.sorted() {
                    if entry.hasPrefix(".") { continue }
                    let full = "\(base)/\(entry)"
                    if claimed.contains(full) { continue }
                    if entry.hasPrefix("com.apple.") || entry == "CloudKit" { continue }
                    // Skip huge/system-ish folders we already cover elsewhere
                    if entry == "MobileSync" || entry == "CallHistoryDB" { continue }
                    specs.append(Spec(
                        categoryId: "applications", categoryName: "Applications", categoryIcon: "app.badge.fill",
                        path: full, displayName: prettyAppName(entry), safe: true, note: appNote
                    ))
                }
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
            let progress = Double(index) / Double(totalSpecs)
            onUpdate(ScanUpdate(
                currentPath: spec.path,
                categories: sortedCategories(categories),
                progress: progress,
                isComplete: false
            ))

            guard fm.fileExists(atPath: spec.path) else { continue }
            let (bytes, fileCount) = directorySize(at: spec.path) { currentFile in
                onUpdate(ScanUpdate(
                    currentPath: currentFile,
                    categories: sortedCategories(categories),
                    progress: progress,
                    isComplete: false
                ))
            }
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

            var cat = categories[spec.categoryId] ?? DiskCategory(
                id: spec.categoryId,
                name: spec.categoryName,
                icon: spec.categoryIcon,
                bytes: 0,
                items: []
            )
            cat.items.append(item)
            cat.bytes += bytes
            categories[spec.categoryId] = cat

            onUpdate(ScanUpdate(
                currentPath: spec.path,
                categories: sortedCategories(categories),
                progress: Double(index + 1) / Double(totalSpecs),
                isComplete: false
            ))
        }

        onUpdate(ScanUpdate(
            currentPath: "",
            categories: sortedCategories(categories),
            progress: 1,
            isComplete: true
        ))
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
    private static func directorySize(at path: String, onFile: (String) -> Void) -> (bytes: UInt64, fileCount: Int) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return (0, 0) }

        var total: UInt64 = 0
        var fileCount = 0
        var counter = 0
        for case let fileURL as URL in enumerator {
            counter += 1
            if counter % 80 == 0 {
                onFile(fileURL.path)
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += UInt64(size)
            fileCount += 1
        }
        return (total, fileCount)
    }

    // MARK: - Actions

    @MainActor
    static func reveal(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    static func delete(path: String) -> Bool {
        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &trashedURL)
            return true
        } catch {
            return false
        }
    }
}
