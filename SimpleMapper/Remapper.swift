import Foundation

/// Which keyboards a mapping applies to.
enum Scope: Codable, Hashable {
    case all
    case device(vendorID: Int, productID: Int, builtIn: Bool)
}

/// Applies one key mapping with `/usr/bin/hidutil property --set UserKeyMapping`.
enum Remapper {
    static let clearJSON = #"{"UserKeyMapping":[]}"#

    static func mappingJSON(from: UInt64, to: UInt64) -> String {
        json(["UserKeyMapping": [["HIDKeyboardModifierMappingSrc": from, "HIDKeyboardModifierMappingDst": to]]])
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

    /// Clears the global and previous device mapping, then sets the new one. Returns error text or nil.
    static func apply(from: UInt64, to: UInt64, scope: Scope, previous: Scope?) -> String? {
        let clearError = clear(previous: previous)
        return run(arguments(set: mappingJSON(from: from, to: to), scope: scope)) ?? clearError
    }

    /// Clears the global mapping and, when it was a device, the previous scope. Returns error text or nil.
    static func clear(previous: Scope?) -> String? {
        let globalError = run(arguments(set: clearJSON, scope: .all))
        guard let previous, previous != .all else { return globalError }
        let previousError = run(arguments(set: clearJSON, scope: previous))
        return globalError ?? previousError
    }

    private static func json(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
        return String(decoding: data, as: UTF8.self)
    }

    private static func run(_ arguments: [String]) -> String? {
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
