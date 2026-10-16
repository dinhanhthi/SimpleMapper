import AppKit
import Combine
import SwiftUI

/// AppKit entry point: no SwiftUI `App`, so SwiftUI is only loaded inside the main window.
@main
@MainActor
enum SimpleMapperMain {
    // NSApplication.delegate is weak; keep the delegate alive for the app lifetime.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

/// Owns the app state for the app lifetime. Under unit tests (hosted in the app) it never remaps the keyboard.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = AppModel()
    let monitor = KeyboardMonitor()
    let detector = KeyDetector()
    let updater = Updater()

    private var statusMenu: StatusMenu?
    private var window: NSWindow?
    private var devicesSink: AnyCancellable?
    private var sigtermSource: DispatchSourceSignal?

    private var isTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTesting else { return }
        NSApp.mainMenu = makeMainMenu()
        statusMenu = StatusMenu(model: model, monitor: monitor, updater: updater, detector: detector,
                                onOpen: { [weak self] in self?.showMainWindow() },
                                onAbout: { [weak self] in self?.showAbout() })
        model.connectedDevices = monitor.devices
        devicesSink = monitor.$devices.sink { [weak self] in self?.model.connectedDevices = $0 }
        monitor.onAttach = { [weak self] in self?.model.apply() }
        // SIGTERM (`killall`, logout) goes through terminate so applicationWillTerminate clears the mapping.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source
        #if DEBUG
        let demo = ProcessInfo.processInfo.environment["SIMPLEMAPPER_DEMO"] == "1"
        #else
        let demo = false
        #endif
        if !demo { updater.start() }
        model.start()
        #if DEBUG
        // README screenshots (scripts/screenshots.sh): the `-AppleInterfaceStyle Light|Dark` launch argument sets
        // this app's appearance (the system one is never changed), and the About panel opens once launched.
        if ProcessInfo.processInfo.environment["SIMPLEMAPPER_DEMO"] == "1" {
            let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        if ProcessInfo.processInfo.environment["SIMPLEMAPPER_DEMO_ABOUT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showAbout() }
        }
        #endif
        // A login-item launch (or a scripted `--background` start) stays in the menu bar.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if !loginLaunch && !ProcessInfo.processInfo.arguments.contains("--background") {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isTesting else { return }
        detector.stop()
        model.clearOnQuit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: MainView(model: model, monitor: monitor, detector: detector)))
            window.title = "SimpleMapper"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            if !window.setFrameAutosaveName("Main") || !window.setFrameUsingName("Main") {
                window.center()
            }
            window.delegate = self
            self.window = window
        }
        bringToFront(window)
    }

    /// Shows the Dock icon and activates the app on the next turn (the `.regular` switch from LSUIElement is
    /// not effective before), then fronts `window`. On macOS 14+ a plain `activate()` is denied on a fresh launch
    /// from LSUIElement; the `ignoringOtherApps:` form is still honored.
    private func bringToFront(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        detector.stop()
        detector.detected = nil
        detector.hint = nil
        // Release the window and its SwiftUI hierarchy after it finishes closing; it is recreated on the next open.
        DispatchQueue.main.async { [weak self] in
            self?.window = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func showAbout() {
        if window == nil {
            // No main window: drop the Dock icon again once the user leaves the app.
            NotificationCenter.default.addObserver(self, selector: #selector(resignedActiveAfterAbout),
                                                   name: NSApplication.didResignActiveNotification, object: nil)
        }
        bringToFront(nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let url = "https://github.com/dinhanhthi/SimpleMapper"
        let credits = NSMutableAttributedString(string: "A lightweight key remapper for macOS.\n\(url)\nMIT License",
                                                attributes: [.font: font, .paragraphStyle: paragraph])
        credits.addAttribute(.link, value: url, range: (credits.string as NSString).range(of: url))
        // Queued after bringToFront's activation.
        DispatchQueue.main.async {
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationIcon: NSImage(named: "AboutLogo") as Any,
                .credits: credits,
            ])
        }
    }

    @objc private func resignedActiveAfterAbout() {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
        if window == nil { NSApp.setActivationPolicy(.accessory) }
    }

    /// App menu (About, Hide, Quit), Edit and Window menus so text fields and shortcuts work in the window.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About SimpleMapper", action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide SimpleMapper", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit SimpleMapper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.windowsMenu = windowMenu
        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
