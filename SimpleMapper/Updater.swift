import AppKit
import Sparkle

/// Sparkle updater, started only when `SUPublicEDKey` is set (an empty key would show a misconfiguration alert).
/// Background checks (at launch, then every `SUScheduledCheckInterval`) pop no Sparkle dialog while the menu bar item
/// exists (gentle reminders): a found update sets `updateAvailable` for the green update button in the main window,
/// and `availableUpdateVersion` for the menu bar icon's badge and "Update to SimpleMapper <version>…".
@MainActor
final class Updater: NSObject, ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var updateAvailable = false

    /// Version of the update a scheduled check found, until its update session ends.
    private(set) var availableUpdateVersion: String?

    /// Called when `availableUpdateVersion` changes; set by the menu bar item.
    var onAvailableUpdateChange: (() -> Void)?

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        controller.startUpdater()
        canCheck = true
        if controller.updater.automaticallyChecksForUpdates { controller.updater.checkForUpdatesInBackground() }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUUpdaterDelegate {
    /// Also called when automatic updates download in the background without any dialog.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        updateAvailable = false
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate updateItem: SUAppcastItem,
                 state: SPUUserUpdateState) {
        if choice == .skip { updateAvailable = false }
    }
}

extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// The menu bar badge stands in for Sparkle's dialog on background checks; without a menu bar item listening,
    /// Sparkle's own alert shows.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        onAvailableUpdateChange == nil
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        availableUpdateVersion = update.displayVersionString
        onAvailableUpdateChange?()
    }

    /// Install, skip, "Remind Me Later" or an error: the badge goes away.
    func standardUserDriverWillFinishUpdateSession() {
        guard availableUpdateVersion != nil else { return }
        availableUpdateVersion = nil
        onAvailableUpdateChange?()
    }
}
