import Foundation
import XCTest

@testable import SystemPulse

final class AccessibilityStatusTests: XCTestCase {
    func testLiveAnnouncementsAreBlockedForTestsUnbundledProcessesAndDisabledVoiceOver() {
        for app in [false, true] {
            for test in [false, true] {
                for voiceOver in [false, true] {
                    XCTAssertEqual(
                        AccessibilityStatusClient.permitsLiveAnnouncement(
                            isApplicationBundle: app, isTestProcess: test, voiceOverEnabled: voiceOver),
                        app && !test && voiceOver)
                }
            }
        }
    }

    @MainActor
    func testStatusAnnouncementsAreInjectedCoalescedAndDoNotChangePreferences() throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let before = fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]
        var messages: [String] = []
        let store = MonitorStore(
            startPolling: false, preferences: preferences,
            accessibilityStatusClient: .init(announce: { messages.append($0.accessibilitySummary) }))
        store.showToast("Injected failure", isError: true)
        let first = try XCTUnwrap(store.toast)
        store.showToast("Injected failure", isError: true)
        XCTAssertEqual(store.toast?.id, first.id)
        store.showToast("Injected failure", isError: false)
        XCTAssertEqual(store.toast?.id, first.id)
        store.dismissToast(id: first.id)
        store.showToast("Injected failure", isError: false)
        XCTAssertEqual(messages, ["Action failed: Injected failure", "Status: Injected failure"])
        XCTAssertEqual(
            (fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]) as NSDictionary,
            before as NSDictionary)
        store.stopPolling()
    }

    @MainActor
    func testFailureRemainsReadablePastOldDismissalDeadline() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(), accessibilityStatusClient: .silent)
        store.showToast("Long failure feedback", isError: true)
        let message = try XCTUnwrap(store.toast)
        try await Task.sleep(for: .seconds(2.3))
        XCTAssertEqual(store.toast?.id, message.id)
        store.dismissToast(id: message.id)
        XCTAssertNil(store.toast)
    }

    @MainActor
    func testStaleDismissCannotRemoveReplacedStatusAndSuccessCannotExpireLaterFailure() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(), accessibilityStatusClient: .silent)
        store.showToast("First status")
        let old = try XCTUnwrap(store.toast)
        store.showToast("A newer failure", isError: true)
        let current = try XCTUnwrap(store.toast)
        store.dismissToast(id: old.id)
        try await Task.sleep(for: .seconds(2.3))
        XCTAssertEqual(store.toast?.id, current.id)
        store.dismissToast(id: current.id)
        XCTAssertNil(store.toast)
    }

    @MainActor
    func testAutomaticVolumeFallbackAndSuccessCannotEraseAnUndismissedFailure() throws {
        let fixture = try SettingsPreferencesFixture()
        var messages: [String] = []
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            accessibilityStatusClient: .init(announce: { messages.append($0.text) }))
        store.selectedVolumeID = "removed-fixture-volume"
        store.showToast("Retained fixture failure", isError: true)
        let failure = try XCTUnwrap(store.toast)
        store.applyVolumes([])
        XCTAssertNil(store.selectedVolumeID)
        XCTAssertEqual(store.toast?.id, failure.id)
        store.showToast("Routine fixture success")
        XCTAssertEqual(store.toast?.id, failure.id)
        XCTAssertEqual(messages, [failure.text])
        store.dismissToast(id: failure.id)
        XCTAssertNil(store.toast)  // Suppressed statuses are never replayed.
        store.showToast("A fresh fixture success")
        XCTAssertEqual(store.toast?.text, "A fresh fixture success")
        store.stopPolling()
    }

    @MainActor
    func testSuccessStillClearsWithoutRepeatingTheAnnouncement() async throws {
        let fixture = try SettingsPreferencesFixture()
        var announcements = 0
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            accessibilityStatusClient: .init(announce: { _ in announcements += 1 }))
        store.showToast("Transient fixture success")
        for _ in 0..<40 {
            if store.toast == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(store.toast)
        XCTAssertEqual(announcements, 1)
    }

    @MainActor
    func testAnnouncementCallbackCannotCreateATimerAfterTerminalStop() async throws {
        let fixture = try SettingsPreferencesFixture()
        let reference = StatusStoreReference()
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            accessibilityStatusClient: .init(announce: { _ in reference.value?.stopPolling() }))
        reference.value = store
        store.showToast("Terminal fixture status")
        let message = try XCTUnwrap(store.toast)
        XCTAssertEqual(store.pollingState, .stopped)
        try await Task.sleep(for: .seconds(2.3))
        XCTAssertEqual(store.toast?.id, message.id)
    }

    @MainActor
    func testStoppedStoreNeverAnnouncesOrCreatesNewFeedback() throws {
        let fixture = try SettingsPreferencesFixture()
        var announcements = 0
        let store = MonitorStore(
            startPolling: false, preferences: fixture.makePreferences(),
            accessibilityStatusClient: .init(announce: { _ in announcements += 1 }))
        store.stopPolling()
        store.showToast("Late error", isError: true)
        XCTAssertEqual(announcements, 0)
        XCTAssertNil(store.toast)
    }
}

@MainActor
private final class StatusStoreReference {
    weak var value: MonitorStore?
}
