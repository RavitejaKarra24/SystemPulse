import AppKit
import SwiftUI

/// Retained independently of the popover; closing hides, rather than destroys, Settings.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static var retained: SettingsWindowController?
    private let preferences: Preferences
    private let notifications: LocalNotificationService

    // Swift 5 evaluates default arguments outside actor isolation. These overloads
    // provide shared defaults without a nonisolated read of a main-actor singleton.
    static func show() {
        show(preferences: .shared, notifications: .shared)
    }

    static func show(preferences: Preferences) {
        show(preferences: preferences, notifications: .shared)
    }

    static func show(notifications: LocalNotificationService) {
        show(preferences: .shared, notifications: notifications)
    }

    static func show(
        preferences: Preferences,
        notifications: LocalNotificationService
    ) {
        if let existing = retained,
            existing.preferences === preferences, existing.notifications === notifications
        {
            existing.showWindow(nil)
            return
        }
        retained?.close()
        let controller = SettingsWindowController(preferences: preferences, notifications: notifications)
        retained = controller
        controller.showWindow(nil)
    }

    /// Passing nil for frameAutosaveName keeps presentation tests out of the user's saved frame.
    init(
        preferences: Preferences,
        notifications: LocalNotificationService,
        frameAutosaveName: String? = "SystemPulse.Settings"
    ) {
        self.preferences = preferences
        self.notifications = notifications
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "SystemPulse Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 660, height: 480)
        window.center()
        // Restore after centering: don't overwrite the user's position on each opening.
        if let frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
            window.setFrameUsingName(frameAutosaveName)
        }
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView(preferences: preferences, notifications: notifications))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        // Accessory apps can activate without temporarily adding a Dock icon.
        NSApp.activate()
        refreshStatus()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshStatus()
    }

    private func refreshStatus() {
        preferences.refreshLaunchAtLoginStatus()
        Task { await notifications.refreshAuthorization() }
    }
}

/// The accessory app has no Window menu, so route Cmd+W to AppKit's native close action.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command,
            event.charactersIgnoringModifiers?.lowercased() == "w"
        {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
