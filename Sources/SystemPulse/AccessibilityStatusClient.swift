import AppKit

/// Accessibility announcements are separate from local UserNotifications.
/// No permissions are requested; ordinary tests never announce to the real OS.
struct AccessibilityStatusClient {
    let announce: @MainActor (ToastMessage) -> Void
    static let silent = Self(announce: { _ in })
    static let live = Self(announce: { message in
        guard let application = NSApp,
            permitsLiveAnnouncement(
                isApplicationBundle: Bundle.main.bundleURL.pathExtension == "app",
                isTestProcess: NSClassFromString("XCTestCase") != nil
                    || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
                voiceOverEnabled: NSWorkspace.shared.isVoiceOverEnabled
            )
        else { return }
        NSAccessibility.post(
            element: application, notification: .announcementRequested,
            userInfo: [
                .announcement: message.accessibilitySummary,
                .priority: message.isError
                    ? NSAccessibilityPriorityLevel.high.rawValue : NSAccessibilityPriorityLevel.medium.rawValue,
            ])
    })

    static func permitsLiveAnnouncement(isApplicationBundle: Bool, isTestProcess: Bool, voiceOverEnabled: Bool) -> Bool
    {
        isApplicationBundle && !isTestProcess && voiceOverEnabled
    }
}

extension ToastMessage {
    var accessibilitySummary: String { "\(isError ? "Action failed" : "Status"): \(text)" }
}
