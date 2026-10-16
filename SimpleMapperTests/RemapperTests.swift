import XCTest
@testable import SimpleMapper

final class RemapperTests: XCTestCase {
    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private let grave: UInt64 = 0x700000035
    private let backslash: UInt64 = 0x700000064
    private let keyA: UInt64 = 0x700000004
    private let keyB: UInt64 = 0x700000005
    private let builtIn = KeyboardDevice(vendorID: 0, productID: 0, builtIn: true, name: "Built-in Keyboard")
    private let magic = KeyboardDevice(vendorID: 1452, productID: 832, builtIn: false, name: "Magic Keyboard")

    private func pairs(_ json: String) throws -> [[UInt64]] {
        let mappings = try XCTUnwrap(object(json)["UserKeyMapping"] as? [[String: Any]])
        return try mappings.map {
            [try XCTUnwrap(($0["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value),
             try XCTUnwrap(($0["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value)]
        }
    }

    private func settings(all: [Mapping], keyboards: [DeviceMappings] = []) -> Settings {
        Settings(modifiedAt: Date(), all: all, keyboards: keyboards)
    }

    func testMappingJSONRoundTrips() throws {
        let json = Remapper.mappingJSON([(from: 0x700000064, to: 0x700000035)])
        let mappings = try XCTUnwrap(object(json)["UserKeyMapping"] as? [[String: Any]])
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual((mappings[0]["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value, 30064771172)
        XCTAssertEqual((mappings[0]["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value, 30064771125)
    }

    func testMappingJSONKeepsEveryPairInOrder() throws {
        let json = Remapper.mappingJSON([(from: backslash, to: grave), (from: keyA, to: keyB)])
        XCTAssertEqual(try pairs(json), [[backslash, grave], [keyA, keyB]])
    }

    func testApplyStartsWithTheGlobalAllList() throws {
        let plan = Remapper.applyCommands(settings(all: [Mapping(from: backslash, to: grave, enabled: true)]), previous: [])
        XCTAssertEqual(plan.commands.count, 1)
        XCTAssertEqual(plan.commands[0].prefix(2), ["property", "--set"])
        XCTAssertEqual(try pairs(plan.commands[0][2]), [[backslash, grave]])
        XCTAssertEqual(plan.applied, [])
    }

    func testEmptyAllListSetsAnEmptyGlobalMapping() {
        let plan = Remapper.applyCommands(settings(all: [Mapping(from: backslash, to: grave, enabled: false)]), previous: [])
        XCTAssertEqual(plan.commands, [["property", "--set", #"{"UserKeyMapping":[]}"#]])
    }

    func testDeviceScopeGetsTheMergedListWithMatching() throws {
        let value = settings(
            all: [Mapping(from: backslash, to: grave, enabled: true), Mapping(from: keyA, to: keyB, enabled: true)],
            keyboards: [DeviceMappings(device: magic, mappings: [Mapping(from: keyA, to: grave, enabled: true)])]
        )
        let plan = Remapper.applyCommands(value, previous: [])
        XCTAssertEqual(plan.commands.count, 2)
        XCTAssertEqual(try pairs(plan.commands[0][2]), [[backslash, grave], [keyA, keyB]])
        let device = plan.commands[1]
        XCTAssertEqual(device[1], "--matching")
        XCTAssertEqual(device[2], Remapper.matchingJSON(magic.scope))
        XCTAssertEqual(device[3], "--set")
        XCTAssertEqual(try pairs(device[4]), [[backslash, grave], [keyA, grave]])
    }

    func testStalePreviousScopeGetsTheAllList() throws {
        let plan = Remapper.applyCommands(settings(all: [Mapping(from: backslash, to: grave, enabled: true)]), previous: [magic.scope, .all])
        XCTAssertEqual(plan.commands.count, 2)
        XCTAssertEqual(plan.commands[1][2], Remapper.matchingJSON(magic.scope))
        XCTAssertEqual(try pairs(plan.commands[1][4]), [[backslash, grave]])
        XCTAssertEqual(plan.applied, [])
    }

    func testAppliedHasEveryScopeWithItsOwnList() {
        let value = settings(all: [], keyboards: [
            DeviceMappings(device: magic, mappings: [Mapping(from: keyA, to: keyB, enabled: true)]),
            DeviceMappings(device: builtIn, mappings: [Mapping(from: keyA, to: keyB, enabled: false)]),
        ])
        let plan = Remapper.applyCommands(value, previous: [])
        XCTAssertEqual(plan.applied, [magic.scope, builtIn.scope])
        XCTAssertEqual(plan.commands.count, 3)
    }

    func testClearPlanIsGlobalThenEachPreviousScopeInStableOrder() {
        let commands = Remapper.clearCommands(previous: [magic.scope, .all, builtIn.scope])
        XCTAssertEqual(commands, [
            ["property", "--set", Remapper.clearJSON],
            Remapper.arguments(set: Remapper.clearJSON, scope: builtIn.scope),
            Remapper.arguments(set: Remapper.clearJSON, scope: magic.scope),
        ])
    }

    func testExecuteRunsEveryCommandInOrderAndReturnsTheFirstError() {
        var calls: [[String]] = []
        let error = Remapper.execute([["a"], ["b"], ["c"]]) { arguments in
            calls.append(arguments)
            return arguments == ["a"] ? nil : "failed \(arguments[0])"
        }
        XCTAssertEqual(calls, [["a"], ["b"], ["c"]])
        XCTAssertEqual(error, "failed b")
    }

    func testAllScopeHasNoMatching() {
        XCTAssertNil(Remapper.matchingJSON(.all))
        XCTAssertEqual(Remapper.arguments(set: "{}", scope: .all), ["property", "--set", "{}"])
    }

    func testDeviceScopeMatchesVendorAndProduct() throws {
        let args = Remapper.arguments(set: "{}", scope: .device(vendorID: 1452, productID: 832, builtIn: false))
        XCTAssertEqual(args.count, 5)
        XCTAssertEqual(args[1], "--matching")
        XCTAssertEqual(args[3], "--set")
        let matching = try object(args[2])
        XCTAssertEqual(matching["VendorID"] as? Int, 1452)
        XCTAssertEqual(matching["ProductID"] as? Int, 832)
        XCTAssertEqual(matching["PrimaryUsagePage"] as? Int, 1)
        XCTAssertEqual(matching["PrimaryUsage"] as? Int, 6)
        XCTAssertNil(matching["Built-In"])
    }

    func testBuiltInScopeMatchesBuiltIn() throws {
        let json = try XCTUnwrap(Remapper.matchingJSON(.device(vendorID: 1452, productID: 832, builtIn: true)))
        let matching = try object(json)
        XCTAssertEqual(matching["Built-In"] as? Int, 1)
        XCTAssertEqual(matching["PrimaryUsagePage"] as? Int, 1)
        XCTAssertEqual(matching["PrimaryUsage"] as? Int, 6)
        XCTAssertNil(matching["VendorID"])
        XCTAssertNil(matching["ProductID"])
    }
}
