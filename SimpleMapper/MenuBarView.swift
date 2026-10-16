import AppKit

/// Menu bar item with a plain AppKit menu (no SwiftUI, for footprint). The menu is rebuilt each time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let monitor: KeyboardMonitor
    private let updater: Updater
    private let detector: KeyDetector
    private let onOpen: () -> Void
    private let onAbout: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    init(model: AppModel, monitor: KeyboardMonitor, updater: Updater, detector: KeyDetector,
         onOpen: @escaping () -> Void, onAbout: @escaping () -> Void) {
        self.model = model
        self.monitor = monitor
        self.updater = updater
        self.detector = detector
        self.onOpen = onOpen
        self.onAbout = onAbout
        super.init()
        if let button = statusItem.button {
            // Template silhouette of the app logo, so it follows the menu bar's light/dark tint.
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("SimpleMapper")
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Open SimpleMapper", #selector(open)))
        let login = item("Launch at login", #selector(toggleLaunchAtLogin))
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        let info = NSMenuItem(title: model.lastError ?? activeText, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        // Input Monitoring is only needed by Detect key; remapping itself needs no permission.
        let granted = detector.hasAccess
        let access = NSMenuItem(title: granted ? "Input Monitoring: granted" : "Input Monitoring: not granted",
                                action: nil, keyEquivalent: "")
        access.isEnabled = false
        menu.addItem(access)
        if !granted {
            menu.addItem(item("Grant Input Monitoring…", #selector(grantAccess)))
        }
        menu.addItem(.separator())
        let update = item(updater.updateAvailable ? "Update Available…" : "Check for Updates…", #selector(checkForUpdates))
        update.isEnabled = updater.canCheck
        menu.addItem(update)
        menu.addItem(item("About SimpleMapper", #selector(about)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "")
        quit.submenu = NSMenu()
        quit.submenu?.addItem(item("Sure to quit", #selector(terminate)))
        menu.addItem(quit)
    }

    private var activeText: String {
        switch model.settings.activeCount(connected: monitor.devices.map(\.scope)) {
        case 0: return "No mappings active"
        case 1: return "1 mapping active"
        case let n: return "\(n) mappings active"
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func open() { onOpen() }
    @objc private func toggleLaunchAtLogin() { model.launchAtLogin.toggle() }
    @objc private func grantAccess() { detector.requestAccess() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func about() { onAbout() }
    @objc private func terminate() { NSApp.terminate(nil) }
}
