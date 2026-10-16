import XCTest
@testable import SimpleMapper

final class SettingsTests: XCTestCase {
    private let grave: UInt64 = 0x700000035
    private let backslash: UInt64 = 0x700000064
    private let keyA: UInt64 = 0x700000004
    private let keyB: UInt64 = 0x700000005
    private let fn: UInt64 = 0xFF00000003
    private let keyboard = KeyboardDevice(vendorID: 1452, productID: 832, builtIn: false, name: "Magic Keyboard")

    private func pairs(_ list: [(from: UInt64, to: UInt64)]) -> [[UInt64]] {
        list.map { [$0.from, $0.to] }
    }

    private func rows(_ list: [Mapping]) -> [[UInt64]] {
        list.map { [$0.from, $0.to, $0.enabled ? 1 : 0] }
    }

    private func json(version: Int = 1, from: UInt64 = 0x700000035, to: UInt64 = 0x700000064, inKeyboard: Bool = false) -> Data {
        let mapping = #"{"from": \#(from), "to": \#(to), "enabled": true}"#
        let all = inKeyboard ? "" : mapping
        let keyboards = inKeyboard
            ? #"{"device": {"vendorID": 1, "productID": 2, "builtIn": false, "name": "K"}, "mappings": [\#(mapping)]}"#
            : ""
        return Data(#"{"version": \#(version), "modifiedAt": "2026-10-15T10:00:00Z", "all": [\#(all)], "keyboards": [\#(keyboards)]}"#.utf8)
    }

    private func assertRejects(_ data: Data, with expected: SettingsError, line: UInt = #line) {
        XCTAssertThrowsError(try Settings.decode(data), line: line) { error in
            XCTAssertEqual(error as? SettingsError, expected, line: line)
        }
    }

    func testRoundTripKeepsEverything() throws {
        let settings = Settings(
            modifiedAt: Date(timeIntervalSince1970: 1_760_000_000),
            all: [Mapping(from: grave, to: backslash, enabled: true), Mapping(from: fn, to: keyA, enabled: false)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [Mapping(from: keyA, to: keyB, enabled: true)])]
        )
        let decoded = try Settings.decode(settings.encoded())
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.modifiedAt, settings.modifiedAt)
        XCTAssertEqual(rows(decoded.all), rows(settings.all))
        XCTAssertEqual(decoded.keyboards.map(\.device), [keyboard])
        XCTAssertEqual(rows(decoded.keyboards[0].mappings), [[keyA, keyB, 1]])
        XCTAssertEqual(decoded.encoded(), settings.encoded())
    }

    func testExcludedRoundTripsAndIsOmittedWhenEmpty() throws {
        let settings = Settings(modifiedAt: .distantPast, all: [], keyboards: [
            DeviceMappings(device: keyboard, mappings: [], excluded: [grave]),
        ])
        XCTAssertEqual(try Settings.decode(settings.encoded()).keyboards.map(\.excluded), [[grave]])
        let plain = Settings(modifiedAt: .distantPast, all: [], keyboards: [
            DeviceMappings(device: keyboard, mappings: [Mapping(from: keyA, to: keyB, enabled: true)]),
        ])
        XCTAssertFalse(String(decoding: plain.encoded(), as: UTF8.self).contains("excluded"))
    }

    func testDecodeRejectsInvalidExcludedUsage() {
        let data = Data(#"{"version": 1, "modifiedAt": "2026-10-15T10:00:00Z", "all": [], "keyboards": [{"device": {"vendorID": 1, "productID": 2, "builtIn": false, "name": "K"}, "mappings": [], "excluded": [30064771073]}]}"#.utf8)
        assertRejects(data, with: .invalidKey(0x700000001))
    }

    func testRoundTripKeepsDistantPast() throws {
        XCTAssertEqual(try Settings.decode(Settings.empty.encoded()).modifiedAt, .distantPast)
    }

    func testDecodeAcceptsValidFile() throws {
        XCTAssertEqual(rows(try Settings.decode(json()).all), [[grave, backslash, 1]])
    }

    func testDecodeRejectsVersion2() {
        assertRejects(json(version: 2), with: .unsupportedVersion(2))
        assertRejects(Data(#"{"version": 2}"#.utf8), with: .unsupportedVersion(2))
    }

    func testDecodeRejectsMalformedJSON() {
        XCTAssertThrowsError(try Settings.decode(Data("{not json".utf8))) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testDecodeRejectsErrorCodeUsage() {
        assertRejects(json(from: 0x700000001), with: .invalidKey(0x700000001))
    }

    func testDecodeRejectsConsumerPageUsage() {
        assertRejects(json(to: 0xC000000B5), with: .invalidKey(0xC000000B5))
    }

    func testDecodeRejectsInvalidUsageInKeyboardList() {
        assertRejects(json(from: 0x700000001, inKeyboard: true), with: .invalidKey(0x700000001))
    }

    func testRoundTripIsEqualDespiteNewIDs() throws {
        let settings = Settings(
            modifiedAt: Date(timeIntervalSince1970: 1_760_000_000.5),
            all: [Mapping(from: grave, to: backslash, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [Mapping(from: keyA, to: keyB, enabled: false)])]
        )
        let decoded = try Settings.decode(settings.encoded())
        XCTAssertNotEqual(decoded.all[0].id, settings.all[0].id)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(Set(decoded.all), Set(settings.all))
    }

    /// A file with `keyboards` devices, each with `mappings` A→B rows, and `all` rows in the All list.
    private func file(keyboards: [(vendorID: Int, productID: Int, builtIn: Bool, name: String)], mappings: Int = 1, all: Int = 0) -> Data {
        let row = #"{"from": \#(keyA), "to": \#(keyB), "enabled": true}"#
        let rows = { (count: Int) in Array(repeating: row, count: count).joined(separator: ",") }
        let devices = keyboards.map { device -> String in
            let name = String(data: try! JSONEncoder().encode(device.name), encoding: .utf8)!
            return #"{"device": {"vendorID": \#(device.vendorID), "productID": \#(device.productID), "builtIn": \#(device.builtIn), "name": \#(name)}, "mappings": [\#(rows(mappings))]}"#
        }
        return Data(#"{"version": 1, "modifiedAt": "2026-10-15T10:00:00Z", "all": [\#(rows(all))], "keyboards": [\#(devices.joined(separator: ","))]}"#.utf8)
    }

    func testDecodeRejectsFileOverOneMegabyte() {
        assertRejects(Data(count: (1 << 20) + 1), with: .fileTooLarge((1 << 20) + 1))
    }

    func testDecodeRejectsTooManyKeyboards() throws {
        let devices = (1...65).map { (vendorID: $0, productID: 1, builtIn: false, name: "K") }
        assertRejects(file(keyboards: devices), with: .tooManyKeyboards(65))
        XCTAssertEqual(try Settings.decode(file(keyboards: Array(devices.prefix(64)))).keyboards.count, 64)
    }

    func testDecodeRejectsTooManyMappings() throws {
        assertRejects(file(keyboards: [], all: 257), with: .tooManyMappings(257))
        assertRejects(file(keyboards: [(1, 2, false, "K")], mappings: 257), with: .tooManyMappings(257))
        XCTAssertEqual(try Settings.decode(file(keyboards: [(1, 2, false, "K")], mappings: 256, all: 256)).all.count, 256)
    }

    func testDecodeRejectsOutOfRangeDeviceIDs() throws {
        assertRejects(file(keyboards: [(0x10000, 2, false, "K")]), with: .invalidDevice(vendorID: 0x10000, productID: 2))
        assertRejects(file(keyboards: [(1, -1, false, "K")]), with: .invalidDevice(vendorID: 1, productID: -1))
        XCTAssertNoThrow(try Settings.decode(file(keyboards: [(0xFFFF, 0, false, "K")])))
        assertRejects(file(keyboards: [(-5, 0x10000, true, "Built-in")]), with: .invalidDevice(vendorID: -5, productID: 0x10000))
    }

    func testDecodeRejectsDuplicateKeyboards() {
        assertRejects(file(keyboards: [(1, 2, false, "K"), (1, 2, false, "K2")]), with: .duplicateKeyboard("K2"))
        XCTAssertNoThrow(try Settings.decode(file(keyboards: [(1, 2, false, "K"), (1, 2, true, "K2")])))
    }

    func testDecodeNormalizesBuiltInIDs() throws {
        let decoded = try Settings.decode(file(keyboards: [(0x5AC, 0x27E, true, "Built-in")]))
        XCTAssertEqual(decoded.keyboards.map(\.device), [KeyboardDevice(vendorID: 0, productID: 0, builtIn: true, name: "Built-in")])
    }

    func testDecodeMergesBuiltInKeyboardsFromDifferentMacs() throws {
        let row = { (from: UInt64, to: UInt64) in #"{"from": \#(from), "to": \#(to), "enabled": true}"# }
        let device = { (vendorID: Int, name: String) in
            #"{"vendorID": \#(vendorID), "productID": \#(vendorID), "builtIn": true, "name": "\#(name)"}"#
        }
        let data = Data(#"""
        {"version": 1, "modifiedAt": "2026-10-15T10:00:00Z", "all": [], "keyboards": [
          {"device": \#(device(0, "Apple Silicon")), "mappings": [\#(row(keyA, keyB))]},
          {"device": \#(device(0x5AC, "Intel")), "mappings": [\#(row(keyA, grave)), \#(row(keyB, keyA))]}
        ]}
        """#.utf8)
        let decoded = try Settings.decode(data)
        XCTAssertEqual(decoded.keyboards.map(\.device), [KeyboardDevice(vendorID: 0, productID: 0, builtIn: true, name: "Apple Silicon")])
        XCTAssertEqual(rows(decoded.keyboards[0].mappings), [[keyA, keyB, 1], [keyB, keyA, 1]])
    }

    func testDecodeRejectsMergedBuiltInListOverCap() {
        let row = { (from: UInt64) in #"{"from": \#(from), "to": \#(0x700000004 as UInt64), "enabled": true}"# }
        let data = { (firstCount: Int) in
            Data(#"""
            {"version": 1, "modifiedAt": "2026-10-15T10:00:00Z", "all": [], "keyboards": [
              {"device": {"vendorID": 0, "productID": 0, "builtIn": true, "name": "A"}, "mappings": [\#(Array(repeating: row(self.keyA), count: firstCount).joined(separator: ","))]},
              {"device": {"vendorID": 1, "productID": 1, "builtIn": true, "name": "B"}, "mappings": [\#(row(self.keyB))]}
            ]}
            """#.utf8)
        }
        assertRejects(data(256), with: .tooManyMappings(257))
        XCTAssertEqual(try Settings.decode(data(255)).keyboards.first?.mappings.count, 256)
    }

    func testDecodeStripsFormatCharactersFromNames() throws {
        let name = "\u{202E}Evil\u{202A}\u{202D}\u{2066}\u{2069} Key\u{200B}\u{200D}\u{200F}board\u{FEFF}"
        let decoded = try Settings.decode(file(keyboards: [(1, 2, false, name)]))
        XCTAssertEqual(decoded.keyboards[0].device.name, "Evil Keyboard")
    }

    func testDecodeCleansDeviceName() throws {
        let long = String(repeating: "é", count: 200)
        let decoded = try Settings.decode(file(keyboards: [(1, 2, false, "Magic\n\u{0}Key\u{7F}board\u{200E}"), (3, 4, false, long)]))
        XCTAssertEqual(decoded.keyboards[0].device.name, "MagicKeyboard")
        XCTAssertEqual(decoded.keyboards[1].device.name, String(repeating: "é", count: 128))
    }

    func testEncodedDropsEmptyKeyboardLists() throws {
        let empty = KeyboardDevice(vendorID: 1, productID: 2, builtIn: false, name: "Empty")
        let settings = Settings(modifiedAt: .distantPast, all: [], keyboards: [
            DeviceMappings(device: empty, mappings: []),
            DeviceMappings(device: keyboard, mappings: [Mapping(from: keyA, to: keyB, enabled: true)]),
        ])
        XCTAssertEqual(try Settings.decode(settings.encoded()).keyboards.map(\.device), [keyboard])
    }

    func testDedupeKeepsLastEnabledInFirstOrder() {
        let list = [
            Mapping(from: keyA, to: keyB, enabled: true),
            Mapping(from: grave, to: backslash, enabled: true),
            Mapping(from: keyA, to: fn, enabled: true),
            Mapping(from: keyA, to: grave, enabled: false),
            Mapping(from: keyB, to: keyA, enabled: false),
        ]
        XCTAssertEqual(pairs(Settings.dedupe(list)), [[keyA, fn], [grave, backslash]])
    }

    func testListForScope() {
        let settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: backslash, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [Mapping(from: keyA, to: keyB, enabled: true)])]
        )
        XCTAssertEqual(rows(settings.list(for: .all)), [[grave, backslash, 1]])
        XCTAssertEqual(rows(settings.list(for: keyboard.scope)), [[keyA, keyB, 1]])
        XCTAssertTrue(settings.list(for: .device(vendorID: 9, productID: 9, builtIn: false)).isEmpty)
    }

    func testMergedDeviceWinsAndAppends() {
        let settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: backslash, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [
                Mapping(from: keyA, to: fn, enabled: true),
                Mapping(from: keyB, to: keyA, enabled: true),
            ])]
        )
        XCTAssertEqual(pairs(settings.merged(for: keyboard.scope)), [[grave, backslash], [keyA, fn], [keyB, keyA]])
        XCTAssertEqual(pairs(settings.merged(for: .all)), [[grave, backslash], [keyA, keyB]])
        XCTAssertEqual(pairs(settings.merged(for: .device(vendorID: 9, productID: 9, builtIn: false))), [[grave, backslash], [keyA, keyB]])
    }

    func testDisabledDeviceRowUnmapsTheAllKeyOnThatKeyboard() {
        let settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: backslash, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [Mapping(from: grave, to: backslash, enabled: false)])]
        )
        XCTAssertEqual(pairs(settings.merged(for: keyboard.scope)), [[keyA, keyB]])
        XCTAssertEqual(Remapper.applyCommands(settings, previous: []).applied, [keyboard.scope])
    }

    func testExcludedAllKeyIsNotMappedOnThatKeyboard() {
        let settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: backslash, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [], excluded: [grave])]
        )
        XCTAssertEqual(pairs(settings.merged(for: keyboard.scope)), [[keyA, keyB]])
        XCTAssertEqual(pairs(settings.merged(for: .all)), [[grave, backslash], [keyA, keyB]])
        XCTAssertEqual(Remapper.applyCommands(settings, previous: []).applied, [keyboard.scope])
    }

    func testFollowAllDropsOnlyTheEditedRowWhenEqualToAll() {
        var settings = Settings(
            modifiedAt: .distantPast,
            // All was changed to grave → keyA after the keyboard overrode it with the same value.
            all: [Mapping(from: grave, to: keyA, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [
                Mapping(from: grave, to: keyA, enabled: true),
                Mapping(from: keyA, to: keyB, enabled: true),
            ], excluded: [fn])]
        )
        settings.followAll(keyA, in: keyboard.scope)
        XCTAssertEqual(rows(settings.list(for: keyboard.scope)), [[grave, keyA, 1]])
        settings.followAll(grave, in: .all)
        XCTAssertEqual(rows(settings.list(for: keyboard.scope)), [[grave, keyA, 1]])
        settings.followAll(fn, in: keyboard.scope)
        XCTAssertEqual(settings.excluded(for: keyboard.scope), [])
    }

    func testFollowAllKeepsARowThatDiffersInToOrSwitch() {
        var settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: keyA, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [
                Mapping(from: grave, to: keyB, enabled: true),
                Mapping(from: keyA, to: keyB, enabled: false),
            ])]
        )
        settings.followAll(grave, in: keyboard.scope)
        settings.followAll(keyA, in: keyboard.scope)
        XCTAssertEqual(rows(settings.list(for: keyboard.scope)), [[grave, keyB, 1], [keyA, keyB, 0]])
    }

    func testShowsOwnRowsAndTheAllKeysAKeyboardUses() {
        let settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: keyA, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [Mapping(from: fn, to: keyA, enabled: true)],
                                       excluded: [keyA])]
        )
        XCTAssertTrue(settings.shows(grave, in: .all))
        XCTAssertFalse(settings.shows(fn, in: .all))
        XCTAssertTrue(settings.shows(grave, in: keyboard.scope))
        XCTAssertTrue(settings.shows(fn, in: keyboard.scope))
        XCTAssertFalse(settings.shows(keyA, in: keyboard.scope))
        XCTAssertFalse(settings.shows(keyB, in: keyboard.scope))
    }

    func testRemoveFromAllDropsEqualKeyboardRowsAndKeepsOverrides() {
        let other = KeyboardDevice(vendorID: 1, productID: 2, builtIn: false, name: "Other")
        let removed = Mapping(from: grave, to: keyA, enabled: true)
        var settings = Settings(
            modifiedAt: .distantPast,
            all: [removed, Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [
                DeviceMappings(device: keyboard, mappings: [Mapping(from: grave, to: keyA, enabled: true)]),
                DeviceMappings(device: other, mappings: [Mapping(from: grave, to: keyB, enabled: true)]),
            ]
        )
        settings.removeFromAll(removed)
        XCTAssertEqual(rows(settings.all), [[keyA, keyB, 1]])
        XCTAssertEqual(rows(settings.list(for: keyboard.scope)), [])
        XCTAssertEqual(rows(settings.list(for: other.scope)), [[grave, keyB, 1]])
    }

    func testApplyToAllKeyboardsDropsOverridesAndExclusionsOfThatKey() {
        let other = KeyboardDevice(vendorID: 1, productID: 2, builtIn: false, name: "Other")
        var settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: keyA, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [
                DeviceMappings(device: keyboard, mappings: [
                    Mapping(from: grave, to: keyB, enabled: true),
                    Mapping(from: keyA, to: fn, enabled: true),
                ]),
                DeviceMappings(device: other, mappings: [], excluded: [grave]),
            ]
        )
        XCTAssertEqual(settings.keyboardsNotFollowingAll(grave), [keyboard, other])
        settings.applyToAllKeyboards(grave)
        XCTAssertEqual(settings.keyboardsNotFollowingAll(grave), [])
        XCTAssertEqual(rows(settings.list(for: keyboard.scope)), [[keyA, fn, 1]])
        XCTAssertEqual(settings.excluded(for: other.scope), [])
    }

    func testTidyDropsStaleOrOverlappingExclusionsAndEmptyKeyboards() {
        let empty = KeyboardDevice(vendorID: 1, productID: 2, builtIn: false, name: "Empty")
        var settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: keyA, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [
                // grave: kept; keyA: has its own row; fn: no longer in All.
                DeviceMappings(device: keyboard, mappings: [Mapping(from: keyA, to: fn, enabled: true)],
                               excluded: [grave, keyA, fn]),
                DeviceMappings(device: empty, mappings: [], excluded: [fn]),
            ]
        )
        settings.tidy()
        XCTAssertEqual(settings.keyboards.map(\.device), [keyboard])
        XCTAssertEqual(settings.excluded(for: keyboard.scope), [grave])
    }

    func testActiveCountDoesNotDoubleCountOverrides() {
        let settings = Settings(
            modifiedAt: .distantPast,
            all: [Mapping(from: grave, to: backslash, enabled: true), Mapping(from: fn, to: keyA, enabled: false)],
            keyboards: [DeviceMappings(device: keyboard, mappings: [
                Mapping(from: grave, to: keyA, enabled: true),
                Mapping(from: keyA, to: keyB, enabled: true),
            ])]
        )
        XCTAssertEqual(settings.activeCount(connected: []), 1)
        XCTAssertEqual(settings.activeCount(connected: [keyboard.scope]), 2)
        XCTAssertEqual(settings.activeCount(connected: [.all, keyboard.scope, keyboard.scope]), 2)
    }

    func testMigratingAllScope() {
        let settings = Settings.migrating(from: grave, to: backslash, enabled: true, scope: .all, savedDevice: keyboard)
        XCTAssertEqual(settings.modifiedAt, .distantPast)
        XCTAssertEqual(rows(settings.all), [[grave, backslash, 1]])
        XCTAssertTrue(settings.keyboards.isEmpty)
    }

    func testMigratingDeviceKeepsSavedDeviceName() {
        let settings = Settings.migrating(from: grave, to: backslash, enabled: true, scope: keyboard.scope, savedDevice: keyboard)
        XCTAssertEqual(settings.modifiedAt, .distantPast)
        XCTAssertTrue(settings.all.isEmpty)
        XCTAssertEqual(settings.keyboards.map(\.device), [keyboard])
        XCTAssertEqual(rows(settings.keyboards[0].mappings), [[grave, backslash, 1]])
    }

    func testMigratingDeviceWithoutMatchingSavedDevice() {
        let scope = Scope.device(vendorID: 7, productID: 8, builtIn: false)
        let settings = Settings.migrating(from: grave, to: backslash, enabled: true, scope: scope, savedDevice: keyboard)
        XCTAssertEqual(settings.keyboards.map(\.device), [KeyboardDevice(vendorID: 7, productID: 8, builtIn: false, name: "Keyboard")])
    }

    func testMigratingDisabledGivesDisabledRow() {
        let settings = Settings.migrating(from: grave, to: backslash, enabled: false, scope: .all, savedDevice: nil)
        XCTAssertEqual(rows(settings.all), [[grave, backslash, 0]])
    }

    func testEmptyHasNoMappings() {
        XCTAssertEqual(Settings.empty.version, 1)
        XCTAssertEqual(Settings.empty.modifiedAt, .distantPast)
        XCTAssertTrue(Settings.empty.all.isEmpty)
        XCTAssertTrue(Settings.empty.keyboards.isEmpty)
    }
}
