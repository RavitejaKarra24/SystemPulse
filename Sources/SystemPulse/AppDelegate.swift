import AppKit
import SwiftUI

// MARK: - Menu Bar App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = MonitorStore()
    private let preferences = Preferences.shared
    private var titleTimer: Timer?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(handleStatusItemClick(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "SystemPulse — click to open, right-click for options"
            button.imagePosition = .imageLeading
        }

        let root = RootView(store: store, preferences: preferences)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]

        popover = NSPopover()
        popover.contentSize = NSSize(width: Theme.popoverWidth, height: 520)
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

    func applicationWillTerminate(_ notification: Notification) {
        titleTimer?.invalidate()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    /// Gates the store's expensive sampling to the times the panel is on screen.
    private func setPanelVisible(_ visible: Bool) {
        store.isPanelVisible = visible
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }

        let style = preferences.menuBarStyle
        let showNet = preferences.showNetworkInMenuBar

        let image = MenuBarRenderer.image(
            cpu: store.cpuUsage,
            memory: store.memoryUsage,
            netIn: store.netInRate,
            netOut: store.netOutRate,
            style: style,
            showNetwork: showNet
        )
        let title = MenuBarRenderer.title(
            cpu: store.cpuUsage,
            memory: store.memoryUsage,
            netIn: store.netInRate,
            netOut: store.netOutRate,
            style: style,
            showNetwork: showNet
        )

        // VoiceOver reads this instead of the drawn gauges, which carry no text.
        image.accessibilityDescription = String(
            format: "SystemPulse. CPU %.0f percent, memory %.0f percent.",
            store.cpuUsage,
            store.memoryUsage
        )
        button.image = image
        button.attributedTitle = title

        var tip = String(
            format: "CPU %.0f%% · Memory %.0f%%\n↓%@ · ↑%@",
            store.cpuUsage,
            store.memoryUsage,
            ByteFormatter.formatRate(store.netInRate),
            ByteFormatter.formatRate(store.netOutRate)
        )
        if store.power.hasBattery {
            tip += String(format: "\nBattery %.0f%% · %@", store.power.chargePercent, store.power.stateLabel)
        }
        tip += String(format: "\nTop: %@ (%.1f%%)", store.topProcessName, store.topProcessCPU)
        button.toolTip = tip
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showContextMenu() {
        if popover.isShown {
            popover.performClose(nil)
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open SystemPulse", action: #selector(togglePopover(_:)), keyEquivalent: "o")

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
              let style = Preferences.MenuBarStyle(rawValue: raw) else { return }
        preferences.menuBarStyle = style
        updateMenuBarTitle()
    }

    @objc private func selectRefreshRate(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double,
              let rate = Preferences.RefreshRate(rawValue: value) else { return }
        preferences.refreshRate = rate
        store.restartPolling()
    }

    @objc private func toggleNetworkInMenuBar() {
        preferences.showNetworkInMenuBar.toggle()
        updateMenuBarTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        preferences.setLaunchAtLogin(!preferences.launchAtLogin)
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
