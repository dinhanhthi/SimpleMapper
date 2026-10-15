import XCTest
@testable import SimpleMapper

final class RemapperTests: XCTestCase {
    private func object(_ json: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testMappingJSONRoundTrips() throws {
        let json = Remapper.mappingJSON(from: KeyCatalog.defaultFrom, to: KeyCatalog.defaultTo)
        let mappings = try XCTUnwrap(object(json)["UserKeyMapping"] as? [[String: Any]])
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual((mappings[0]["HIDKeyboardModifierMappingSrc"] as? NSNumber)?.uint64Value, 30064771172)
        XCTAssertEqual((mappings[0]["HIDKeyboardModifierMappingDst"] as? NSNumber)?.uint64Value, 30064771125)
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
