import XCTest
@testable import SimpleMapper

final class SettingsStoreTests: XCTestCase {
    private let grave: UInt64 = 0x700000035
    private let backslash: UInt64 = 0x700000064
    private let keyboard = KeyboardDevice(vendorID: 1452, productID: 832, builtIn: false, name: "Magic Keyboard")
    private var root: URL!
    private var localDir: URL!
    private var cloudRoot: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SettingsStoreTests-\(UUID().uuidString)")
        localDir = root.appendingPathComponent("Local/SimpleMapper")
        cloudRoot = root.appendingPathComponent("CloudDocs")
        try FileManager.default.createDirectory(at: cloudRoot, withIntermediateDirectories: true)
        suiteName = "SimpleMapperTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = SettingsStore(localDir: localDir, cloudRoot: cloudRoot, defaults: defaults)
    }

    override func tearDownWithError() throws {
        for dir in [localDir!, cloudFolder] where FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Helpers

    /// Stores a legacy value exactly like the old `AppModel.save`: JSON data.
    private func setLegacy<T: Encodable>(_ value: T, _ key: String) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }

    private func setLegacyMapping(scope: Scope = .all, lastApplied: Scope? = nil) throws {
        try setLegacy(grave, "fromUsage")
        try setLegacy(backslash, "toUsage")
        try setLegacy(true, "enabled")
        try setLegacy(scope, "scope")
        try setLegacy(keyboard, "savedDevice")
        if let lastApplied { try setLegacy(lastApplied, "lastAppliedScope") }
    }

    private func settings(at seconds: TimeInterval, to: UInt64 = 0x700000064) -> Settings {
        Settings(modifiedAt: Date(timeIntervalSince1970: seconds), all: [Mapping(from: grave, to: to, enabled: true)], keyboards: [])
    }


    private func writeCloud(_ data: Data) throws {
        let url = try XCTUnwrap(store.cloudURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func readLocal() throws -> Settings {
        try Settings.decode(Data(contentsOf: store.localURL))
    }

    private var cloudFolder: URL { cloudRoot.appendingPathComponent("SimpleMapper") }

    /// The cloud file's bytes, modification date and file number: any write changes one of them.
    private func cloudFileState() throws -> [AnyHashable] {
        let url = try XCTUnwrap(store.cloudURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return [try Data(contentsOf: url), attributes[.modificationDate] as? Date, attributes[.systemFileNumber] as? Int]
    }

    private func assertLegacyKeys(present: Bool, file: StaticString = #filePath, line: UInt = #line) {
        for key in ["fromUsage", "toUsage", "scope", "enabled", "savedDevice"] {
            XCTAssertEqual(defaults.object(forKey: key) != nil, present, key, file: file, line: line)
        }
    }

    private func recheck() -> (settings: Settings?, problem: String?) {
        let done = expectation(description: "recheck")
        var result: (Settings?, String?)
        store.recheckRestore(after: 0) { restored, problem in
            XCTAssertTrue(Thread.isMainThread)
            result = (restored, problem)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }

    private func writePlaceholder() throws {
        try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        try Data().write(to: cloudFolder.appendingPathComponent(".settings.json.icloud"))
    }

    /// A full All list (256 rows) whose `from` is not the legacy mapping's.
    private var fullCloud: Settings {
        let rows = Array(repeating: Mapping(from: 0x700000004, to: 0x700000005, enabled: true), count: Settings.maxMappingsPerList)
        return Settings(modifiedAt: Date(timeIntervalSince1970: 1_760_000_000), all: rows, keyboards: [])
    }

    // MARK: - Paths

    func testCloudURLPointsIntoSimpleMapperFolder() {
        XCTAssertEqual(store.cloudURL, cloudFolder.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.localURL, localDir.appendingPathComponent("settings.json"))
    }

    // MARK: - Save

    func testSaveWritesLocalAndMirrorsSameBytesCreatingCloudFolder() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFolder.path))
        XCTAssertNil(store.save(settings(at: 1_760_000_000)))
        let local = try Data(contentsOf: store.localURL)
        XCTAssertEqual(local, settings(at: 1_760_000_000).encoded())
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.cloudURL)), local)
    }

    func testSaveWithoutCloudRootWritesLocalOnly() throws {
        try FileManager.default.removeItem(at: cloudRoot)
        XCTAssertNil(store.cloudURL)
        XCTAssertNil(store.save(settings(at: 1_760_000_000)))
        XCTAssertEqual(try readLocal(), settings(at: 1_760_000_000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudRoot.path))
    }

    func testMirrorFailureKeepsLocalAndReportsIt() throws {
        try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: cloudFolder.path)
        let problem = try XCTUnwrap(store.save(settings(at: 1_760_000_000)))
        XCTAssertTrue(problem.hasPrefix("Saved locally; couldn't copy to iCloud Drive: "), problem)
        XCTAssertEqual(try readLocal(), settings(at: 1_760_000_000))
    }

    // MARK: - Load

    func testFreshInstallGivesEmptyAndWritesNothing() throws {
        let (settings, problem) = store.load()
        XCTAssertEqual(settings.encoded(), Settings.empty.encoded())
        XCTAssertNil(problem)
        XCTAssertFalse(store.restorePending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localDir.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFolder.path))
    }

    func testLocalFileIsUsedAndCloudIgnored() throws {
        XCTAssertNil(store.save(settings(at: 1_760_000_000)))
        try writeCloud(settings(at: 1_760_000_100, to: 0x700000004).encoded())
        let (settings, problem) = store.load()
        XCTAssertEqual(settings, self.settings(at: 1_760_000_000))
        XCTAssertNil(problem)
    }

    func testMissingLocalIsRestoredFromCloud() throws {
        let cloud = settings(at: 1_760_000_100, to: 0x700000004)
        try writeCloud(cloud.encoded())
        let state = try cloudFileState()
        let (settings, problem) = store.load()
        XCTAssertEqual(settings, cloud)
        XCTAssertNil(problem)
        XCTAssertEqual(try readLocal(), cloud)
        XCTAssertEqual(try cloudFileState(), state)
    }

    func testPlaceholderGivesEmptyAndRestorePending() throws {
        try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        try Data().write(to: cloudFolder.appendingPathComponent(".settings.json.icloud"))
        let (settings, problem) = store.load()
        XCTAssertEqual(settings.encoded(), Settings.empty.encoded())
        XCTAssertEqual(problem, "Restoring settings from iCloud…")
        XCTAssertTrue(store.restorePending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFolder.appendingPathComponent("settings.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
    }

    func testUndecodableCloudGivesEmptyAndStaysUntouched() throws {
        try writeCloud(Data("not json".utf8))
        let state = try cloudFileState()
        let (settings, problem) = store.load()
        XCTAssertEqual(settings.encoded(), Settings.empty.encoded())
        XCTAssertNotNil(problem)
        XCTAssertEqual(try cloudFileState(), state)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
    }

    func testLegacyMappingIsAppendedToRestoredCloud() throws {
        let cloud = Settings(modifiedAt: Date(timeIntervalSince1970: 1_760_000_000), all: [Mapping(from: 0x700000004, to: 0x700000005, enabled: true)], keyboards: [])
        try writeCloud(cloud.encoded())
        let state = try cloudFileState()
        try setLegacyMapping()
        let (settings, problem) = store.load()
        XCTAssertNil(problem)
        XCTAssertEqual(settings.all.map { [$0.from, $0.to] }, [[0x700000004, 0x700000005], [grave, backslash]])
        XCTAssertEqual(try readLocal(), settings)
        XCTAssertEqual(try cloudFileState(), state)
        assertLegacyKeys(present: false)
    }

    func testLegacyMappingKeepsCloudRowWithSameFrom() throws {
        let cloud = settings(at: 1_760_000_000, to: 0x700000004)
        try writeCloud(cloud.encoded())
        try setLegacyMapping()
        let (settings, problem) = store.load()
        XCTAssertNil(problem)
        XCTAssertEqual(settings, cloud)
        XCTAssertEqual(try readLocal(), cloud)
        assertLegacyKeys(present: false)
    }

    func testMigrationWritesFileAndRemovesKeys() throws {
        try setLegacyMapping()
        let settings = store.load().settings
        XCTAssertEqual(settings.all.map { [$0.from, $0.to] }, [[grave, backslash]])
        XCTAssertEqual(try readLocal().encoded(), settings.encoded())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFolder.path))
        assertLegacyKeys(present: false)
    }

    func testMigrationKeepsDeviceScope() throws {
        try setLegacyMapping(scope: keyboard.scope)
        let settings = store.load().settings
        XCTAssertEqual(settings.all, [])
        XCTAssertEqual(settings.keyboards.map(\.device), [keyboard])
    }

    func testMigrationGivesBuiltInKeyboardZeroIDs() throws {
        let builtIn = KeyboardDevice(vendorID: 1452, productID: 641, builtIn: true, name: "Apple Internal Keyboard")
        try setLegacyMapping(scope: builtIn.scope)
        try setLegacy(builtIn, "savedDevice")
        let settings = store.load().settings
        XCTAssertEqual(settings.keyboards.map(\.device.scope), [.device(vendorID: 0, productID: 0, builtIn: true)])
        XCTAssertEqual(try readLocal().encoded(), settings.encoded())
    }

    func testMigrationMovesLastAppliedScopeIntoAppliedScopes() throws {
        try setLegacyMapping(scope: keyboard.scope, lastApplied: keyboard.scope)
        _ = store.load()
        XCTAssertEqual(store.appliedScopes, [keyboard.scope])
        XCTAssertNil(defaults.object(forKey: "lastAppliedScope"))
    }

    func testMigrationNormalizesBuiltInLastAppliedScope() throws {
        let intelBuiltIn = Scope.device(vendorID: 1452, productID: 641, builtIn: true)
        try setLegacyMapping(scope: .all, lastApplied: intelBuiltIn)
        _ = store.load()
        XCTAssertEqual(store.appliedScopes, [.device(vendorID: 0, productID: 0, builtIn: true)])
    }

    func testMigrationKeepsKeysWhenLocalDirIsReadOnly() throws {
        try setLegacyMapping(lastApplied: keyboard.scope)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: localDir.path)
        let (settings, problem) = store.load()
        XCTAssertEqual(settings.all.map { [$0.from, $0.to] }, [[grave, backslash]])
        XCTAssertEqual(problem, "Couldn't save migrated settings; will retry at next launch.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
        assertLegacyKeys(present: true)
        XCTAssertNotNil(defaults.object(forKey: "lastAppliedScope"))
        XCTAssertEqual(store.appliedScopes, [])
    }

    func testMigrationRejectsInvalidUsageAndKeepsKeys() throws {
        try setLegacyMapping()
        try setLegacy(UInt64(0x700000001), "fromUsage")
        let result = store.load()
        XCTAssertEqual(result.settings.encoded(), Settings.empty.encoded())
        XCTAssertNotNil(result.problem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
        assertLegacyKeys(present: true)
    }

    /// Writes `data` as the local file, loads, and returns the result with the moved-aside file's bytes.
    private func loadUnreadable(_ data: Data) throws -> (result: (settings: Settings, problem: String?), moved: Data?) {
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try data.write(to: store.localURL)
        let result = store.load()
        let names = try FileManager.default.contentsOfDirectory(atPath: localDir.path)
        let moved = names.first { $0.hasPrefix("settings.json.unreadable-") }
        return (result, try moved.map { try Data(contentsOf: localDir.appendingPathComponent($0)) })
    }

    func testUnreadableLocalFileIsMovedAside() throws {
        let data = Data("not json".utf8)
        let (result, moved) = try loadUnreadable(data)
        XCTAssertEqual(result.settings.encoded(), Settings.empty.encoded())
        XCTAssertNotNil(result.problem)
        XCTAssertEqual(moved, data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
    }

    func testUnreadableLocalFileIsMovedAsideThenRestoredFromCloud() throws {
        let cloud = settings(at: 1_760_000_100, to: 0x700000004)
        try writeCloud(cloud.encoded())
        let data = Data("not json".utf8)
        let (result, moved) = try loadUnreadable(data)
        XCTAssertEqual(result.settings, cloud)
        XCTAssertNotNil(result.problem)
        XCTAssertEqual(moved, data)
        XCTAssertEqual(try readLocal(), cloud)
    }

    func testUnreadableLocalFilesInSameMillisecondGetDistinctNames() throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000.123)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        for bytes in ["first", "second"] {
            try Data(bytes.utf8).write(to: store.localURL)
            _ = store.load(now: now)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: localDir.path).sorted()
        XCTAssertEqual(names.count, 2, "\(names)")
        XCTAssertTrue(names[0].hasPrefix("settings.json.unreadable-"), names[0])
        XCTAssertEqual(names[1], names[0] + "-1")
        XCTAssertEqual(try names.map { try Data(contentsOf: localDir.appendingPathComponent($0)) }, [Data("first".utf8), Data("second".utf8)])
    }

    func testUnmovableUnreadableLocalFileLocksSave() throws {
        let data = Data("not json".utf8)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try data.write(to: store.localURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: localDir.path)
        let (settings, problem) = store.load()
        XCTAssertEqual(settings.encoded(), Settings.empty.encoded())
        XCTAssertNotNil(problem)
        XCTAssertTrue(store.localLocked)
        // Writable again: only the lock keeps the file.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: localDir.path)
        let refusal = try XCTUnwrap(store.save(self.settings(at: 1_760_000_000)))
        XCTAssertTrue(refusal.hasPrefix("Settings are read-only until \(store.localURL.path) can be moved aside: "), refusal)
        XCTAssertEqual(try Data(contentsOf: store.localURL), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: localDir.path), ["settings.json"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFolder.path))
    }

    func testUnreadableCloudFileIsPendingAndUntouched() throws {
        try writeCloud(settings(at: 1_760_000_100, to: 0x700000004).encoded())
        let state = try cloudFileState()
        let url = try XCTUnwrap(store.cloudURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let (settings, problem) = store.load()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertEqual(settings.encoded(), Settings.empty.encoded())
        XCTAssertEqual(problem, "Restoring settings from iCloud…")
        XCTAssertTrue(store.restorePending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
        XCTAssertEqual(try cloudFileState(), state)
    }

    func testRestoredCloudThatCannotBeSavedLocallyIsReported() throws {
        let cloud = settings(at: 1_760_000_100, to: 0x700000004)
        try writeCloud(cloud.encoded())
        let state = try cloudFileState()
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: localDir.path)
        let (settings, problem) = store.load()
        XCTAssertEqual(settings, cloud)
        XCTAssertEqual(problem, "Couldn't save the settings restored from iCloud on this Mac.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
        XCTAssertEqual(try cloudFileState(), state)
    }

    // MARK: - Recheck restore

    func testRecheckRestoreRestoresCloudFileOnceItArrives() throws {
        try writePlaceholder()
        _ = store.load()
        let cloud = settings(at: 1_760_000_100, to: 0x700000004)
        try writeCloud(cloud.encoded())
        let result = recheck()
        XCTAssertEqual(result.settings, cloud)
        XCTAssertNil(result.problem)
        XCTAssertEqual(try readLocal(), cloud)
        XCTAssertFalse(store.restorePending)
    }

    func testRecheckRestoreGivesNilWithoutCloudFile() throws {
        try writePlaceholder()
        _ = store.load()
        XCTAssertTrue(store.restorePending)
        XCTAssertNil(recheck().settings)
        XCTAssertFalse(store.restorePending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
    }

    func testRecheckReportsUndecodableCloudFile() throws {
        try writePlaceholder()
        _ = store.load()
        try writeCloud(Data("not json".utf8))
        let result = recheck()
        XCTAssertNil(result.settings)
        XCTAssertTrue(result.problem?.hasPrefix("iCloud settings not used: ") == true, result.problem ?? "nil")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
        XCTAssertFalse(store.restorePending)
    }

    func testPlaceholderWithLegacyMergesInMemoryOnly() throws {
        try writePlaceholder()
        try setLegacyMapping()
        let (settings, problem) = store.load()
        XCTAssertEqual(settings.all.map { [$0.from, $0.to] }, [[grave, backslash]])
        XCTAssertEqual(problem, "Restoring settings from iCloud…")
        XCTAssertTrue(store.restorePending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.localURL.path))
        assertLegacyKeys(present: true)
    }

    func testSaveWhilePendingWritesLocalOnlyAndRecheckKeepsIt() throws {
        try writePlaceholder()
        try setLegacyMapping()
        let saved = store.load().settings
        XCTAssertNil(store.save(saved))
        XCTAssertEqual(try readLocal(), saved)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cloudFolder.path), [".settings.json.icloud"])
        try writeCloud(settings(at: 1_760_000_100, to: 0x700000004).encoded())
        XCTAssertNil(recheck().settings)
        XCTAssertEqual(try readLocal(), saved)
        XCTAssertFalse(store.restorePending)
    }

    func testRecheckMergesLegacyThenRemovesKeys() throws {
        try writePlaceholder()
        try setLegacyMapping(scope: .all, lastApplied: keyboard.scope)
        _ = store.load()
        let cloud = Settings(modifiedAt: Date(timeIntervalSince1970: 1_760_000_000), all: [Mapping(from: 0x700000004, to: 0x700000005, enabled: true)], keyboards: [])
        try writeCloud(cloud.encoded())
        let state = try cloudFileState()
        let result = recheck()
        let restored = try XCTUnwrap(result.settings)
        XCTAssertNil(result.problem)
        XCTAssertEqual(restored.all.map { [$0.from, $0.to] }, [[0x700000004, 0x700000005], [grave, backslash]])
        XCTAssertEqual(try readLocal(), restored)
        XCTAssertEqual(try cloudFileState(), state)
        assertLegacyKeys(present: false)
        XCTAssertEqual(store.appliedScopes, [keyboard.scope])
        XCTAssertFalse(store.restorePending)
    }

    func testLegacyOverCapKeepsCloudAndKeys() throws {
        try writeCloud(fullCloud.encoded())
        try setLegacyMapping()
        let (settings, problem) = store.load()
        XCTAssertEqual(settings, fullCloud)
        XCTAssertEqual(try readLocal(), fullCloud)
        XCTAssertTrue(problem?.hasPrefix("Couldn't add your previous mapping: ") == true, problem ?? "nil")
        assertLegacyKeys(present: true)
    }

    func testRecheckLegacyOverCapKeepsCloudAndKeys() throws {
        try writePlaceholder()
        try setLegacyMapping()
        _ = store.load()
        try writeCloud(fullCloud.encoded())
        let result = recheck()
        XCTAssertEqual(result.settings, fullCloud)
        XCTAssertEqual(try readLocal(), fullCloud)
        XCTAssertTrue(result.problem?.hasPrefix("Couldn't add your previous mapping: ") == true, result.problem ?? "nil")
        assertLegacyKeys(present: true)
        XCTAssertFalse(store.restorePending)
    }

    // MARK: - Applied scopes

    func testAppliedScopesRoundTrip() {
        XCTAssertEqual(store.appliedScopes, [])
        store.appliedScopes = [keyboard.scope]
        XCTAssertEqual(store.appliedScopes, [keyboard.scope])
    }
}
