import AppKit
import Sparkle

/// Sparkle updater, started only when `SUPublicEDKey` is set (an empty key would show a misconfiguration alert).
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var canCheck = false

    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.startUpdater()
        canCheck = true
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
