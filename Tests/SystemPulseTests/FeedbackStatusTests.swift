import Foundation
import XCTest

@testable import SystemPulse

final class FeedbackStatusTests: XCTestCase {
    @MainActor
    func testStatusFeedbackIsCoalescedAndDoesNotChangePreferences() throws {
        let fixture = try SettingsPreferencesFixture()
        let preferences = fixture.makePreferences()
        let before = fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]
        let store = MonitorStore(startPolling: false, preferences: preferences)
        store.showToast("Injected failure", isError: true)
        let first = try XCTUnwrap(store.toast)
        store.showToast("Injected failure", isError: true)
        XCTAssertEqual(store.toast?.id, first.id)
        store.showToast("Injected failure", isError: false)
        XCTAssertEqual(store.toast?.id, first.id)
        store.dismissToast(id: first.id)
        store.showToast("Injected failure", isError: false)
        XCTAssertEqual(store.toast?.text, "Injected failure")
        XCTAssertFalse(try XCTUnwrap(store.toast).isError)
        XCTAssertEqual(
            (fixture.defaults.persistentDomain(forName: fixture.suiteName) ?? [:]) as NSDictionary,
            before as NSDictionary)
        store.stopPolling()
    }

    @MainActor
    func testFailureRemainsReadablePastOldDismissalDeadline() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
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
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
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
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        store.selectedVolumeID = "removed-fixture-volume"
        store.showToast("Retained fixture failure", isError: true)
        let failure = try XCTUnwrap(store.toast)
        store.applyVolumes([])
        XCTAssertNil(store.selectedVolumeID)
        XCTAssertEqual(store.toast?.id, failure.id)
        store.showToast("Routine fixture success")
        XCTAssertEqual(store.toast?.id, failure.id)
        store.dismissToast(id: failure.id)
        XCTAssertNil(store.toast)
        store.showToast("A fresh fixture success")
        XCTAssertEqual(store.toast?.text, "A fresh fixture success")
        store.stopPolling()
    }

    @MainActor
    func testSuccessStillClears() async throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        store.showToast("Transient fixture success")
        for _ in 0..<40 {
            if store.toast == nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(store.toast)
    }

    @MainActor
    func testStoppedStoreNeverCreatesNewFeedback() throws {
        let fixture = try SettingsPreferencesFixture()
        let store = MonitorStore(startPolling: false, preferences: fixture.makePreferences())
        store.stopPolling()
        store.showToast("Late error", isError: true)
        XCTAssertNil(store.toast)
    }
}
