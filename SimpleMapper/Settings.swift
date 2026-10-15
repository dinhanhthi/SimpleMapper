import Foundation

/// One key mapping. `id` lives in memory only (SwiftUI row identity); it is not written to the file,
/// nor compared or hashed, so a decoded copy equals the original.
struct Mapping: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: UInt64
    var to: UInt64
    var enabled: Bool

    private enum CodingKeys: String, CodingKey { case from, to, enabled }

    static func == (lhs: Mapping, rhs: Mapping) -> Bool {
        lhs.from == rhs.from && lhs.to == rhs.to && lhs.enabled == rhs.enabled
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(from)
        hasher.combine(to)
        hasher.combine(enabled)
    }
}

/// The mappings of one keyboard; they win over the All list on the same `from` key.
struct DeviceMappings: Codable, Hashable {
    var device: KeyboardDevice
    var mappings: [Mapping]
}

/// Everything SimpleMapper saves: the settings file format, version 1.
struct Settings: Codable, Equatable {
    var version = 1
    var modifiedAt: Date
    var all: [Mapping]
    var keyboards: [DeviceMappings]

    /// Fresh install: no mappings. Generated settings are dated `.distantPast`; the date is informational only.
    static let empty = Settings(modifiedAt: .distantPast, all: [], keyboards: [])

    /// ISO-8601 with milliseconds, so two edits within one second stay ordered; whole seconds are still read.
    private static let fractionalDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let wholeSecondDates = ISO8601DateFormatter()

    static let maxFileSize = 1 << 20
    static let maxKeyboards = 64
    static let maxMappingsPerList = 256
    static let maxNameLength = 128

    /// Decodes and validates a settings file: version 1 only, within the size caps, valid and distinct keyboards,
    /// every usage remappable. Keyboard names are cleaned (no control characters, at most 128 characters).
    /// Built-in keyboards get IDs 0/0 and form one entry (several are merged).
    static func decode(_ data: Data) throws -> Settings {
        guard data.count <= maxFileSize else { throw SettingsError.fileTooLarge(data.count) }
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = Self.fractionalDates.date(from: string) ?? Self.wholeSecondDates.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
            }
            return date
        }
        // Checked first, so a newer file is reported as such even if its shape changed.
        let version = try decoder.decode(Header.self, from: data).version
        guard version == 1 else { throw SettingsError.unsupportedVersion(version) }
        var settings = try decoder.decode(Settings.self, from: data)
        guard settings.keyboards.count <= maxKeyboards else { throw SettingsError.tooManyKeyboards(settings.keyboards.count) }
        for list in [settings.all] + settings.keyboards.map(\.mappings) where list.count > maxMappingsPerList {
            throw SettingsError.tooManyMappings(list.count)
        }
        for device in settings.keyboards.map(\.device) {
            let ids = 0...0xFFFF
            guard ids.contains(device.vendorID) && ids.contains(device.productID) else {
                throw SettingsError.invalidDevice(vendorID: device.vendorID, productID: device.productID)
            }
        }
        for mapping in settings.all + settings.keyboards.flatMap(\.mappings) {
            for usage in [mapping.from, mapping.to]
            where KeyDetector.acceptedUsage(page: UInt32(usage >> 32), usage: UInt32(usage & 0xFFFF_FFFF)) == nil {
                throw SettingsError.invalidKey(usage)
            }
        }
        // The built-in keyboard is one scope (hidutil matches it by `Built-In`), whatever IDs a Mac reported.
        var keyboards: [DeviceMappings] = []
        for var entry in settings.keyboards {
            let device = entry.device
            entry.device = KeyboardDevice(
                vendorID: device.builtIn ? 0 : device.vendorID,
                productID: device.builtIn ? 0 : device.productID,
                builtIn: device.builtIn,
                name: cleanName(device.name)
            )
            guard let i = keyboards.firstIndex(where: { $0.device.scope == entry.device.scope }) else {
                keyboards.append(entry)
                continue
            }
            guard entry.device.builtIn else { throw SettingsError.duplicateKeyboard(entry.device.name) }
            // Two built-in entries (from Macs with different IDs): keep the first, add the keys it does not map.
            let froms = Set(keyboards[i].mappings.map(\.from))
            keyboards[i].mappings += entry.mappings.filter { !froms.contains($0.from) }
            guard keyboards[i].mappings.count <= maxMappingsPerList else {
                throw SettingsError.tooManyMappings(keyboards[i].mappings.count)
            }
        }
        settings.keyboards = keyboards
        return settings
    }

    /// Drops control and format characters (Unicode Cc and Cf: bidi overrides, zero-width characters) and keeps
    /// at most `maxNameLength` characters.
    private static func cleanName(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        return String(String(scalars).prefix(maxNameLength))
    }

    /// Pretty, key-sorted JSON; keyboards without mappings are dropped.
    func encoded() -> Data {
        var copy = self
        copy.keyboards.removeAll { $0.mappings.isEmpty }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.fractionalDates.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try! encoder.encode(copy)
    }

    /// The list edited for `scope`: the All list, or that keyboard's list (empty when it has none).
    func list(for scope: Scope) -> [Mapping] {
        guard scope != .all else { return all }
        return keyboards.first { $0.device.scope == scope }?.mappings ?? []
    }

    /// Enabled pairs only; the last enabled entry per `from` wins, in order of first appearance.
    static func dedupe(_ mappings: [Mapping]) -> [(from: UInt64, to: UInt64)] {
        var pairs: [(from: UInt64, to: UInt64)] = []
        var index: [UInt64: Int] = [:]
        for mapping in mappings where mapping.enabled {
            if let i = index[mapping.from] {
                pairs[i].to = mapping.to
            } else {
                index[mapping.from] = pairs.count
                pairs.append((mapping.from, mapping.to))
            }
        }
        return pairs
    }

    /// What hidutil gets for `scope`: the All list, overridden or extended by the keyboard's own entries.
    func merged(for scope: Scope) -> [(from: UInt64, to: UInt64)] {
        var pairs = Self.dedupe(all)
        guard scope != .all else { return pairs }
        for pair in Self.dedupe(list(for: scope)) {
            if let i = pairs.firstIndex(where: { $0.from == pair.from }) {
                pairs[i].to = pair.to
            } else {
                pairs.append(pair)
            }
        }
        return pairs
    }

    /// Active mappings: the All list plus each connected keyboard's extra keys (overrides are not counted twice).
    func activeCount(connected: [Scope]) -> Int {
        let allKeys = Set(Self.dedupe(all).map(\.from))
        var count = allKeys.count
        for scope in Set(connected) where scope != .all {
            count += Self.dedupe(list(for: scope)).filter { !allKeys.contains($0.from) }.count
        }
        return count
    }

    /// Converts the old single mapping (UserDefaults) into settings, dated `.distantPast`.
    static func migrating(from: UInt64, to: UInt64, enabled: Bool, scope: Scope, savedDevice: KeyboardDevice?) -> Settings {
        let mapping = Mapping(from: from, to: to, enabled: enabled)
        guard case let .device(vendorID, productID, builtIn) = scope else {
            return Settings(modifiedAt: .distantPast, all: [mapping], keyboards: [])
        }
        let device = savedDevice.flatMap { $0.scope == scope ? $0 : nil }
            ?? KeyboardDevice(vendorID: vendorID, productID: productID, builtIn: builtIn, name: "Keyboard")
        return Settings(modifiedAt: .distantPast, all: [], keyboards: [DeviceMappings(device: device, mappings: [mapping])])
    }
}

/// Why a settings file was rejected.
enum SettingsError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidKey(UInt64)
    case fileTooLarge(Int)
    case tooManyKeyboards(Int)
    case tooManyMappings(Int)
    case invalidDevice(vendorID: Int, productID: Int)
    case duplicateKeyboard(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            return "This settings file has version \(version), but this SimpleMapper only reads version 1. Update SimpleMapper."
        case let .invalidKey(usage):
            return "This settings file contains a key SimpleMapper can't remap (usage 0x\(String(usage, radix: 16, uppercase: true)))."
        case let .fileTooLarge(size):
            return "This settings file is too large (\(size) bytes; at most \(Settings.maxFileSize))."
        case let .tooManyKeyboards(count):
            return "This settings file has \(count) keyboards; at most \(Settings.maxKeyboards) are allowed."
        case let .tooManyMappings(count):
            return "This settings file has a list of \(count) mappings; at most \(Settings.maxMappingsPerList) per list are allowed."
        case let .invalidDevice(vendorID, productID):
            return "This settings file contains a keyboard with invalid IDs (vendor \(vendorID), product \(productID))."
        case let .duplicateKeyboard(name):
            return "This settings file lists the keyboard \"\(name)\" more than once."
        }
    }
}
