import Foundation
import ServiceManagement

/// App state: the settings (loaded and saved by `SettingsStore`) and what hidutil was given. `init` touches nothing;
/// `start` loads and applies, so the unit-test host never reads or writes real settings.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var settings = Settings.empty
    @Published private(set) var lastError: String?
    /// Updated by the app from `KeyboardMonitor.devices`.
    var connectedDevices: [KeyboardDevice] = []

    private var store: SettingsStore?

    /// Loads the settings, shows any problem and applies them. When the iCloud copy is still downloading, checks
    /// once more later and adopts it if it was restored.
    func start(store: SettingsStore = SettingsStore()) {
        self.store = store
        let (settings, problem) = store.load()
        self.settings = settings
        lastError = problem
        // Settings migrated or kept locally before iCloud Drive had a copy: mirror them once now.
        if !store.restorePending, !store.localLocked, settings != .empty, let cloudURL = store.cloudURL,
           !FileManager.default.fileExists(atPath: cloudURL.path),
           !FileManager.default.fileExists(atPath: cloudURL.deletingLastPathComponent()
               .appendingPathComponent(".settings.json.icloud").path) {
            let saveProblem = store.save(settings)
            lastError = problem ?? saveProblem
        }
        apply()
        guard store.restorePending else { return }
        store.recheckRestore { [weak self] restored, problem in
            guard let self else { return }
            guard restored != nil || problem != nil else {
                if self.lastError == "Restoring settings from iCloud…" {
                    self.lastError = FileManager.default.fileExists(atPath: store.localURL.path)
                        ? nil : "iCloud settings are not downloaded yet; relaunch SimpleMapper to restore them."
                }
                return
            }
            if let restored { self.settings = restored }
            self.lastError = problem
            if restored != nil { self.apply() }
        }
    }

    /// Sends the settings to hidutil. Keeps the current `lastError` unless hidutil fails.
    func apply() {
        guard let store else { return }
        let (commands, applied) = Remapper.applyCommands(settings, previous: store.appliedScopes)
        lastError = Remapper.execute(commands) ?? lastError
        store.appliedScopes = applied
    }

    func clearOnQuit() {
        guard let store else { return }
        _ = Remapper.execute(Remapper.clearCommands(previous: store.appliedScopes))
        store.appliedScopes = []
    }

    /// Adds a mapping to the All list (`device` nil) or to that keyboard's list. The same `from` in that list
    /// replaces its `to` and enables it. Returns whether the mapping was accepted.
    @discardableResult
    func add(from: UInt64, to: UInt64, in device: KeyboardDevice?) -> Bool {
        var candidate = settings
        if let device, listPath(device.scope, in: candidate) == nil {
            guard candidate.keyboards.count < Settings.maxKeyboards else {
                lastError = "At most \(Settings.maxKeyboards) keyboards can have their own mappings."
                return false
            }
            candidate.keyboards.append(DeviceMappings(device: device, mappings: []))
        }
        guard let path = listPath(device?.scope ?? .all, in: candidate) else { return false }
        if let i = candidate[keyPath: path].firstIndex(where: { $0.from == from }) {
            candidate[keyPath: path][i].to = to
            candidate[keyPath: path][i].enabled = true
        } else {
            guard candidate[keyPath: path].count < Settings.maxMappingsPerList else {
                lastError = "At most \(Settings.maxMappingsPerList) mappings per list."
                return false
            }
            candidate[keyPath: path].append(Mapping(from: from, to: to, enabled: true))
        }
        return commit(candidate)
    }

    func remove(_ id: UUID, in scope: Scope) {
        edit(id, in: scope) { $0.remove(at: $1) }
    }

    func setEnabled(_ enabled: Bool, for id: UUID, in scope: Scope) {
        edit(id, in: scope) { $0[$1].enabled = enabled }
    }

    /// Refused when another row of that list already maps `from` (no duplicates in a list).
    func setFrom(_ from: UInt64, for id: UUID, in scope: Scope) {
        guard !settings.list(for: scope).contains(where: { $0.from == from && $0.id != id }) else {
            lastError = "This key is already mapped in this list."
            return
        }
        edit(id, in: scope) { $0[$1].from = from }
    }

    func setTo(_ to: UInt64, for id: UUID, in scope: Scope) {
        edit(id, in: scope) { $0[$1].to = to }
    }

    /// Replaces all settings with a valid settings file.
    func importSettings(from url: URL) throws {
        commit(try Settings.decode(Data(contentsOf: url)))
    }

    func exportSettings(to url: URL) throws {
        try settings.encoded().write(to: url, options: .atomic)
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        lastError = "Approve SimpleMapper in System Settings > General > Login Items"
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// The editable list for `scope` in `settings`; `nil` for a keyboard without a list.
    private func listPath(_ scope: Scope, in settings: Settings) -> WritableKeyPath<Settings, [Mapping]>? {
        guard scope != .all else { return \.all }
        return settings.keyboards.firstIndex { $0.device.scope == scope }.map { \.keyboards[$0].mappings }
    }

    /// Changes the row `id` of the list for `scope` (given the list and the row index), then commits.
    private func edit(_ id: UUID, in scope: Scope, _ change: (inout [Mapping], Int) -> Void) {
        var candidate = settings
        guard let path = listPath(scope, in: candidate),
              let i = candidate[keyPath: path].firstIndex(where: { $0.id == id })
        else { return }
        change(&candidate[keyPath: path], i)
        commit(candidate)
    }

    /// Drops empty keyboard lists, stamps the date and checks the result reads back as a valid file (else only
    /// `lastError` changes, so the next launch never has to move the file aside); then saves and applies.
    /// `false` only when the result is not a valid file (or there is no store).
    @discardableResult
    private func commit(_ candidate: Settings) -> Bool {
        guard let store else { return false }
        guard candidate != settings else { return true }
        var candidate = candidate
        candidate.keyboards.removeAll { $0.mappings.isEmpty }
        candidate.modifiedAt = Date()
        do {
            _ = try Settings.decode(candidate.encoded())
        } catch {
            lastError = error.localizedDescription
            return false
        }
        settings = candidate
        lastError = store.save(candidate)
        apply()
        return true
    }
}
