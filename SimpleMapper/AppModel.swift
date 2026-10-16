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
    /// Runs one hidutil command (no-op in demo mode).
    private var runner: ([String]) -> String? = Remapper.run

    /// Loads the settings, shows any problem and applies them. When the iCloud copy is still downloading, checks
    /// once more later and adopts it if it was restored.
    func start(store: SettingsStore = SettingsStore()) {
        #if DEBUG
        let store = demoStore() ?? store
        #endif
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
        lastError = Remapper.execute(commands, runner: runner) ?? lastError
        store.appliedScopes = applied
    }

    func clearOnQuit() {
        guard let store else { return }
        _ = Remapper.execute(Remapper.clearCommands(previous: store.appliedScopes), runner: runner)
        store.appliedScopes = []
    }

    #if DEBUG
    /// Demo mode for the README screenshots (`SIMPLEMAPPER_DEMO=1`, Debug builds only): fixed settings in a fresh
    /// temp folder, iCloud off, and hidutil is never run, so the user's settings and keyboard are untouched.
    private func demoStore() -> SettingsStore? {
        guard ProcessInfo.processInfo.environment["SIMPLEMAPPER_DEMO"] == "1" else { return nil }
        runner = { _ in nil }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimpleMapperDemo-\(UUID().uuidString)", isDirectory: true)
        let store = SettingsStore(localDir: root.appendingPathComponent("local", isDirectory: true),
                                  cloudRoot: root.appendingPathComponent("no-icloud", isDirectory: true),
                                  defaults: UserDefaults(suiteName: "SimpleMapperDemo-\(UUID().uuidString)")!)
        func mapping(_ from: String, _ to: String, enabled: Bool = true) -> Mapping {
            Mapping(from: KeyCatalog.key(name: from)!.usage, to: KeyCatalog.key(name: to)!.usage, enabled: enabled)
        }
        let keychron = KeyboardDevice(vendorID: 0x05AC, productID: 0x0250, builtIn: false, name: "Keychron K8")
        _ = store.save(Settings(modifiedAt: Date(), all: [
            mapping("caps_lock", "escape"),
            mapping("non_us_backslash", "grave_accent_and_tilde"),
            mapping("right_option", "fn", enabled: false),
        ], keyboards: [DeviceMappings(device: keychron, mappings: [mapping("right_command", "right_control")])]))
        return store
    }
    #endif

    /// Adds a mapping to the All list (`device` nil) or to that keyboard's list; refused when that list already
    /// shows `from` (`Settings.shows`). Returns whether the mapping was accepted.
    @discardableResult
    func add(from: UInt64, to: UInt64, in device: KeyboardDevice?) -> Bool {
        guard !settings.shows(from, in: device?.scope ?? .all) else {
            lastError = "This key is already mapped in this list."
            return false
        }
        return override(from: from, to: to, enabled: true, in: device)
    }

    /// Sets the row for `from` in the All list (`device` nil) or that keyboard's own list, adding it if needed; a
    /// keyboard row equal to the All mapping is not kept (`Settings.followAll`).
    @discardableResult
    func override(from: UInt64, to: UInt64, enabled: Bool, in device: KeyboardDevice?) -> Bool {
        var candidate = settings
        if let device, !addKeyboard(device, to: &candidate) { return false }
        guard let path = listPath(device?.scope ?? .all, in: candidate) else { return false }
        if let i = candidate[keyPath: path].firstIndex(where: { $0.from == from }) {
            candidate[keyPath: path][i].to = to
            candidate[keyPath: path][i].enabled = enabled
        } else {
            guard candidate[keyPath: path].count < Settings.maxMappingsPerList else {
                lastError = "At most \(Settings.maxMappingsPerList) mappings per list."
                return false
            }
            candidate[keyPath: path].append(Mapping(from: from, to: to, enabled: enabled))
        }
        if let device { candidate.followAll(from, in: device.scope) }
        return commit(candidate)
    }

    /// Removing an All row also removes, on every keyboard, its own rows with the same values (green dots); rows
    /// with other values (gray dots) stay.
    func remove(_ id: UUID, in scope: Scope) {
        guard scope == .all, let removed = settings.all.first(where: { $0.id == id }) else {
            edit(id, in: scope) { $0.remove(at: $1) }
            return
        }
        var candidate = settings
        candidate.removeFromAll(removed)
        commit(candidate)
    }

    /// The keyboard no longer maps `from`: its own row for it is removed and the All mapping for it is not used
    /// there, until `from` is added to this keyboard again.
    func exclude(_ from: UInt64, in device: KeyboardDevice) {
        var candidate = settings
        guard addKeyboard(device, to: &candidate),
              let k = candidate.keyboards.firstIndex(where: { $0.device.scope == device.scope })
        else { return }
        candidate.keyboards[k].mappings.removeAll { $0.from == from }
        if !candidate.keyboards[k].excluded.contains(from) { candidate.keyboards[k].excluded.append(from) }
        commit(candidate)
    }

    /// Every keyboard follows the All mapping for `from` again (`Settings.applyToAllKeyboards`).
    func applyToAllKeyboards(_ from: UInt64) {
        var candidate = settings
        candidate.applyToAllKeyboards(from)
        commit(candidate)
    }

    /// The keyboard follows the All mapping for `from` again: its own row for it is removed.
    func useAll(_ from: UInt64, in scope: Scope) {
        var candidate = settings
        guard scope != .all, let k = candidate.keyboards.firstIndex(where: { $0.device.scope == scope }) else { return }
        candidate.keyboards[k].mappings.removeAll { $0.from == from }
        candidate.keyboards[k].excluded.removeAll { $0 == from }
        commit(candidate)
    }

    func setEnabled(_ enabled: Bool, for id: UUID, in scope: Scope) {
        edit(id, in: scope) { $0[$1].enabled = enabled }
    }

    /// Refused when the list already shows `from` (`Settings.shows`). For a keyboard, the card becomes its own row
    /// (it may follow All again, see `Settings.followAll`), and the All mapping for the old key is excluded there,
    /// so it does not come back as another card.
    func setFrom(_ from: UInt64, for mapping: Mapping, in device: KeyboardDevice?) {
        guard from != mapping.from else { return }
        let scope = device?.scope ?? .all
        guard !settings.shows(from, in: scope) else {
            lastError = "This key is already mapped in this list."
            return
        }
        guard let device else {
            edit(mapping.id, in: .all) { $0[$1].from = from }
            return
        }
        var candidate = settings
        guard addKeyboard(device, to: &candidate),
              let k = candidate.keyboards.firstIndex(where: { $0.device.scope == scope })
        else { return }
        if let i = candidate.keyboards[k].mappings.firstIndex(where: { $0.id == mapping.id }) {
            candidate.keyboards[k].mappings[i].from = from
        } else {
            guard candidate.keyboards[k].mappings.count < Settings.maxMappingsPerList else {
                lastError = "At most \(Settings.maxMappingsPerList) mappings per list."
                return
            }
            candidate.keyboards[k].mappings.append(Mapping(from: from, to: mapping.to, enabled: mapping.enabled))
        }
        if candidate.allMapping(from: mapping.from) != nil, !candidate.keyboards[k].excluded.contains(mapping.from) {
            candidate.keyboards[k].excluded.append(mapping.from)
        }
        candidate.followAll(from, in: scope)
        commit(candidate)
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
        // The edited row's key, if it is still there (not after a remove).
        if let from = candidate[keyPath: path].first(where: { $0.id == id })?.from { candidate.followAll(from, in: scope) }
        commit(candidate)
    }

    /// Adds an empty entry for `device` unless it has one; `false` when there are too many keyboards.
    private func addKeyboard(_ device: KeyboardDevice, to candidate: inout Settings) -> Bool {
        guard !candidate.keyboards.contains(where: { $0.device.scope == device.scope }) else { return true }
        guard candidate.keyboards.count < Settings.maxKeyboards else {
            lastError = "At most \(Settings.maxKeyboards) keyboards can have their own mappings."
            return false
        }
        candidate.keyboards.append(DeviceMappings(device: device, mappings: []))
        return true
    }

    /// Tidies the keyboard entries (`Settings.tidy`), stamps the date and checks the result reads back as a valid file (else only
    /// `lastError` changes, so the next launch never has to move the file aside); then saves and applies.
    /// `false` only when the result is not a valid file (or there is no store).
    @discardableResult
    private func commit(_ candidate: Settings) -> Bool {
        guard let store else { return false }
        guard candidate != settings else { return true }
        var candidate = candidate
        candidate.tidy()
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
