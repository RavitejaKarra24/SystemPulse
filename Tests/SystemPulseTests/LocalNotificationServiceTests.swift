import XCTest

@testable import SystemPulse

@MainActor
private final class MockNotificationClient: LocalNotificationClient {
    var isAvailable = true
    var status: LocalNotificationAuthorization = .notDetermined
    var grant = true
    var requestError: Error?
    var deliveryError: Error?
    var requestCount = 0
    var refreshCount = 0
    var payloads: [LocalNotificationPayload] = []
    var requestContinuation: CheckedContinuation<Bool, Never>?
    var pauseRequest = false
    var pauseRefresh = false
    var refreshContinuation: CheckedContinuation<LocalNotificationAuthorization, Never>?
    var refreshContinuations: [CheckedContinuation<LocalNotificationAuthorization, Never>] = []
    var pauseDelivery = false
    var deliveryContinuation: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> LocalNotificationAuthorization {
        refreshCount += 1
        if pauseRefresh {
            return await withCheckedContinuation {
                refreshContinuation = $0
                refreshContinuations.append($0)
            }
        }
        return status
    }

    func requestAuthorization() async throws -> Bool {
        requestCount += 1
        if let requestError { throw requestError }
        let result: Bool
        if pauseRequest {
            result = await withCheckedContinuation { requestContinuation = $0 }
        } else {
            result = grant
        }
        status = result ? .authorized : .denied
        return result
    }

    func deliver(_ payload: LocalNotificationPayload) async throws {
        if let deliveryError { throw deliveryError }
        if pauseDelivery { await withCheckedContinuation { deliveryContinuation = $0 } }
        payloads.append(payload)
    }
}

private enum NotificationTestError: Error {
    case failure
}

final class LocalNotificationServiceTests: XCTestCase {
    private var event: AlertEvent {
        AlertEvent(
            kind: .memoryHeadroom, timestamp: .now,
            value: 5, threshold: 10, duration: 30)
    }

    @MainActor
    func testInitializationAndRefreshNeverRequestOrDeliver() async {
        let client = MockNotificationClient()
        let service = LocalNotificationService(client: client)
        XCTAssertEqual(client.refreshCount, 0)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertFalse(service.canDeliver)
        XCTAssertEqual(service.authorizationStatusLabel, "Not requested")
        XCTAssertFalse(service.isRequesting)
        XCTAssertNil(service.lastError)
        await service.refreshAuthorization()
        XCTAssertEqual(client.refreshCount, 1)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(client.payloads.isEmpty)
    }

    @MainActor
    func testDefaultAndSharedServicesAreSafeAndUnavailableInXCTest() async {
        XCTAssertFalse(LocalNotificationService.isApplicationBundle(.main))
        for service in [LocalNotificationService(), LocalNotificationService.shared] {
            XCTAssertFalse(service.canDeliver)
            XCTAssertTrue(service.authorizationStatusLabel.contains("Unavailable"))
            await service.refreshAuthorization()
            await service.requestAuthorization()
            await service.deliver(event)
            XCTAssertFalse(service.canDeliver)
            XCTAssertFalse(service.isRequesting)
            XCTAssertTrue(service.lastError?.contains("unavailable") ?? false)
        }
    }

    @MainActor
    func testUnavailableInjectedClientIsNeverCalled() async {
        let client = MockNotificationClient()
        client.isAvailable = false
        client.status = .authorized
        let service = LocalNotificationService(client: client)
        await service.refreshAuthorization()
        await service.requestAuthorization()
        await service.deliver(event)
        XCTAssertEqual(client.refreshCount, 0)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertFalse(service.canDeliver)
        XCTAssertTrue(service.authorizationStatusLabel.contains("Unavailable"))
    }

    @MainActor
    func testExplicitGrantUpdatesStateWithoutTestNotification() async {
        let client = MockNotificationClient()
        let service = LocalNotificationService(client: client)
        await service.requestAuthorization()
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertTrue(service.canDeliver)
        XCTAssertEqual(service.authorizationStatusLabel, "Authorized")
        XCTAssertFalse(service.isRequesting)
        XCTAssertNil(service.lastError)
        XCTAssertTrue(client.payloads.isEmpty)
    }

    @MainActor
    func testDeniedAuthorizationHasActionableFeedbackAndNoDelivery() async {
        let client = MockNotificationClient()
        client.grant = false
        let service = LocalNotificationService(client: client)
        await service.requestAuthorization()
        XCTAssertFalse(service.canDeliver)
        XCTAssertTrue(service.authorizationStatusLabel.contains("Denied"))
        XCTAssertTrue(service.lastError?.contains("System Settings") ?? false)
        await service.deliver(event)
        XCTAssertEqual(client.requestCount, 1)
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertFalse(service.isRequesting)
        client.status = .authorized
        await service.refreshAuthorization()
        XCTAssertTrue(service.canDeliver)
        XCTAssertNil(service.lastError)
    }

    @MainActor
    func testDeliveryDoesNotRequestUndeterminedPermission() async {
        let client = MockNotificationClient()
        let service = LocalNotificationService(client: client)
        await service.deliver(event)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertFalse(service.canDeliver)
        XCTAssertTrue(service.lastError?.contains("not authorized") ?? false)
    }

    @MainActor
    func testAuthorizedAndProvisionalDeliveryUseOnlyMetricPresentation() async {
        for status in [LocalNotificationAuthorization.authorized, .provisional] {
            let client = MockNotificationClient()
            client.status = status
            let service = LocalNotificationService(client: client)
            let event = event
            await service.deliver(event)
            XCTAssertTrue(service.canDeliver)
            XCTAssertEqual(client.requestCount, 0)
            XCTAssertEqual(client.payloads.count, 1)
            XCTAssertEqual(client.payloads.first?.identifier, "systempulse.alert.\(event.id.uuidString)")
            XCTAssertEqual(client.payloads.first?.title, event.title)
            XCTAssertEqual(client.payloads.first?.message, event.message)
            XCTAssertTrue(client.payloads.first?.message.contains("ESTIMATED") ?? false)
            XCTAssertFalse(client.payloads.first?.message.contains("/") ?? true)
            XCTAssertNil(service.lastError)
        }
    }

    @MainActor
    func testDeliveryRefreshesRevokedPermission() async {
        let client = MockNotificationClient()
        client.status = .authorized
        let service = LocalNotificationService(client: client)
        await service.refreshAuthorization()
        XCTAssertTrue(service.canDeliver)
        client.status = .denied
        await service.deliver(event)
        XCTAssertFalse(service.canDeliver)
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(service.lastError?.contains("denied") ?? false)
    }

    @MainActor
    func testRequestAndDeliveryErrorsAreClearAndRecoverable() async {
        let client = MockNotificationClient()
        let service = LocalNotificationService(client: client)
        client.requestError = NotificationTestError.failure
        await service.requestAuthorization()
        XCTAssertFalse(service.isRequesting)
        XCTAssertTrue(service.lastError?.contains("Could not request") ?? false)
        client.requestError = nil
        await service.requestAuthorization()
        XCTAssertNil(service.lastError)
        client.deliveryError = NotificationTestError.failure
        await service.deliver(event)
        XCTAssertTrue(service.canDeliver)
        XCTAssertTrue(service.lastError?.contains("Could not deliver") ?? false)
        XCTAssertTrue(client.payloads.isEmpty)
        await service.refreshAuthorization()
        XCTAssertTrue(
            service.lastError?.contains("Could not deliver") ?? false,
            "Background refresh must not hide delivery failure")
        client.deliveryError = nil
        await service.deliver(event)
        XCTAssertNil(service.lastError)
        XCTAssertEqual(client.payloads.count, 1)
    }

    @MainActor
    func testOptOutWhileAuthorizationRefreshIsSuspendedCancelsDelivery() async {
        let client = MockNotificationClient()
        client.status = .authorized
        client.pauseRefresh = true
        let service = LocalNotificationService(client: client)
        var enabled = true
        let delivery = Task { await service.deliver(event, allowDelivery: { enabled }) }
        while client.refreshContinuation == nil { await Task.yield() }
        enabled = false
        client.refreshContinuation?.resume(returning: .authorized)
        await delivery.value
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertNil(service.lastError)
    }

    @MainActor
    func testRuleEditAndRevertDuringAuthorizationDropsQueuedEvent() async throws {
        try await assertConfigurationChangeDuringDelivery(shouldDeliver: false) { preferences in
            let original = preferences.alertRules
            var rules = original
            rules[0].threshold = 99
            preferences.alertRules = rules
            preferences.alertRules = original
        }
    }

    @MainActor
    func testBriefOptOutDuringAuthorizationDropsQueuedEvent() async throws {
        try await assertConfigurationChangeDuringDelivery(shouldDeliver: false) { preferences in
            preferences.alertsEnabled = false
            preferences.alertsEnabled = true
        }
    }

    @MainActor
    func testUnrelatedRuleEditDuringAuthorizationKeepsEligibleEvent() async throws {
        try await assertConfigurationChangeDuringDelivery(shouldDeliver: true) { preferences in
            var rules = preferences.alertRules
            let index = rules.firstIndex { $0.kind == .diskAvailable }!
            rules[index].threshold = Double(1 << 30)
            preferences.alertRules = rules
        }
    }

    @MainActor
    private func assertConfigurationChangeDuringDelivery(
        shouldDeliver: Bool, change: (Preferences) -> Void
    ) async throws {
        let name = "SystemPulse.AsyncAlerts.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.alertsEnabled = true
        let token = preferences.alertConfigurationToken(for: .cpuUsage)
        let client = MockNotificationClient()
        client.status = .authorized
        client.pauseRefresh = true
        let service = LocalNotificationService(client: client)
        let event = AlertEvent(kind: .cpuUsage, timestamp: .now, value: 95, threshold: 90, duration: 30)
        let delivery = Task {
            await service.deliver(
                event,
                allowDelivery: {
                    preferences.alertsEnabled && preferences.alertConfigurationToken(for: .cpuUsage) == token
                })
        }
        while client.refreshContinuation == nil { await Task.yield() }
        change(preferences)
        client.refreshContinuation?.resume(returning: .authorized)
        await delivery.value
        XCTAssertEqual(client.payloads.count, shouldDeliver ? 1 : 0)
        XCTAssertEqual(client.requestCount, 0)
    }

    @MainActor
    func testOldRefreshCannotOverwriteExplicitAuthorization() async {
        let client = MockNotificationClient()
        client.pauseRefresh = true
        let service = LocalNotificationService(client: client)
        let old = Task { await service.refreshAuthorization() }
        while client.refreshContinuations.isEmpty { await Task.yield() }
        let request = Task { await service.requestAuthorization() }
        while client.refreshContinuations.count < 2 { await Task.yield() }
        client.refreshContinuations[1].resume(returning: .authorized)
        await request.value
        XCTAssertTrue(service.canDeliver)
        client.refreshContinuations[0].resume(returning: .denied)
        let applied = await old.value
        XCTAssertFalse(applied)
        XCTAssertTrue(service.canDeliver)
        XCTAssertNil(service.lastError)
    }

    @MainActor
    func testQueryStartedDuringPermissionPromptCannotOverrideDecision() async {
        let client = MockNotificationClient()
        client.pauseRequest = true
        client.pauseRefresh = true
        let service = LocalNotificationService(client: client)
        let request = Task { await service.requestAuthorization() }
        while client.requestContinuation == nil { await Task.yield() }
        let duringPrompt = Task { await service.refreshAuthorization() }
        while client.refreshContinuations.isEmpty { await Task.yield() }
        client.requestContinuation?.resume(returning: false)
        while client.refreshContinuations.count < 2 { await Task.yield() }
        client.refreshContinuations[1].resume(returning: .denied)
        await request.value
        client.refreshContinuations[0].resume(returning: .authorized)
        let applied = await duringPrompt.value
        XCTAssertFalse(applied)
        XCTAssertFalse(service.canDeliver)
        XCTAssertTrue(service.authorizationStatusLabel.contains("Denied"))
        XCTAssertTrue(client.payloads.isEmpty)
    }

    @MainActor
    func testPermissionRevocationAndReauthorizationInvalidatesQueuedEvent() async {
        let client = MockNotificationClient()
        client.status = .authorized
        let service = LocalNotificationService(client: client)
        await service.refreshAuthorization()
        client.pauseRefresh = true
        let delivery = Task { await service.deliver(event) }
        while client.refreshContinuations.isEmpty { await Task.yield() }
        client.pauseRefresh = false
        client.grant = false
        await service.requestAuthorization()
        client.grant = true
        await service.requestAuthorization()
        client.refreshContinuations[0].resume(returning: .authorized)
        await delivery.value
        XCTAssertTrue(client.payloads.isEmpty)
        XCTAssertTrue(service.canDeliver)
    }

    @MainActor
    func testConcurrentBreachesShareAuthorizationWithoutDroppingEvents() async {
        let client = MockNotificationClient()
        client.status = .authorized
        client.pauseRefresh = true
        let service = LocalNotificationService(client: client)
        let first = Task { await service.deliver(event) }
        while client.refreshContinuations.isEmpty { await Task.yield() }
        let second = Task { await service.deliver(event) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(client.refreshCount, 1)
        client.refreshContinuations[0].resume(returning: .authorized)
        await first.value
        await second.value
        XCTAssertEqual(client.payloads.count, 2)
    }

    @MainActor
    func testObservedPermissionTransitionsResetStoreBeforeNextMenuTick() async throws {
        let name = "SystemPulse.PermissionLifecycle.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.alertsEnabled = true
        var events: [AlertEvent] = []
        let store = MonitorStore(startPolling: false, preferences: preferences, alertSink: { events.append($0) })
        let client = MockNotificationClient()
        client.status = .authorized
        let service = LocalNotificationService(client: client)
        service.authorizationDidChange = { store.notificationDeliveryAllowed = $0 }
        await service.refreshAuthorization()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        func sample(_ second: Int) {
            let date = base.addingTimeInterval(Double(second))
            store.applySample(
                cpu: .init(perCore: [95]),
                memory: MemoryBreakdown(app: 0, wired: 0, compressed: 0, cached: 0, free: 0, total: 0),
                io: DiskIOSnapshot(timestamp: date), power: nil, net: NetworkSnapshot(timestamp: date),
                disk: nil, info: nil, evaluatedAt: date)
        }
        for second in stride(from: 0, through: 27, by: 3) { sample(second) }
        client.status = .denied
        await service.refreshAuthorization()
        XCTAssertFalse(store.notificationDeliveryAllowed)
        client.status = .authorized
        await service.refreshAuthorization()
        for second in stride(from: 30, through: 57, by: 3) { sample(second) }
        XCTAssertTrue(events.isEmpty)
        sample(60)
        XCTAssertEqual(events.map(\.kind), [.cpuUsage])
        XCTAssertEqual(events.first?.timestamp, base.addingTimeInterval(60))
        XCTAssertEqual(client.requestCount, 0)
        XCTAssertTrue(client.payloads.isEmpty)
    }

    @MainActor
    func testSlowOldSuccessDoesNotHideNewerFailure() async {
        let client = MockNotificationClient()
        client.status = .authorized
        client.pauseDelivery = true
        let service = LocalNotificationService(client: client)
        let first = Task { await service.deliver(event) }
        while client.deliveryContinuation == nil { await Task.yield() }
        client.deliveryError = NotificationTestError.failure
        await service.deliver(event)
        XCTAssertTrue(service.lastError?.contains("Could not deliver") ?? false)
        client.deliveryContinuation?.resume()
        await first.value
        XCTAssertTrue(service.lastError?.contains("Could not deliver") ?? false)
        await service.refreshAuthorization()
        XCTAssertTrue(service.lastError?.contains("Could not deliver") ?? false)
    }

    @MainActor
    func testEventAgingDuringAuthorizationIsNotDelivered() async {
        let client = MockNotificationClient()
        client.status = .authorized
        client.pauseRefresh = true
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var now = base
        let service = LocalNotificationService(client: client, now: { now })
        let event = AlertEvent(kind: .cpuUsage, timestamp: base, value: 95, threshold: 90, duration: 30)
        let delivery = Task { await service.deliver(event) }
        while client.refreshContinuation == nil { await Task.yield() }
        now = base.addingTimeInterval(300)
        client.refreshContinuation?.resume(returning: .authorized)
        await delivery.value
        XCTAssertTrue(client.payloads.isEmpty)
        await service.deliver(event)
        XCTAssertEqual(client.refreshCount, 1, "Already stale events do not issue authorization queries")
    }

    @MainActor
    func testConcurrentExplicitRequestsAreCoalescedAndRequestingIsObservable() async {
        let client = MockNotificationClient()
        client.pauseRequest = true
        let service = LocalNotificationService(client: client)
        let firstRequest = Task { await service.requestAuthorization() }
        // Yield until the mock reaches its deterministic suspension point.
        while client.requestContinuation == nil { await Task.yield() }
        XCTAssertTrue(service.isRequesting)
        await service.requestAuthorization()
        XCTAssertEqual(client.requestCount, 1)
        client.requestContinuation?.resume(returning: true)
        client.requestContinuation = nil
        await firstRequest.value
        XCTAssertFalse(service.isRequesting)
        XCTAssertTrue(service.canDeliver)
        XCTAssertTrue(client.payloads.isEmpty)
    }
}
