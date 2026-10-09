import AppKit
import SwiftUI
import XCTest

@testable import SystemPulse

final class SettingsPresentationTests: XCTestCase {
    @MainActor
    func testEverySettingsPaneRendersInBothAppearancesWithoutPermissionOrLoginChanges() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let client = SettingsNotificationTestClient()
        let notifications = LocalNotificationService(client: client)
        // Resolve the injected status before off-screen capture; rendering is
        // not an async lifecycle test and must not freeze a pending mock query.
        await notifications.refreshAuthorization()
        // Restored enabled alerts must never trigger a permission request.
        preferences.alertsEnabled = true
        for appearance in [Preferences.Appearance.light, .dark] {
            preferences.appearance = appearance
            for pane in SettingsPane.allCases {
                let view = SettingsView(
                    preferences: preferences, notifications: notifications, initialPane: pane)
                let bitmap = try render(view, appearance: appearance)
                XCTAssertGreaterThan(bitmap.pixelsWide, 0)
                XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
                XCTAssertTrue(preferences.alertsEnabled)
                if let directory = ProcessInfo.processInfo.environment["SYSTEMPULSE_SCREENSHOT_DIR"] {
                    let url = URL(fileURLWithPath: directory, isDirectory: true)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    try data.write(
                        to: url.appendingPathComponent("settings-\(pane.rawValue)-\(appearance.rawValue).png"))
                }
            }
        }
        XCTAssertEqual(client.requestCalls, 0)
        XCTAssertEqual(client.deliveryCalls, 0)
        XCTAssertEqual(fixture.login.registerCalls, 0)
        XCTAssertEqual(fixture.login.unregisterCalls, 0)
    }

    @MainActor
    func testNativeControllerCloseKeyFrameAndLiveAppearance() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let client = SettingsNotificationTestClient()
        let notifications = LocalNotificationService(client: client)
        let policy = NSApplication.shared.activationPolicy()
        let controller = SettingsWindowController(
            preferences: preferences, notifications: notifications, frameAutosaveName: nil)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.contentViewController is NSHostingController<SettingsView>)
        XCTAssertEqual(window.frameAutosaveName, "")
        window.setContentSize(NSSize(width: 820, height: 680))
        let resizedFrame = window.frame
        for appearance in [Preferences.Appearance.light, .dark] {
            preferences.appearance = appearance
            settleLayout(window)
            XCTAssertEqual(
                window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
                appearance == .dark ? .darkAqua : .aqua)
        }
        preferences.appearance = .system
        settleLayout(window)
        XCTAssertEqual(
            window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]),
            NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]))
        fixture.login.status = .enabled
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        XCTAssertTrue(preferences.launchAtLogin, "Focusing Settings must resync external Login Items changes")
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "w",
                charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13))
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertFalse(window.isVisible, "Cmd+W must perform the native close action")
        XCTAssertTrue(controller.window === window, "Native close must retain the window for reopening")
        XCTAssertEqual(window.frame, resizedFrame)
        XCTAssertEqual(NSApp.activationPolicy(), policy)
        XCTAssertEqual(client.requestCalls + client.deliveryCalls, 0)
        XCTAssertEqual(fixture.login.registerCalls + fixture.login.unregisterCalls, 0)
    }

    @MainActor
    func testPermissionOnlyRequestedByExplicitEnableAndDeniedFeedbackRemainsVisible() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let client = SettingsNotificationTestClient()
        let notifications = LocalNotificationService(client: client)
        await notifications.refreshAuthorization()
        XCTAssertEqual(client.requestCalls, 0)
        XCTAssertNil(SettingsAlertActions.setEnabled(false, preferences: preferences, notifications: notifications))
        XCTAssertFalse(preferences.alertsEnabled)
        XCTAssertEqual(client.requestCalls, 0)
        let task = try XCTUnwrap(
            SettingsAlertActions.setEnabled(true, preferences: preferences, notifications: notifications))
        await task.value
        XCTAssertTrue(preferences.alertsEnabled)
        XCTAssertEqual(client.requestCalls, 1)
        XCTAssertFalse(notifications.canDeliver)
        XCTAssertNotNil(notifications.lastError)
        XCTAssertTrue(notifications.authorizationStatusLabel.contains("Denied"))
        // Rendering denied state and disabling never ask again.
        _ = try render(
            AlertsSettingsPane(preferences: preferences, notifications: notifications), appearance: .light)
        SettingsAlertActions.setEnabled(false, preferences: preferences, notifications: notifications)
        await Task.yield()
        XCTAssertEqual(client.requestCalls, 1)
        XCTAssertEqual(client.deliveryCalls, 0)
    }

    @MainActor
    func testDisablingBeforeQueuedEnableRunsDoesNotRequestPermission() async throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let client = SettingsNotificationTestClient()
        let notifications = LocalNotificationService(client: client)
        let task = try XCTUnwrap(
            SettingsAlertActions.setEnabled(true, preferences: preferences, notifications: notifications))
        SettingsAlertActions.setEnabled(false, preferences: preferences, notifications: notifications)
        await task.value
        XCTAssertFalse(preferences.alertsEnabled)
        XCTAssertEqual(client.requestCalls, 0)
        XCTAssertEqual(client.deliveryCalls, 0)
    }

    @MainActor
    private func settleLayout(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content, appearance: Preferences.Appearance
    ) throws -> NSBitmapImageRep {
        let frame = NSRect(x: 0, y: 0, width: 760, height: 620)
        let hosting = NSHostingView(
            rootView:
                content
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, appearance == .dark ? .dark : .light))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        hosting.frame = frame
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let colors = Set(
            stride(from: bitmap.pixelsHigh / 4, to: bitmap.pixelsHigh * 3 / 4, by: 8).flatMap { y in
                stride(from: bitmap.pixelsWide / 3, to: bitmap.pixelsWide - 20, by: 8).compactMap { x in
                    bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.description
                }
            })
        XCTAssertGreaterThan(colors.count, 3, "Expected settings controls, not an empty detail surface")
        return bitmap
    }
}

@MainActor
private final class SettingsNotificationTestClient: LocalNotificationClient {
    let isAvailable = true
    var authorization: LocalNotificationAuthorization = .denied
    private(set) var requestCalls = 0
    private(set) var deliveryCalls = 0

    func authorizationStatus() async -> LocalNotificationAuthorization { authorization }
    func requestAuthorization() async throws -> Bool {
        requestCalls += 1
        return authorization.canDeliver
    }
    func deliver(_ payload: LocalNotificationPayload) async throws { deliveryCalls += 1 }
}
