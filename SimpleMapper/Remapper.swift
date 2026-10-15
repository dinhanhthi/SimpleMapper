import Foundation

/// Which keyboards a mapping applies to.
enum Scope: Codable, Hashable {
    case all
    case device(vendorID: Int, productID: Int, builtIn: Bool)
}

/// Applies key mappings with `/usr/bin/hidutil property --set UserKeyMapping`.
enum Remapper {
    static let clearJSON = #"{"UserKeyMapping":[]}"#

    static func mappingJSON(_ pairs: [(from: UInt64, to: UInt64)]) -> String {
        json(["UserKeyMapping": pairs.map { ["HIDKeyboardModifierMappingSrc": $0.from, "HIDKeyboardModifierMappingDst": $0.to] }])
    }

    /// `nil` for `.all`; built-in keyboards are matched by `Built-In`, others by vendor/product.
    static func matchingJSON(_ scope: Scope) -> String? {
        guard case let .device(vendorID, productID, builtIn) = scope else { return nil }
        if builtIn {
            return json(["Built-In": 1, "PrimaryUsagePage": 1, "PrimaryUsage": 6])
        }
        return json(["VendorID": vendorID, "ProductID": productID, "PrimaryUsagePage": 1, "PrimaryUsage": 6])
    }

    static func arguments(set json: String, scope: Scope) -> [String] {
        guard let matching = matchingJSON(scope) else { return ["property", "--set", json] }
        return ["property", "--matching", matching, "--set", json]
    }

    /// Global All list first, then the merged list of every previous or mapped keyboard (a stale one gets the All list).
    /// `applied` is the keyboards with at least one enabled mapping.
    static func applyCommands(_ settings: Settings, previous: Set<Scope>) -> (commands: [[String]], applied: Set<Scope>) {
        let applied = Set(settings.keyboards.map(\.device.scope).filter { $0 != .all && !Settings.dedupe(settings.list(for: $0)).isEmpty })
        let deviceCommands = sorted(previous.union(applied)).map { arguments(set: mappingJSON(settings.merged(for: $0)), scope: $0) }
        return ([arguments(set: mappingJSON(Settings.dedupe(settings.all)), scope: .all)] + deviceCommands, applied)
    }

    /// Clears the global mapping, then every previous keyboard.
    static func clearCommands(previous: Set<Scope>) -> [[String]] {
        [arguments(set: clearJSON, scope: .all)] + sorted(previous).map { arguments(set: clearJSON, scope: $0) }
    }

    /// Runs every command in order. Returns the first error text or nil.
    static func execute(_ commands: [[String]], runner: ([String]) -> String? = Remapper.run) -> String? {
        commands.map(runner).compactMap { $0 }.first
    }

    /// Device scopes only, in a stable order: built-in first, then by vendor and product.
    private static func sorted(_ scopes: Set<Scope>) -> [Scope] {
        scopes.compactMap { scope -> (key: [Int], scope: Scope)? in
            guard case let .device(vendorID, productID, builtIn) = scope else { return nil }
            return ([builtIn ? 0 : 1, vendorID, productID], scope)
        }
        .sorted { $0.key.lexicographicallyPrecedes($1.key) }
        .map(\.scope)
    }

    private static func json(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }

    static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return error.localizedDescription
        }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "hidutil exited with status \(process.terminationStatus)" : message
    }
}
