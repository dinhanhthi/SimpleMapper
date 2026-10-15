import Foundation
import ServiceManagement

/// App state persisted in UserDefaults. Only `fromUsage`, `toUsage`, `scope` and `enabled` call `apply()`;
/// `savedDevice` and `lastAppliedScope` only persist, so `apply()` setting `lastAppliedScope` cannot recurse.
@MainActor
final class AppModel: ObservableObject {
    enum Slot { case from, to }

    @Published var fromUsage: UInt64 { didSet { save(fromUsage, "fromUsage"); apply() } }
    @Published var toUsage: UInt64 { didSet { save(toUsage, "toUsage"); apply() } }
    @Published var scope: Scope { didSet { save(scope, "scope"); apply() } }
    @Published var enabled: Bool { didSet { save(enabled, "enabled"); apply() } }
    @Published var savedDevice: KeyboardDevice? { didSet { save(savedDevice, "savedDevice") } }
    @Published private(set) var status = ""
    /// Updated by the app from `KeyboardMonitor.devices`.
    var connectedDevices: [KeyboardDevice] = []

    private var lastAppliedScope: Scope? { didSet { save(lastAppliedScope, "lastAppliedScope") } }
    private let defaults = UserDefaults.standard

    /// Property observers do not run for assignments in `init`, so loading never calls `apply()`.
    init() {
        fromUsage = Self.load("fromUsage") ?? KeyCatalog.defaultFrom
        toUsage = Self.load("toUsage") ?? KeyCatalog.defaultTo
        scope = Self.load("scope") ?? .all
        enabled = Self.load("enabled") ?? true
        savedDevice = Self.load("savedDevice")
        lastAppliedScope = Self.load("lastAppliedScope")
    }

    func apply() {
        guard enabled else {
            let error = Remapper.clear(previous: lastAppliedScope)
            lastAppliedScope = nil
            status = error ?? "Off"
            return
        }
        let error = Remapper.apply(from: fromUsage, to: toUsage, scope: scope, previous: lastAppliedScope)
        lastAppliedScope = scope
        status = error ?? "Active: \(label(fromUsage)) → \(label(toUsage)) on \(scopeName)"
    }

    func clearOnQuit() {
        _ = Remapper.clear(previous: lastAppliedScope)
        lastAppliedScope = nil
    }

    func use(_ detected: DetectedKey, as slot: Slot) {
        switch slot {
        case .from: fromUsage = detected.usage
        case .to: toUsage = detected.usage
        }
    }

    /// Sets `savedDevice` first (no apply), then `scope`, so hidutil runs once.
    func useKeyboard(_ device: KeyboardDevice) {
        savedDevice = device
        scope = device.scope
    }

    func useAllKeyboards() {
        scope = .all
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        status = "Approve SimpleMapper in System Settings > General > Login Items"
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private var scopeName: String {
        guard scope != .all else { return "All keyboards" }
        let connected = connectedDevices.first { $0.scope == scope }
        let name = connected?.name ?? (savedDevice?.scope == scope ? savedDevice?.name : nil) ?? "Keyboard"
        return connected == nil ? "\(name) (not connected)" : name
    }

    private func label(_ usage: UInt64) -> String {
        KeyCatalog.key(usage: usage)?.label ?? String(format: "0x%llX", usage)
    }

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
