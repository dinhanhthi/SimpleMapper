import Combine
import SwiftUI

@main
struct SimpleMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                model: appDelegate.model,
                monitor: appDelegate.monitor,
                detector: appDelegate.detector,
                updater: appDelegate.updater
            )
        } label: {
            // Template silhouette of the app logo, so it follows the menu bar's light/dark tint.
            Image("MenuBarIcon")
                .accessibilityLabel("SimpleMapper")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the app state for the app lifetime. Under unit tests (hosted in the app) it never remaps the keyboard.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model = AppModel()
    let monitor = KeyboardMonitor()
    let detector = KeyDetector()
    let updater = Updater()

    private var devicesSink: AnyCancellable?
    private var sigtermSource: DispatchSourceSignal?

    private var isTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isTesting else { return }
        model.connectedDevices = monitor.devices
        devicesSink = monitor.$devices.sink { [weak self] in self?.model.connectedDevices = $0 }
        monitor.onAttach = { [weak self] in self?.model.apply() }
        // SIGTERM (`killall`, logout) goes through terminate so applicationWillTerminate clears the mapping.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source
        updater.start()
        model.apply()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isTesting else { return }
        detector.stop()
        model.clearOnQuit()
    }
}
