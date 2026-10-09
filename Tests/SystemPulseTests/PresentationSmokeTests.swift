import AppKit
import SwiftUI
import XCTest

@testable import SystemPulse

final class PresentationSmokeTests: XCTestCase {
    /// Exercises every topic in both appearances without starting timers or touching real processes/files.
    @MainActor
    func testEveryTopicRendersInBothAppearances() async throws {
        let store = fixtureStore()
        let screenshotDirectory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"]
        for scheme in [ColorScheme.light, .dark] {
            for tab in MetricTab.allCases {
                let view = MainView(
                    store: store, tab: .constant(tab), searchFocusToken: .constant(false),
                    onSelectProcess: { _ in }, onSelectDiskItem: { _ in }
                )
                .frame(width: Theme.popoverWidth, height: 720, alignment: .top)
                .background(AppBackground())
                .environment(\.colorScheme, scheme)
                let image = try render(view, scheme: scheme)
                XCTAssertEqual(image.size.width, Theme.popoverWidth)
                XCTAssertEqual(image.size.height, 720)
                if let screenshotDirectory {
                    try savePreview(
                        image, directory: screenshotDirectory, name: "\(tab.rawValue.lowercased())-\(scheme)")
                }
            }
        }
    }

    @MainActor
    func testSelectedInterfaceAndUnavailableVolumeRenderInBothAppearances() async throws {
        let store = fixtureStore()
        store.selectedNetworkInterfaceID = "en0"
        store.selectedDownloadTimeline = store.downloadTimeline
        store.selectedUploadTimeline = store.uploadTimeline
        store.applyVolumes(
            store.volumes + [
                MonitoredVolume(
                    id: "fixture-unavailable", name: "External Drive",
                    mountURL: URL(fileURLWithPath: "/Volumes/Fixture"),
                    isInternal: false, isReadOnly: true, totalBytes: nil, availableBytes: nil)
            ])
        store.selectedVolumeID = "fixture-unavailable"
        for scheme in [ColorScheme.light, .dark] {
            for tab in [MetricTab.network, .disk] {
                let view = MainView(
                    store: store, tab: .constant(tab), searchFocusToken: .constant(false),
                    onSelectProcess: { _ in }, onSelectDiskItem: { _ in }
                )
                .frame(width: Theme.popoverWidth, height: 720, alignment: .top)
                .background(AppBackground())
                .environment(\.colorScheme, scheme)
                let image = try render(view, scheme: scheme)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    try savePreview(
                        image, directory: directory, name: "\(tab.rawValue.lowercased())-selected-\(scheme)")
                }
            }
        }
    }

    @MainActor
    func testInsightsAndReducedModulesRenderInBothAppearances() async throws {
        let name = "SystemPulse.Presentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let store = fixtureStore()
        let now = Date()
        let memory = MemoryBreakdown(
            app: 10 << 30, wired: 3 << 30, compressed: 2 << 30, cached: 512 << 20,
            free: 512 << 20, total: 16 << 30, swapUsed: 1 << 30)
        store.applySample(
            cpu: .init(perCore: [95, 95]), memory: memory,
            io: DiskIOSnapshot(timestamp: now), power: store.power,
            net: NetworkSnapshot(timestamp: now),
            disk: .init(total: 500 << 30, used: 498 << 30, free: 2 << 30), info: store.systemInfo, thermal: .serious)
        store.cpuTimeline = MetricHistory()
        for index in 0...20 {
            store.cpuTimeline.record(95, at: now.addingTimeInterval(Double(index - 20) * 3))
        }
        XCTAssertEqual(store.monitoringInsights(at: now).count, 4)
        for reduced in [false, true] {
            preferences.visibleModules = reduced ? [.cpu, .memory] : [.cpu, .memory, .network, .disk, .power]
            for scheme in [ColorScheme.light, .dark] {
                let view = MainView(
                    store: store, preferences: preferences, tab: .constant(.overview),
                    searchFocusToken: .constant(false),
                    onSelectProcess: { _ in }, onSelectDiskItem: { _ in }, onOpenSettings: {}
                )
                .frame(width: Theme.popoverWidth, height: 720, alignment: .top)
                .background(AppBackground())
                .environment(\.colorScheme, scheme)
                let image = try render(view, scheme: scheme)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    try savePreview(
                        image, directory: directory, name: "overview-\(reduced ? "reduced" : "insights")-\(scheme)")
                }
            }
        }
    }

    @MainActor
    func testPartialAndStoppedStorageScansRenderInBothAppearances() async throws {
        let fixture = try SettingsPreferencesFixture()
        let item = DiskItem(
            id: "/fixture/cache", name: "Fixture Cache", path: "/fixture/cache",
            bytes: 8192, fileCount: 1, isDirectory: true, categoryName: "Development", safeToDelete: true,
            safetyNote: "Fixture data only")
        let category = DiskCategory(
            id: "development", name: "Development", icon: "hammer.fill", bytes: 8192, items: [item])
        for cancelled in [false, true] {
            let store = MonitorStore(
                startPolling: false, preferences: fixture.makePreferences(),
                scanRunner: { update in
                    update(
                        .init(
                            currentPath: "", categories: [category], progress: cancelled ? 0.5 : 1,
                            isComplete: true, isCancelled: cancelled, skippedLocationCount: cancelled ? 0 : 2))
                })
            store.scanDisk()
            await store.waitForDiskScan()
            XCTAssertTrue(store.scanResultsArePartial)
            for scheme in [ColorScheme.light, .dark] {
                let view = VStack(spacing: 16) {
                    ScanStatusBar(store: store)
                    DiskCategoryListCard(store: store, onSelectItem: { _ in })
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(width: Theme.popoverWidth, height: 360, alignment: .top)
                .background(AppBackground())
                .environment(\.colorScheme, scheme)
                let image = try render(view, scheme: scheme, height: 360)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    try savePreview(
                        image, directory: directory, name: "disk-\(cancelled ? "stopped" : "partial")-\(scheme)")
                }
            }
        }
    }

    @MainActor
    func testSelectedFolderAndPendingChooserRenderInBothAppearances() async throws {
        let fixture = try SettingsPreferencesFixture()
        let selected = URL(fileURLWithPath: "/fixture/Selected Folder")
        let item = DiskItem(
            id: selected.path, name: "Selected Folder", path: selected.path, bytes: 8192, fileCount: 10,
            isDirectory: true, categoryName: "Selected folder", safeToDelete: false,
            safetyNote: "Read-only fixture inventory")
        let category = DiskCategory(
            id: "selected-folder", name: "Selected folder", icon: "folder", bytes: 8192, items: [item])
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            folderScanRunner: { _, update in
                update(.init(currentPath: "", categories: [category], progress: 1, isComplete: true))
            })
        XCTAssertTrue(store.scanFolder(selected))
        await store.waitForDiskScan()
        for choosing in [false, true] {
            let token = choosing ? store.beginFolderSelection() : nil
            for scheme in [ColorScheme.light, .dark] {
                let view = VStack(spacing: 16) {
                    ScanStatusBar(store: store)
                    DiskCategoryListCard(store: store, onSelectItem: { _ in })
                    Spacer(minLength: 0)
                }
                .padding(20)
                .frame(width: Theme.popoverWidth, height: 500, alignment: .top)
                .background(AppBackground())
                .environment(\.colorScheme, scheme)
                let image = try render(view, scheme: scheme, height: 500)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    try savePreview(
                        image, directory: directory, name: "folder-\(choosing ? "choosing" : "inventory")-\(scheme)")
                }
            }
            if let token { _ = store.completeFolderSelection(nil, revision: token) }
        }
    }

    @MainActor
    func testBoundedFolderExplorerRendersFilesFoldersAndPartialEvidence() async throws {
        let fixture = try SettingsPreferencesFixture()
        let root = URL(fileURLWithPath: "/fixture/Explorer")
        let files = (0..<100).map { index in
            FolderInventoryEntry(
                url: root.appendingPathComponent("file-\(index).txt"), isDirectory: false,
                logicalBytes: UInt64(100 - index) * 1024, allocatedBytes: index == 0 ? nil : 4096, fileCount: 1)
        }
        let directory = FolderInventoryEntry(
            url: root.appendingPathComponent("Subfolder"), isDirectory: true,
            logicalBytes: 24_000, allocatedBytes: nil, fileCount: 3)
        for partial in [false, true] {
            let inventory = FolderInventory(
                root: root, largestFiles: files, directories: [directory],
                observedFileCount: 150, omittedDirectoryCount: 4)
            let store = MonitorStore(
                startPolling: false, preferences: fixture.makePreferences(),
                folderScanRunner: { _, update in
                    update(
                        .init(
                            currentPath: "", categories: [], progress: 1, isComplete: true,
                            skippedLocationCount: partial ? 2 : 0, inventory: inventory))
                })
            XCTAssertTrue(store.scanFolder(root))
            await store.waitForDiskScan()
            for scheme in [ColorScheme.light, .dark] {
                let view = FolderInventoryCard(store: store)
                    .padding(20)
                    .frame(width: Theme.popoverWidth, height: 720, alignment: .top)
                    .background(AppBackground())
                    .environment(\.colorScheme, scheme)
                let image = try render(view, scheme: scheme)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    try savePreview(
                        image, directory: directory,
                        name: "folder-explorer-\(partial ? "partial" : "complete")-\(scheme)")
                }
            }
        }
    }

    @MainActor
    func testCleanupQueueReviewAndPartialResultsRenderWithoutRealTrash() async throws {
        let fixture = try SettingsPreferencesFixture()
        let entries = (0..<3).map { index in
            DiskItem(
                id: "/fixture/review/cache-\(index)", name: "Fixture Cache \(index)",
                path: "/fixture/review/cache-\(index)",
                bytes: UInt64(index + 1) * 8192, fileCount: 10, isDirectory: true, categoryName: "Development",
                safeToDelete: true, safetyNote: "Quit the owning app. This fixture contains no user data.")
        }
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            cleanupTrashClient: .init(move: { item in
                item.id == entries[1].id ? .failed("Injected refusal") : .movedToTrash
            }),
            cleanupEligibility: { _ in true })
        store.lastScanComplete = true
        store.diskCategories = [
            DiskCategory(
                id: "development", name: "Development", icon: "hammer", bytes: CleanupQueue.totalBytes(entries),
                items: entries)
        ]
        for entry in entries { XCTAssertTrue(store.queueCleanupItem(entry)) }
        let review = try XCTUnwrap(store.prepareCleanupReview())
        for completed in [false, true] {
            if completed {
                XCTAssertTrue(store.confirmCleanup(review))
                await store.waitForCleanup()
            }
            for scheme in [ColorScheme.light, .dark] {
                let queue = CleanupQueueCard(store: store)
                    .padding(20).frame(width: Theme.popoverWidth, height: 720, alignment: .top)
                    .background(AppBackground()).environment(\.colorScheme, scheme)
                let queueImage = try render(queue, scheme: scheme)
                let windowContent = CleanupReviewView(store: store, review: review, onClose: {})
                    .frame(width: 540, height: 740)
                    .background(AppBackground()).environment(\.colorScheme, scheme)
                let reviewImage = try render(windowContent, scheme: scheme, height: 740, width: 540)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    let stage = completed ? "results" : "review"
                    try savePreview(queueImage, directory: directory, name: "cleanup-queue-\(stage)-\(scheme)")
                    try savePreview(reviewImage, directory: directory, name: "cleanup-window-\(stage)-\(scheme)")
                }
            }
        }
        XCTAssertEqual(store.cleanupQueue.count, 1)
    }

    @MainActor
    func testHardwareSourcesAndLimitsRenderWithoutLiveProbes() throws {
        for scheme in [ColorScheme.light, .dark] {
            let view = GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "Sources and limits")
                    HardwareTelemetryNotesView()
                }
            }
            .padding(20).frame(width: Theme.popoverWidth, height: 900, alignment: .top)
            .background(AppBackground()).environment(\.colorScheme, scheme)
            let image = try render(view, scheme: scheme, height: 900)
            if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                try savePreview(image, directory: directory, name: "hardware-sources-\(scheme)")
            }
        }
    }

    @MainActor
    private func savePreview(_ image: NSImage, directory: String, name: String) throws {
        let directory = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func testEmptyOverviewRendersInShortPanel() async throws {
        let store = MonitorStore(startPolling: false)
        let view = RootView(store: store, preferences: .shared, panelHeight: 540)
        let image = try render(view, scheme: .light, height: 540)
        XCTAssertEqual(image.size.height, 540)
    }

    /// ImageRenderer skips AppKit-backed ScrollView/TextField content. Capture a real hosting view instead.
    @MainActor
    private func render<Content: View>(
        _ content: Content, scheme: ColorScheme, height: CGFloat = 720, width: CGFloat = Theme.popoverWidth
    ) throws -> NSImage {
        let hosting = NSHostingView(rootView: content)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(
            named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.frame = frame
        hosting.layoutSubtreeIfNeeded()
        // Allow the native scrolling hierarchy to perform its first layout pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        // Catch the blank-body snapshots ImageRenderer previously produced.
        let bodyColors = Set(
            stride(from: bitmap.pixelsHigh / 3, to: bitmap.pixelsHigh * 3 / 4, by: 12).flatMap { y in
                stride(from: 25, to: bitmap.pixelsWide - 25, by: 12).compactMap { x in
                    bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.description
                }
            })
        XCTAssertGreaterThan(bodyColors.count, 3, "Expected visible topic content, not just panel chrome")
        let image = NSImage(size: frame.size)
        image.addRepresentation(bitmap)
        window.close()
        return image
    }

    @MainActor
    private func fixtureStore() -> MonitorStore {
        let store = MonitorStore(startPolling: false)
        let wave = (0..<60).map { index in 22 + 12 * sin(Double(index) * 0.3) + Double(index % 7) }
        store.cpuUsage = wave.last ?? 0
        store.cpuPeak = 52
        store.cpuHistory = wave
        store.perCoreCPU = [22, 34, 14, 19, 42, 31, 20, 12]
        store.memoryBreakdown = MemoryBreakdown(
            app: 6 << 30, wired: 2 << 30, compressed: 1 << 30,
            cached: 3 << 30, free: 4 << 30, total: 16 << 30, swapUsed: 512 << 20)
        store.memoryHistory = wave.map { (8.6 + $0 / 100) * 1_073_741_824 }
        store.memoryHistory[store.memoryHistory.count - 1] = Double(store.memoryUsed)
        store.netInRate = 1_800_000
        store.netOutRate = 120_000
        store.netInHistory = wave.map { $0 * 50_000 }
        store.netOutHistory = wave.map { $0 * 3_000 }
        store.netInHistory[store.netInHistory.count - 1] = store.netInRate
        store.netOutHistory[store.netOutHistory.count - 1] = store.netOutRate
        store.netInPeak = 3_200_000
        store.netOutPeak = store.netOutHistory.max() ?? 0
        store.sessionBytesIn = 480 << 20
        store.sessionBytesOut = 32 << 20
        store.diskTotal = 500 << 30
        store.diskFree = 210 << 30
        store.diskUsed = 290 << 30
        store.diskUsage = 58
        store.diskReadHistory = wave.map { $0 * 80_000 }
        store.diskWriteHistory = wave.map { $0 * 10_000 }
        store.lastScanComplete = true
        store.power = PowerInfo(
            hasBattery: true, chargePercent: 78, hasChargeReading: true,
            lowPowerModeEnabled: false, isPluggedIn: false,
            timeRemaining: 14_400, cycleCount: 124, hasCycleCountReading: true, designCycleCount: 1000,
            healthPercent: 94, fullChargeCapacity: 4700, designCapacity: 5000,
            systemPowerWatts: 8.4)
        store.powerDrawHistory = wave.map { 6 + $0 / 10 }
        store.powerDrawHistory[store.powerDrawHistory.count - 1] = 8.4
        store.powerDrawPeak = store.powerDrawHistory.max() ?? 0
        let now = Date()
        for index in wave.indices {
            let timestamp = now.addingTimeInterval(Double(index - wave.count + 1) * 1.5)
            store.cpuTimeline.record(wave[index], at: timestamp)
            store.memoryTimeline.record(store.memoryHistory[index], at: timestamp)
            store.downloadTimeline.record(store.netInHistory[index], at: timestamp)
            store.uploadTimeline.record(store.netOutHistory[index], at: timestamp)
            store.diskReadTimeline.record(store.diskReadHistory[index], at: timestamp)
            store.diskWriteTimeline.record(store.diskWriteHistory[index], at: timestamp)
            store.powerDrawTimeline.record(
                store.powerDrawHistory[index], at: now.addingTimeInterval(Double(index - wave.count + 1) * 5))
        }
        store.networkInterfaces = [
            NetworkInterfaceReading(
                snapshot: NetworkInterfaceSnapshot(
                    name: "en0", displayName: "Wi-Fi", addresses: ["192.0.2.1"], isActive: true,
                    kind: .wifi, bytesIn: 600 << 20, bytesOut: 45 << 20),
                inRate: store.netInRate, outRate: store.netOutRate,
                sessionBytesIn: store.sessionBytesIn, sessionBytesOut: store.sessionBytesOut)
        ]
        store.applyVolumes([
            MonitoredVolume(
                id: "fixture-home", name: "Macintosh HD", mountURL: URL(fileURLWithPath: "/System/Volumes/Data"),
                isInternal: true, isReadOnly: false, totalBytes: store.diskTotal, availableBytes: store.diskFree,
                availableForImportantUsage: true, isHomeVolume: true)
        ])
        store.systemInfo = SystemInfo(
            loadAverage1: 1.24, loadAverage5: 1.12, loadAverage15: 1.02,
            processCount: 342, uptime: 183_600, coreCount: 8)
        store.topProcessName = "Safari"
        store.topProcessCPU = 12.4
        let process = ProcessStat(
            id: 45678, name: "Safari", executablePath: "/Applications/Safari.app/Contents/MacOS/Safari",
            bundlePath: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari",
            cpu: 12.4, memory: 450 << 20, threadCount: 12, iconKey: "fixture")
        store.processGroups = [
            ProcessGroup(
                id: "safari", name: "Safari", iconKey: nil,
                isSystemGroup: false, processes: [process])
        ]
        return store
    }
}
