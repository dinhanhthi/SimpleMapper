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

/// The mappings of one keyboard; they win over the All list on the same `from` key. `excluded`: the All list's
/// `from` keys this keyboard does not use (removed from it); written only when not empty.
struct DeviceMappings: Codable, Hashable {
    var device: KeyboardDevice
    var mappings: [Mapping]
    var excluded: [UInt64] = []

    private enum CodingKeys: String, CodingKey { case device, mappings, excluded }

    init(device: KeyboardDevice, mappings: [Mapping], excluded: [UInt64] = []) {
        self.device = device
        self.mappings = mappings
        self.excluded = excluded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        device = try container.decode(KeyboardDevice.self, forKey: .device)
        mappings = try container.decode([Mapping].self, forKey: .mappings)
        excluded = try container.decodeIfPresent([UInt64].self, forKey: .excluded) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(device, forKey: .device)
        try container.encode(mappings, forKey: .mappings)
        if !excluded.isEmpty { try container.encode(excluded, forKey: .excluded) }
    }

    /// Nothing of its own: the keyboard just uses the All list.
    var isEmpty: Bool { mappings.isEmpty && excluded.isEmpty }
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
        for count in [settings.all.count] + settings.keyboards.flatMap({ [$0.mappings.count, $0.excluded.count] })
        where count > maxMappingsPerList {
            throw SettingsError.tooManyMappings(count)
        }
        for device in settings.keyboards.map(\.device) {
            let ids = 0...0xFFFF
            guard ids.contains(device.vendorID) && ids.contains(device.productID) else {
                throw SettingsError.invalidDevice(vendorID: device.vendorID, productID: device.productID)
            }
        }
        let usages = (settings.all + settings.keyboards.flatMap(\.mappings)).flatMap { [$0.from, $0.to] }
            + settings.keyboards.flatMap(\.excluded)
        for usage in usages
        where KeyDetector.acceptedUsage(page: UInt32(usage >> 32), usage: UInt32(usage & 0xFFFF_FFFF)) == nil {
            throw SettingsError.invalidKey(usage)
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
            keyboards[i].excluded += entry.excluded.filter { !keyboards[i].excluded.contains($0) }
            for count in [keyboards[i].mappings.count, keyboards[i].excluded.count] where count > maxMappingsPerList {
                throw SettingsError.tooManyMappings(count)
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

    /// Pretty, key-sorted JSON; keyboards with nothing of their own are dropped.
    func encoded() -> Data {
        var copy = self
        copy.keyboards.removeAll(where: \.isEmpty)
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

    /// The All list's keys `scope` does not use (none for `.all`).
    func excluded(for scope: Scope) -> [UInt64] {
        keyboards.first { $0.device.scope == scope }?.excluded ?? []
    }

    /// The All row for `from` that a keyboard follows: the last enabled one (as hidutil gets), else the first.
    func allMapping(from: UInt64) -> Mapping? {
        all.last { $0.from == from && $0.enabled } ?? all.first { $0.from == from }
    }

    /// Whether the list for `scope` has a card for `from`: a row of its own or, for a keyboard, an All key it uses.
    func shows(_ from: UInt64, in scope: Scope) -> Bool {
        list(for: scope).contains { $0.from == from }
            || scope != .all && allMapping(from: from) != nil && !excluded(for: scope).contains(from)
    }

    /// After a local edit of `from` in `scope`'s own list: `from` is no longer excluded, and a row for it equal to
    /// the All mapping (To and on/off) is dropped, so the keyboard follows All for that key again. Only the edited
    /// key, and never for All changes: an override stays when All later gets the same values.
    mutating func followAll(_ from: UInt64, in scope: Scope) {
        guard scope != .all, let k = keyboards.firstIndex(where: { $0.device.scope == scope }) else { return }
        keyboards[k].excluded.removeAll { $0 == from }
        guard let followed = allMapping(from: from) else { return }
        keyboards[k].mappings.removeAll { $0.from == from && $0.to == followed.to && $0.enabled == followed.enabled }
    }

    /// Removes `mapping` from the All list; once All no longer maps its key, each keyboard's own rows equal to it
    /// (To and on/off: green dots) go too, and rows with other values stay.
    mutating func removeFromAll(_ mapping: Mapping) {
        all.removeAll { $0.id == mapping.id }
        guard allMapping(from: mapping.from) == nil else { return }
        for k in keyboards.indices {
            keyboards[k].mappings.removeAll { $0.from == mapping.from && $0.to == mapping.to && $0.enabled == mapping.enabled }
        }
    }

    /// The keyboards that do not follow the All mapping for `from`: with their own row for it, or that removed it.
    func keyboardsNotFollowingAll(_ from: UInt64) -> [KeyboardDevice] {
        keyboards.filter { $0.mappings.contains { $0.from == from } || $0.excluded.contains(from) }.map(\.device)
    }

    /// Every keyboard follows the All mapping for `from` again: their own rows for it and its exclusions go.
    mutating func applyToAllKeyboards(_ from: UInt64) {
        for k in keyboards.indices {
            keyboards[k].mappings.removeAll { $0.from == from }
            keyboards[k].excluded.removeAll { $0 == from }
        }
    }

    /// Drops excluded keys the All list no longer has or the keyboard has its own row for, then keyboards with
    /// nothing of their own.
    mutating func tidy() {
        let allFroms = Set(all.map(\.from))
        for k in keyboards.indices {
            let own = Set(keyboards[k].mappings.map(\.from))
            keyboards[k].excluded.removeAll { !allFroms.contains($0) || own.contains($0) }
        }
        keyboards.removeAll(where: \.isEmpty)
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

    /// What hidutil gets for `scope`: the All list without its excluded keys, overridden or extended by the
    /// keyboard's own entries. A keyboard entry wins on its `from` key even when disabled: that key is then not
    /// mapped on this keyboard.
    func merged(for scope: Scope) -> [(from: UInt64, to: UInt64)] {
        let allPairs = Self.dedupe(all)
        guard scope != .all else { return allPairs }
        let own = list(for: scope)
        let ownFroms = Set(own.map(\.from))
        let ownPairs = Self.dedupe(own)
        let excluded = Set(excluded(for: scope))
        let kept = allPairs.compactMap { pair in
            ownFroms.contains(pair.from) ? ownPairs.first { $0.from == pair.from }
                : excluded.contains(pair.from) ? nil : pair
        }
        return kept + ownPairs.filter { pair in !allPairs.contains { $0.from == pair.from } }
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
