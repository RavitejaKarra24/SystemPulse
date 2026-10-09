import Foundation
import Observation
import UserNotifications

/// Main-actor client boundary keeps UI state and notification operations isolated.
/// Tests inject a client; they never need to construct a notification center.
enum LocalNotificationAuthorization: Sendable {
    case unavailable, notDetermined, denied, authorized, provisional

    var canDeliver: Bool { self == .authorized || self == .provisional }

    var label: String {
        switch self {
        case .unavailable: "Unavailable — run the installed .app"
        case .notDetermined: "Not requested"
        case .denied: "Denied — enable in System Settings"
        case .authorized: "Authorized"
        case .provisional: "Authorized quietly"
        }
    }
}

struct LocalNotificationPayload: Equatable, Sendable {
    let identifier: String
    let title: String
    let message: String
    // No sound or userInfo: alerts carry only aggregate, nonprivate metrics.
}

@MainActor
protocol LocalNotificationClient {
    var isAvailable: Bool { get }
    func authorizationStatus() async -> LocalNotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func deliver(_ payload: LocalNotificationPayload) async throws
}

@Observable
@MainActor
final class LocalNotificationService {
    static let shared = LocalNotificationService()

    private(set) var isRequesting = false
    private(set) var lastError: String?
    private var operationError: String?
    private var errorRevision: UInt64 = 0
    private var authorizationQueryRevision: UInt64 = 0
    @ObservationIgnored private var pendingAuthorization:
        (revision: UInt64, task: Task<LocalNotificationAuthorization, Never>)?
    private(set) var authorizationRevision: UInt64 = 0
    /// Lifecycle sink runs synchronously on the main actor. Observed revocation
    /// must reset warmup immediately, not wait for the next menu-render tick.
    @ObservationIgnored var authorizationDidChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private let now: @MainActor () -> Date
    private var authorization: LocalNotificationAuthorization
    @ObservationIgnored private let client: any LocalNotificationClient

    var authorizationStatusLabel: String { authorization.label }
    var canDeliver: Bool { client.isAvailable && authorization.canDeliver }

    /// Does not query the OS, request permission, or send anything at startup.
    /// The default factory never touches UNUserNotificationCenter outside a .app.
    init(client: (any LocalNotificationClient)? = nil, now: @escaping @MainActor () -> Date = { .now }) {
        let selectedClient = client ?? Self.makeDefaultClient()
        self.client = selectedClient
        self.now = now
        authorization = selectedClient.isAvailable ? .notDetermined : .unavailable
    }

    /// False means superseded: an older query must not overwrite newer state
    /// or authorize a queued delivery using an unrelated response.
    @discardableResult
    func refreshAuthorization() async -> Bool {
        guard client.isAvailable else {
            setAuthorization(.unavailable)
            lastError = "Notifications are unavailable outside an installed application bundle."
            return true
        }
        // Concurrent breach events share one OS query, instead of invalidating
        // each other's delivery. An explicit permission request supersedes it.
        let query: UInt64
        let task: Task<LocalNotificationAuthorization, Never>
        if let pendingAuthorization {
            query = pendingAuthorization.revision
            task = pendingAuthorization.task
        } else {
            authorizationQueryRevision &+= 1
            query = authorizationQueryRevision
            task = Task { [client] in await client.authorizationStatus() }
            pendingAuthorization = (query, task)
        }
        let status = await task.value
        guard query == authorizationQueryRevision else { return false }
        if pendingAuthorization?.revision == query { pendingAuthorization = nil }
        setAuthorization(status)
        lastError =
            authorization == .denied ? "Notifications are denied. Enable them in System Settings." : operationError
        if authorization == .unavailable { lastError = "Notifications are unavailable." }
        return true
    }

    private func setAuthorization(_ status: LocalNotificationAuthorization) {
        let changed = status.canDeliver != authorization.canDeliver
        if changed { authorizationRevision &+= 1 }
        authorization = status
        if changed { authorizationDidChange?(canDeliver) }
    }

    private func invalidateAuthorizationQueries() {
        authorizationQueryRevision &+= 1
        pendingAuthorization = nil
    }

    private func eventIsFresh(_ event: AlertEvent) -> Bool {
        let age = now().timeIntervalSince(event.timestamp)
        return age.isFinite && age >= 0 && age <= AlertEngine.maximumContinuityGap
    }

    /// The ONLY path that may prompt for permission. Wire to an explicit user action.
    func requestAuthorization() async {
        guard !isRequesting else { return }
        guard client.isAvailable else {
            await refreshAuthorization()
            return
        }
        isRequesting = true
        // Invalidate queries begun before this explicit authorization operation.
        invalidateAuthorizationQueries()
        errorRevision &+= 1
        operationError = nil
        lastError = nil
        defer { isRequesting = false }
        do {
            let granted = try await client.requestAuthorization()
            // Queries begun while the permission operation was suspended may
            // also contain a pre-decision snapshot. Confirm from a new query.
            invalidateAuthorizationQueries()
            await refreshAuthorization()
            if !granted && !canDeliver {
                lastError = "Notification permission was not granted. Enable notifications in System Settings."
            }
        } catch {
            invalidateAuthorizationQueries()
            await refreshAuthorization()
            // Never show framework error descriptions that might contain private paths.
            errorRevision &+= 1
            operationError = "Could not request notification permission. Try again or check System Settings."
            lastError = operationError
        }
    }

    func deliver(_ event: AlertEvent, allowDelivery: (@MainActor () -> Bool)? = nil) async {
        guard allowDelivery?() ?? true, eventIsFresh(event) else { return }
        let epoch = canDeliver ? authorizationRevision : nil
        guard await refreshAuthorization() else { return }
        // Settings, permission and event freshness can change while the OS
        // query is suspended. A revoked event never revives on reauthorization.
        guard allowDelivery?() ?? true, eventIsFresh(event),
            epoch.map({ $0 == authorizationRevision }) ?? true
        else { return }
        guard canDeliver else {
            if lastError == nil {
                lastError = "Notifications are not authorized. Use Enable Notifications to request permission."
            }
            return
        }
        let payload = LocalNotificationPayload(
            identifier: "systempulse.alert.\(event.id.uuidString)", title: event.title, message: event.message)
        let beganAtErrorRevision = errorRevision
        do {
            try await client.deliver(payload)
            // A slow older success cannot conceal a newer failed delivery.
            if errorRevision == beganAtErrorRevision {
                operationError = nil
                lastError = nil
            }
        } catch {
            errorRevision &+= 1
            operationError = "Could not deliver the alert. Check notification settings and try again."
            lastError = operationError
        }
    }

    /// XCTest must remain unavailable even when run inside an application test host.
    static func isApplicationBundle(_ bundle: Bundle) -> Bool {
        bundle.bundleURL.pathExtension.lowercased() == "app"
            && bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL"
            && !(bundle.bundleIdentifier ?? "").isEmpty
            && bundle.executableURL != nil
            && NSClassFromString("XCTestCase") == nil
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private static func makeDefaultClient() -> any LocalNotificationClient {
        guard isApplicationBundle(.main) else { return UnavailableNotificationClient() }
        return SystemNotificationClient()
    }
}

@MainActor
private struct UnavailableNotificationClient: LocalNotificationClient {
    let isAvailable = false
    func authorizationStatus() async -> LocalNotificationAuthorization { .unavailable }
    func requestAuthorization() async throws -> Bool { false }
    func deliver(_ payload: LocalNotificationPayload) async throws {}
}

/// Retained by the client because UNUserNotificationCenter's delegate is weak.
/// Stateless callbacks run on the framework's queue, without touching UI state.
private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

@MainActor
private final class SystemNotificationClient: LocalNotificationClient {
    let isAvailable = true
    private let center: UNUserNotificationCenter
    private let delegate = ForegroundNotificationDelegate()

    /// Only called after the .app/test-host guard above has succeeded.
    init() {
        center = UNUserNotificationCenter.current()
        center.delegate = delegate
    }

    func authorizationStatus() async -> LocalNotificationAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status: LocalNotificationAuthorization
                switch settings.authorizationStatus {
                case .notDetermined: status = .notDetermined
                case .denied: status = .denied
                case .authorized, .ephemeral: status = .authorized
                case .provisional: status = .provisional
                @unknown default: status = .unavailable
                }
                continuation.resume(returning: status)
            }
        }
    }

    func requestAuthorization() async throws -> Bool {
        // Deliberately omit .sound. No startup call reaches this method.
        try await center.requestAuthorization(options: [.alert])
    }

    func deliver(_ payload: LocalNotificationPayload) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.message
        content.sound = nil
        let request = UNNotificationRequest(identifier: payload.identifier, content: content, trigger: nil)
        try await center.add(request)
    }
}
