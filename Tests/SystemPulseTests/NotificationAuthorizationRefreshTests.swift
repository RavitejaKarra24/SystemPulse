import Foundation
import XCTest

@testable import SystemPulse

private final class WeakAuthorizationRefreshReference {
    weak var value: NotificationAuthorizationRefresh?
    init(_ value: NotificationAuthorizationRefresh?) { self.value = value }
}

/// A cancellation-insensitive callback bridge, like an outstanding OS settings query.
@MainActor
private final class AuthorizationRefreshFixture {
    var date = Date(timeIntervalSinceReferenceDate: 1_000)
    var invocations = 0
    var completions = 0
    var returned = false
    var wasCancelledOnReturn = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var returnWaiter: CheckedContinuation<Void, Never>?

    func makeCoordinator() -> NotificationAuthorizationRefresh {
        NotificationAuthorizationRefresh(
            now: { self.date },
            refresh: { await self.refresh() },
            onComplete: { self.completions += 1 })
    }

    private func refresh() async {
        invocations += 1
        returned = false
        await withCheckedContinuation {
            continuation = $0
            startWaiter?.resume()
            startWaiter = nil
        }
        wasCancelledOnReturn = Task.isCancelled
        returned = true
        returnWaiter?.resume()
        returnWaiter = nil
    }

    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func resume() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    func waitForReturn() async {
        if returned { return }
        await withCheckedContinuation { returnWaiter = $0 }
    }
}

final class NotificationAuthorizationRefreshTests: XCTestCase {
    @MainActor
    func testInitializationAndIdleWaitDoNotRefresh() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(NotificationAuthorizationRefresh.interval, 60)
        XCTAssertEqual(fixture.invocations, 0)
        XCTAssertEqual(fixture.completions, 0)
    }

    @MainActor
    func testHundredsOfIntervalsAndWakesKeepOnlyOnePendingWaiter() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        var accepted = coordinator.request() ? 1 : 0
        // Even before the task enters refresh, requests must be bounded.
        for _ in 0..<500 {
            fixture.date.addTimeInterval(60)
            if coordinator.request() { accepted += 1 }
            if coordinator.request(force: true) { accepted += 1 }
        }
        XCTAssertEqual(accepted, 1)
        await fixture.waitForStart()
        for _ in 0..<500 {
            fixture.date.addTimeInterval(60)
            if coordinator.request() { accepted += 1 }
            if coordinator.request(force: true) { accepted += 1 }
        }
        XCTAssertEqual(accepted, 1)
        XCTAssertEqual(fixture.invocations, 1)
        XCTAssertEqual(fixture.completions, 0)

        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 1, "Ignored wakes must not create a backlog on completion")
        XCTAssertEqual(fixture.completions, 1)
        // Cadence is measured from acceptance, not a potentially very late callback.
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        XCTAssertEqual(fixture.invocations, 2)
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.completions, 2)
    }

    @MainActor
    func testEarlyRequestsAreIgnoredAndExactIntervalIsDue() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        let start = fixture.date
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()

        for second in 0..<60 {
            fixture.date = start.addingTimeInterval(Double(second))
            XCTAssertFalse(coordinator.request())
        }
        fixture.date = start.addingTimeInterval(59.999)
        XCTAssertFalse(coordinator.request())
        XCTAssertEqual(fixture.invocations, 1)
        fixture.date = start.addingTimeInterval(60)
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 2)
        XCTAssertEqual(fixture.completions, 2)
    }

    @MainActor
    func testForceBypassesIdleCadenceButEstablishesNewBaseline() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        fixture.date.addTimeInterval(10)
        XCTAssertFalse(coordinator.request())
        XCTAssertTrue(coordinator.request(force: true))
        XCTAssertFalse(coordinator.request(force: true))
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        fixture.date.addTimeInterval(50)
        XCTAssertFalse(coordinator.request())
        fixture.date.addTimeInterval(10)
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 3)
    }

    @MainActor
    func testFutureBaselineAndRepeatedBackwardClockChangesRebaseWithoutQueries() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        for _ in 0..<500 {
            fixture.date.addTimeInterval(-60)
            XCTAssertFalse(coordinator.request())
        }
        XCTAssertEqual(fixture.invocations, 1)
        XCTAssertFalse(coordinator.request())
        fixture.date.addTimeInterval(59)
        XCTAssertFalse(coordinator.request())
        fixture.date.addTimeInterval(1)
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 2)
    }

    @MainActor
    func testInvalidClockReadingsNeverScheduleEvenForcedAndDoNotPoisonCadence() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        let validDate = fixture.date
        let invalidIntervals: [TimeInterval] = [.nan, .infinity, -.infinity]
        for _ in 0..<100 {
            for interval in invalidIntervals {
                fixture.date = Date(timeIntervalSinceReferenceDate: interval)
                XCTAssertFalse(coordinator.request())
                XCTAssertFalse(coordinator.request(force: true))
            }
        }
        XCTAssertEqual(fixture.invocations, 0)
        fixture.date = validDate
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        for interval in invalidIntervals {
            fixture.date = Date(timeIntervalSinceReferenceDate: interval)
            XCTAssertFalse(coordinator.request())
            XCTAssertFalse(coordinator.request(force: true))
        }
        fixture.date = validDate.addingTimeInterval(59)
        XCTAssertFalse(coordinator.request())
        fixture.date = validDate.addingTimeInterval(60)
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 2)
    }

    @MainActor
    func testOverflowedElapsedTimeRebasesWithoutQuerySpam() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        fixture.date = Date(timeIntervalSinceReferenceDate: -Double.greatestFiniteMagnitude)
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        fixture.date = Date(timeIntervalSinceReferenceDate: Double.greatestFiniteMagnitude)
        for _ in 0..<500 { XCTAssertFalse(coordinator.request()) }
        XCTAssertEqual(fixture.invocations, 1)
    }

    @MainActor
    func testStopBeforeAnyRequestIsTerminal() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        coordinator.stop()
        coordinator.stop()
        for _ in 0..<500 {
            fixture.date.addTimeInterval(60)
            XCTAssertFalse(coordinator.request())
            XCTAssertFalse(coordinator.request(force: true))
        }
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 0)
        XCTAssertEqual(fixture.completions, 0)
    }

    @MainActor
    func testStopBeforeTaskStartsSkipsRefreshAndCompletion() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        XCTAssertTrue(coordinator.request())
        coordinator.stop()
        await coordinator.waitForCurrentRefresh()
        XCTAssertEqual(fixture.invocations, 0)
        XCTAssertEqual(fixture.completions, 0)
        XCTAssertFalse(coordinator.request(force: true))
    }

    @MainActor
    func testStopWhilePendingRejectsLateCompletionAndRestart() async {
        let fixture = AuthorizationRefreshFixture()
        let coordinator = fixture.makeCoordinator()
        XCTAssertTrue(coordinator.request())
        await fixture.waitForStart()
        coordinator.stop()
        coordinator.stop()
        for _ in 0..<500 {
            fixture.date.addTimeInterval(60)
            XCTAssertFalse(coordinator.request())
            XCTAssertFalse(coordinator.request(force: true))
        }
        XCTAssertEqual(fixture.invocations, 1)
        XCTAssertFalse(fixture.returned, "Cancellation need not interrupt the underlying callback")
        fixture.resume()
        await coordinator.waitForCurrentRefresh()
        XCTAssertTrue(fixture.wasCancelledOnReturn)
        XCTAssertEqual(fixture.completions, 0)
        XCTAssertFalse(coordinator.request())
        XCTAssertFalse(coordinator.request(force: true))
        XCTAssertEqual(fixture.invocations, 1)
    }

    @MainActor
    func testPendingRefreshDoesNotRetainCoordinatorAndDeinitCancelsWaiter() async {
        let fixture = AuthorizationRefreshFixture()
        var coordinator: NotificationAuthorizationRefresh? = fixture.makeCoordinator()
        let weakCoordinator = WeakAuthorizationRefreshReference(coordinator)
        XCTAssertEqual(coordinator?.request(), true)
        await fixture.waitForStart()
        coordinator = nil
        XCTAssertNil(weakCoordinator.value, "A stuck callback must not keep the coordinator alive")
        XCTAssertFalse(fixture.returned)
        fixture.resume()
        await fixture.waitForReturn()
        XCTAssertTrue(fixture.wasCancelledOnReturn)
        XCTAssertEqual(fixture.invocations, 1)
        XCTAssertEqual(fixture.completions, 0)
    }
}
