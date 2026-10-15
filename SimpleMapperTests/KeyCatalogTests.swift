import XCTest
@testable import SimpleMapper

final class KeyCatalogTests: XCTestCase {
    func testNamesAreUnique() {
        let names = KeyCatalog.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testUsagePagesAreKeyboardOrFn() {
        for key in KeyCatalog.all {
            let page = key.usage >> 32
            XCTAssertTrue(page == 0x07 || page == 0xFF, "\(key.name) has page \(page)")
        }
    }

    func testDefaults() {
        XCTAssertEqual(KeyCatalog.key(usage: KeyCatalog.defaultFrom)?.name, "non_us_backslash")
        XCTAssertEqual(KeyCatalog.key(usage: KeyCatalog.defaultTo)?.name, "grave_accent_and_tilde")
    }

    func testLookupByUsage() {
        XCTAssertEqual(KeyCatalog.key(usage: 0x700000064)?.name, "non_us_backslash")
        XCTAssertEqual(KeyCatalog.key(usage: 0x700000035)?.name, "grave_accent_and_tilde")
    }

    func testLookupByName() {
        XCTAssertEqual(KeyCatalog.key(name: "fn")?.usage, 0xFF00000003)
        XCTAssertEqual(KeyCatalog.key(name: "a")?.usage, 0x700000004)
        XCTAssertEqual(KeyCatalog.key(name: "f24")?.usage, 0x700000073)
    }

    func testPrimaryNameWinsOverJapaneseAlias() {
        XCTAssertEqual(KeyCatalog.key(usage: 0x700000090)?.name, "lang1")
    }

    func testEveryCategoryIsNonEmpty() {
        for category in Category.allCases {
            XCTAssertFalse(KeyCatalog.all.filter { $0.category == category }.isEmpty, "\(category) is empty")
        }
    }
}
