import AppKit

/// Menu bar item with a plain AppKit menu (no SwiftUI, for footprint). The menu is rebuilt each time it opens.
/// While Sparkle holds an update found by a scheduled check, the logo has a download badge and "Check for Updates…"
/// reads "Update to SimpleMapper <version>…".
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
    private let logo: NSImage?
    private var appearanceObservation: NSKeyValueObservation?

    init(model: AppModel, monitor: KeyboardMonitor, updater: Updater, detector: KeyDetector,
         onOpen: @escaping () -> Void, onAbout: @escaping () -> Void) {
        self.model = model
        self.monitor = monitor
        self.updater = updater
        self.detector = detector
        self.onOpen = onOpen
        self.onAbout = onAbout
        // Template silhouette of the app logo, so it follows the menu bar's light/dark tint.
        let logo = NSImage(named: "MenuBarIcon")
        logo?.isTemplate = true
        self.logo = logo
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updater.onAvailableUpdateChange = { [weak self] in self?.refreshUpdateState() }
        // The badged logo is drawn in the menu bar's tint: redraw it when the menu bar turns light or dark.
        appearanceObservation = statusItem.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshUpdateState() }
        }
        refreshUpdateState()
    }

    /// The template logo, or, while an update waits, the logo with a download badge at its bottom-right corner.
    private func refreshUpdateState() {
        guard let button = statusItem.button else { return }
        guard updater.availableUpdateVersion != nil, let logo else {
            button.image = logo
            button.setAccessibilityLabel("SimpleMapper")
            return
        }
        let badged = NSImage(size: logo.size, flipped: false) { [weak button] rect in
            // A template image drawn here would come out black: fill its shape with the menu bar's text colour.
            (button?.effectiveAppearance ?? .currentDrawing()).performAsCurrentDrawingAppearance {
                let context = NSGraphicsContext.current?.cgContext
                context?.beginTransparencyLayer(auxiliaryInfo: nil)
                logo.draw(in: rect)
                NSColor.labelColor.setFill()
                rect.fill(using: .sourceAtop)
                context?.endTransparencyLayer()
            }
            let badge = NSRect(x: rect.maxX - 9, y: rect.minY, width: 9, height: 9)
            // A white disc, then a bold arrow in a deep green (the system green, 45 % of the way to black).
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badge).fill()
            let green = NSColor.systemGreen.blended(withFraction: 0.45, of: .black) ?? .systemGreen
            let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .black)
                .applying(NSImage.SymbolConfiguration(paletteColors: [green]))
            if let arrow = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration) {
                // Aspect-fit in the disc's inner square, centred.
                let inner = badge.insetBy(dx: 1, dy: 1)
                let size = arrow.size
                let scale = min(inner.width / size.width, inner.height / size.height)
                let fitted = NSSize(width: size.width * scale, height: size.height * scale)
                arrow.draw(in: NSRect(x: badge.midX - fitted.width / 2, y: badge.midY - fitted.height / 2,
                                      width: fitted.width, height: fitted.height))
            }
            return true
        }
        badged.accessibilityDescription = "SimpleMapper, update available"
        button.image = badged
        button.setAccessibilityLabel("SimpleMapper, update available")
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
        let title = updater.availableUpdateVersion.map { "Update to SimpleMapper \($0)…" } ?? "Check for Updates…"
        let update = item(title, #selector(checkForUpdates))
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
