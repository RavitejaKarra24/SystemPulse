import Foundation
import ServiceManagement

/// User-facing preferences backed by UserDefaults.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case gauges = "Gauges"
        case compact = "Compact"
        case detailed = "Detailed"
        case iconOnly = "Icon Only"

        var id: String { rawValue }
    }

    enum RefreshRate: Double, CaseIterable, Identifiable {
        case fast = 1.0
        case normal = 1.5
        case relaxed = 3.0

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .fast: return "Fast (1s)"
            case .normal: return "Normal (1.5s)"
            case .relaxed: return "Relaxed (3s)"
            }
        }
    }

    var menuBarStyle: MenuBarStyle {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: Keys.menuBarStyle) }
    }

    var refreshRate: RefreshRate {
        didSet { UserDefaults.standard.set(refreshRate.rawValue, forKey: Keys.refreshRate) }
    }

    var showNetworkInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showNetworkInMenuBar, forKey: Keys.showNetwork) }
    }

    var launchAtLogin: Bool

    private enum Keys {
        static let menuBarStyle = "prefs.menuBarStyle"
        static let refreshRate = "prefs.refreshRate"
        static let showNetwork = "prefs.showNetwork"
    }

    private init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Keys.menuBarStyle),
           let style = MenuBarStyle(rawValue: raw) {
            menuBarStyle = style
        } else {
            menuBarStyle = .gauges
        }

        let rate = defaults.double(forKey: Keys.refreshRate)
        refreshRate = RefreshRate(rawValue: rate) ?? .normal
        showNetworkInMenuBar = defaults.object(forKey: Keys.showNetwork) as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Unsigned local builds often can't register — keep UI honest.
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
