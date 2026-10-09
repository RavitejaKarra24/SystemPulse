import AppKit
import SwiftUI

// MARK: - Menu Bar App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private lazy var store: MonitorStore = MonitorStore(alertSink: { [weak self] event in
        let token = self?.preferences.alertConfigurationToken(for: event.kind)
        let permissionToken = self?.store.notificationAuthorizationRevision
        let notificationToken = LocalNotificationService.shared.authorizationRevision
        Task { @MainActor [weak self] in
            await LocalNotificationService.shared.deliver(
                event,
                allowDelivery: { [weak self] in
                    guard let self else { return false }
                    let preferences = self.preferences
                    return self.store.notificationAuthorizationRevision == permissionToken
                        && LocalNotificationService.shared.authorizationRevision == notificationToken
                        && preferences.alertsEnabled
                        && preferences.alertConfigurationToken(for: event.kind) == token
                        && preferences.alertRules.contains { $0.kind == event.kind && $0.enabled }
                })
        }
    })
    private let preferences = Preferences.shared
    private var titleTimer: Timer?
    private var eventMonitor: Any?
    private var volumeObservers: [NSObjectProtocol] = []
    private var powerObservers: [NSObjectProtocol] = []
    private lazy var authorizationRefresh: NotificationAuthorizationRefresh = NotificationAuthorizationRefresh(
        refresh: { await LocalNotificationService.shared.refreshAuthorization() },
        onComplete: { [weak self] in
            self?.store.notificationDeliveryAllowed = LocalNotificationService.shared.canDeliver
        })

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()
        LocalNotificationService.shared.authorizationDidChange = { [weak self] allowed in
            self?.store.notificationDeliveryAllowed = allowed
        }
        refreshNotificationAuthorization()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "SystemPulse — click to open, right-click for options"
            button.imagePosition = .imageLeading
        }

        let panelHeight = min(CGFloat(720), (NSScreen.main?.visibleFrame.height ?? 810) - 90)
        let root = RootView(
            store: store, preferences: preferences, panelHeight: panelHeight,
            onOpenSettings: { [weak self] in
                self?.openSettings(nil)
            })
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.contentSize = NSSize(width: Theme.popoverWidth, height: panelHeight)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hosting
        popover.delegate = self

        // Keep menu bar responsive while scrolling / tracking.
        titleTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateMenuBarTitle()
            }
        }
        if let titleTimer {
            RunLoop.main.add(titleTimer, forMode: .common)
        }
        updateMenuBarTitle()

        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor in self?.store.refreshVolumes() }
            }
            volumeObservers.append(observer)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        powerObservers.append(
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.store.suspendPolling()
                    self?.titleTimer?.fire()
                }
            })
        powerObservers.append(
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.store.resumePolling()
                    self?.refreshNotificationAuthorization(force: true)
                }
            })

        // Close popover on outside click (more reliable than transient alone).
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.popover.isShown else { return }
                self.setPanelVisible(false)
                self.popover.performClose(nil)
            }
        }
    }

    private let cleanupTerminationGate = CleanupTerminationGate()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if cleanupTerminationGate.deferTerminationIfNeeded(
            store: store,
            onReady: {
                sender.reply(toApplicationShouldTerminate: true)
            })
        {
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        titleTimer?.invalidate()
        authorizationRefresh.stop()
        FolderSelectionSession.shared.cancel()
        CleanupReviewWindowController.shared.close()
        store.stopPolling()
        LocalNotificationService.shared.authorizationDidChange = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        for observer in volumeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        volumeObservers.removeAll()
        for observer in powerObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        powerObservers.removeAll()
    }

    /// Gates the store's expensive sampling to the times the panel is on screen.
    private func setPanelVisible(_ visible: Bool) {
        store.isPanelVisible = visible
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }

        store.synchronizePollingPreferences()
        store.notificationDeliveryAllowed = LocalNotificationService.shared.canDeliver
        refreshNotificationAuthorization()
        let style = preferences.menuBarStyle
        let metrics = preferences.menuBarMetrics
        let readings = store.menuBarReadings()
        let image = MenuBarRenderer.image(readings: readings, metrics: metrics, style: style)
        let description = MenuBarRenderer.tooltipDescription(readings: readings, metrics: metrics)
        button.image = image
        button.attributedTitle = MenuBarRenderer.title(readings: readings, metrics: metrics, style: style)
        button.toolTip = description + "\nClick to open · Right-click for settings"
    }

    @objc private func handleStatusItemClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.animates = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    private func showContextMenu() {
        if popover.isShown {
            popover.performClose(nil)
        }

        preferences.refreshLaunchAtLoginStatus()
        let menu = NSMenu()
        menu.addItem(withTitle: "Open SystemPulse", action: #selector(togglePopover(_:)), keyEquivalent: "o")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")

        menu.addItem(.separator())

        // Menu bar style
        let styleMenu = NSMenu()
        for style in Preferences.MenuBarStyle.allCases {
            let item = NSMenuItem(
                title: style.rawValue,
                action: #selector(selectMenuBarStyle(_:)),
                keyEquivalent: ""
            )
            item.representedObject = style.rawValue
            item.state = preferences.menuBarStyle == style ? .on : .off
            styleMenu.addItem(item)
        }
        let styleItem = NSMenuItem(title: "Menu Bar Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

        // Refresh rate
        let rateMenu = NSMenu()
        for rate in Preferences.RefreshRate.allCases {
            let item = NSMenuItem(
                title: rate.label,
                action: #selector(selectRefreshRate(_:)),
                keyEquivalent: ""
            )
            item.representedObject = rate.rawValue
            item.state = preferences.refreshRate == rate ? .on : .off
            rateMenu.addItem(item)
        }
        let rateItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        rateItem.submenu = rateMenu
        menu.addItem(rateItem)

        let netItem = NSMenuItem(
            title: "Show Network in Menu Bar",
            action: #selector(toggleNetworkInMenuBar),
            keyEquivalent: ""
        )
        netItem.state = preferences.showNetworkInMenuBar ? .on : .off
        menu.addItem(netItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.state = preferences.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "About SystemPulse", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(withTitle: "Quit SystemPulse", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
            if let sub = item.submenu {
                for subItem in sub.items { subItem.target = self }
            }
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        updateMenuBarTitle()
    }

    @objc private func selectMenuBarStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let style = Preferences.MenuBarStyle(rawValue: raw)
        else { return }
        preferences.menuBarStyle = style
        updateMenuBarTitle()
    }

    @objc private func selectRefreshRate(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double,
            let rate = Preferences.RefreshRate(rawValue: value)
        else { return }
        preferences.refreshRate = rate
        store.restartPolling()
    }

    @objc private func toggleNetworkInMenuBar() {
        preferences.showNetworkInMenuBar.toggle()
        updateMenuBarTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        if let message = preferences.setLaunchAtLogin(!preferences.launchAtLogin) {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func openSettings(_ sender: Any?) {
        popover?.performClose(nil)
        SettingsWindowController.show(preferences: preferences)
    }

    private func refreshNotificationAuthorization(force: Bool = false) {
        authorizationRefresh.request(force: force)
    }

    /// Standard commands remain reachable while the standalone settings window is key.
    private func installApplicationMenu() {
        let main = NSMenu()
        let application = NSMenu(title: "SystemPulse")
        let appItem = NSMenuItem(title: "SystemPulse", action: nil, keyEquivalent: "")
        application.addItem(withTitle: "About SystemPulse", action: #selector(showAbout), keyEquivalent: "").target =
            self
        application.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",").target =
            self
        application.addItem(.separator())
        application.addItem(
            withTitle: "Hide SystemPulse", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(withTitle: "Quit SystemPulse", action: #selector(quitApp), keyEquivalent: "q").target = self
        appItem.submenu = application
        main.addItem(appItem)

        let edit = ApplicationEditMenu.make()
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        let windows = NSMenu(title: "Window")
        windows.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windows
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windows
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SystemPulse"
        alert.informativeText = """
            A native menu-bar system monitor for macOS.

            Live CPU, memory, network, and disk insights \
            with process control and reclaimable-space cleanup.

            Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Popover lifecycle

extension AppDelegate: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        setPanelVisible(true)
    }

    func popoverDidClose(_ notification: Notification) {
        setPanelVisible(false)
    }
}
