import Foundation

/// Reads and writes the settings file. The local file is the single source of truth; every save mirrors it to
/// iCloud Drive (when it exists), which is read only when the local file is missing (fresh install, reinstall).
final class SettingsStore {
    let localDir: URL
    let cloudRoot: URL
    let defaults: UserDefaults
    /// The local file is missing and the iCloud copy is still downloading; see `recheckRestore`.
    var restorePending = false
    /// An unreadable local file could not be moved aside: `save` refuses, so the file is never overwritten.
    private(set) var localLocked = false
    private var lockMessage = ""

    /// Serial: every settings file read and write.
    private let queue = DispatchQueue(label: "dinh.thi.SimpleMapper.SettingsStore")
    private static let legacyKeys = ["fromUsage", "toUsage", "scope", "enabled", "savedDevice", "lastAppliedScope"]

    init(
        localDir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SimpleMapper", isDirectory: true),
        cloudRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true),
        defaults: UserDefaults = .standard
    ) {
        self.localDir = localDir
        self.cloudRoot = cloudRoot
        self.defaults = defaults
    }

    var localURL: URL { localDir.appendingPathComponent("settings.json") }

    /// `nil` when iCloud Drive is not there (the kill switch: return `nil` here to stay local only).
    var cloudURL: URL? {
        guard FileManager.default.fileExists(atPath: cloudRoot.path) else { return nil }
        return cloudRoot.appendingPathComponent("SimpleMapper/settings.json")
    }

    /// The local file; when it is missing, the iCloud copy (restored locally), plus the old single mapping from
    /// UserDefaults (migrated once); else empty. An existing but unreadable local file is moved aside to
    /// `settings.json.unreadable-<now>` (a new name, never overwritten), then loading goes on as if it were
    /// missing; when it can't be moved, `localLocked`. While the iCloud copy is still downloading (or can't be
    /// read: `restorePending`), the old mapping is merged in memory only: nothing is written and the old keys
    /// stay, for `recheckRestore`. Never writes to iCloud. `problem` tells the user. Call from the main thread.
    func load(now: Date = Date()) -> (settings: Settings, problem: String?) {
        queue.sync { () -> (settings: Settings, problem: String?) in
            restorePending = false
            localLocked = false
            var problems: [String] = []
            if FileManager.default.fileExists(atPath: localURL.path) {
                do {
                    return (try Settings.decode(Data(contentsOf: localURL)), nil)
                } catch {
                    let aside = asideURL(now)
                    do {
                        try FileManager.default.moveItem(at: localURL, to: aside)
                    } catch let moveError {
                        // Restoring or saving now would overwrite the file that could not be kept.
                        localLocked = true
                        lockMessage = "Settings are read-only until \(localURL.path) can be moved aside: \(moveError.localizedDescription)"
                        return (.empty, "Local settings are unreadable (\(error.localizedDescription)) and couldn't be moved aside: \(moveError.localizedDescription)")
                    }
                    problems.append("Local settings were unreadable and were moved to \(aside.lastPathComponent): \(error.localizedDescription)")
                }
            }
            var settings = Settings.empty
            var restored = false
            if let cloudURL {
                let notDownloaded = cloudNotDownloaded(cloudURL)
                if !notDownloaded && !FileManager.default.fileExists(atPath: cloudURL.path) {
                    // Nothing in iCloud.
                } else if !notDownloaded, let data = try? Data(contentsOf: cloudURL) {
                    do {
                        settings = try Settings.decode(data)
                        restored = true
                    } catch {
                        problems.append("iCloud settings not used: \(error.localizedDescription)")
                    }
                } else {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: cloudURL)
                    restorePending = true
                    problems.append("Restoring settings from iCloud…")
                }
            }
            let (migrated, problem) = migrate(into: &settings)
            problems += [problem].compactMap { $0 }
            if (restored || migrated) && !restorePending {
                if writeLocal(settings) == nil {
                    if migrated { removeLegacyKeys() }
                } else {
                    problems.append(migrated
                        ? "Couldn't save migrated settings; will retry at next launch."
                        : "Couldn't save the settings restored from iCloud on this Mac.")
                }
            }
            return (settings, problems.isEmpty ? nil : problems.joined(separator: "\n"))
        }
    }

    /// Runs on `queue`. Adds the old single mapping from UserDefaults to `settings` (a row with the same `from`
    /// in the same list is kept instead); whether it was added, and a message when it could not be (then
    /// `settings` is unchanged and the old keys must stay).
    private func migrate(into settings: inout Settings) -> (Bool, String?) {
        let base = settings
        guard let from: UInt64 = legacy("fromUsage"), let to: UInt64 = legacy("toUsage") else { return (false, nil) }
        for usage in [from, to]
        where KeyDetector.acceptedUsage(page: UInt32(usage >> 32), usage: UInt32(usage & 0xFFFF_FFFF)) == nil {
            return (false, "The old mapping was not migrated: it contains a key SimpleMapper can't remap (usage 0x\(String(usage, radix: 16, uppercase: true))).")
        }
        let raw = Settings.migrating(
            from: from,
            to: to,
            enabled: legacy("enabled") ?? true,
            scope: legacy("scope") ?? .all,
            savedDevice: legacy("savedDevice")
        )
        // As read back from the file: a built-in keyboard gets IDs 0/0, like `KeyboardDevice.keyboard`.
        let migrated = (try? Settings.decode(raw.encoded())) ?? raw
        if let mapping = migrated.all.first {
            if !settings.all.contains(where: { $0.from == mapping.from }) { settings.all.append(mapping) }
        } else if let entry = migrated.keyboards.first, let mapping = entry.mappings.first {
            if let i = settings.keyboards.firstIndex(where: { $0.device.scope == entry.device.scope }) {
                if !settings.keyboards[i].mappings.contains(where: { $0.from == mapping.from }) {
                    settings.keyboards[i].mappings.append(mapping)
                }
            } else {
                settings.keyboards.append(entry)
            }
        }
        do {
            _ = try Settings.decode(settings.encoded())
        } catch {
            settings = base
            return (false, "Couldn't add your previous mapping: \(error.localizedDescription)")
        }
        return (true, nil)
    }

    /// Runs on `queue`, once the migrated settings are written.
    private func removeLegacyKeys() {
        let lastApplied: Scope? = legacy("lastAppliedScope")
        Self.legacyKeys.forEach(defaults.removeObject(forKey:))
        // Built-in keyboards share one 0/0 scope (Intel Macs stored their Apple IDs).
        if case let .device(vendorID, productID, builtIn)? = lastApplied {
            appliedScopes.insert(builtIn ? .device(vendorID: 0, productID: 0, builtIn: true)
                                         : .device(vendorID: vendorID, productID: productID, builtIn: false))
        }
    }

    /// When `load` found only an iCloud placeholder: checks once, after `seconds`, whether the download is done,
    /// then clears `restorePending` whatever the result. The restored file gets the old mapping (as in `load`);
    /// the old keys are removed only once it is written locally. A local file already written by `save` is kept.
    /// Completion on main: the restored settings (written locally), or `nil` if there is nothing to restore;
    /// and a message when the iCloud file can't be decoded or the old mapping could not be added.
    func recheckRestore(after seconds: TimeInterval = 5, completion: @escaping (Settings?, String?) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            let (restored, problem) = self.queue.sync { () -> (Settings?, String?) in
                self.restorePending = false
                guard !FileManager.default.fileExists(atPath: self.localURL.path),
                      let cloudURL = self.cloudURL,
                      !self.cloudEvicted(cloudURL),
                      let data = try? Data(contentsOf: cloudURL)
                else { return (nil, nil) }
                var settings: Settings
                do {
                    settings = try Settings.decode(data)
                } catch {
                    return (nil, "iCloud settings not used: \(error.localizedDescription)")
                }
                let (migrated, problem) = self.migrate(into: &settings)
                guard self.writeLocal(settings) == nil else { return (nil, nil) }
                if migrated { self.removeLegacyKeys() }
                return (settings, problem)
            }
            completion(restored, problem)
        }
    }

    /// The iCloud file has no data here yet: a `.icloud` placeholder, or an evicted file.
    private func cloudNotDownloaded(_ cloudURL: URL) -> Bool {
        let placeholder = cloudURL.deletingLastPathComponent().appendingPathComponent(".settings.json.icloud")
        return FileManager.default.fileExists(atPath: placeholder.path) || cloudEvicted(cloudURL)
    }

    /// macOS 14+: an evicted iCloud file shows under its real name with no data; reading it would download it
    /// synchronously.
    private func cloudEvicted(_ cloudURL: URL) -> Bool {
        let values = try? cloudURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
        return values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current
    }

    /// `settings.json.unreadable-<date as yyyyMMdd-HHmmss-SSS, local time>`, with `-1`, `-2`, … when taken.
    private func asideURL(_ date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let base = "settings.json.unreadable-\(formatter.string(from: date))"
        var url = localDir.appendingPathComponent(base)
        var n = 0
        while FileManager.default.fileExists(atPath: url.path) {
            n += 1
            url = localDir.appendingPathComponent("\(base)-\(n)")
        }
        return url
    }

    /// Writes the local file, then the same bytes to iCloud Drive (when it is there). While `restorePending`,
    /// writes the local file only: the iCloud copy still downloading must not be overwritten (and `recheckRestore`
    /// then keeps this local file). While `localLocked`, writes nothing. Returns `nil` on success, else a message
    /// for the user. Call from the main thread.
    func save(_ settings: Settings) -> String? {
        queue.sync {
            if localLocked { return lockMessage }
            let data = settings.encoded()
            if let error = write(data, to: localURL) { return "Couldn't save settings: \(error.localizedDescription)" }
            guard !restorePending, let cloudURL, let error = write(data, to: cloudURL) else { return nil }
            return "Saved locally; couldn't copy to iCloud Drive: \(error.localizedDescription)"
        }
    }

    /// Runs on `queue`.
    private func writeLocal(_ settings: Settings) -> Error? {
        write(settings.encoded(), to: localURL)
    }

    /// Atomically, creating the folder; the error, or `nil` on success.
    private func write(_ data: Data, to url: URL) -> Error? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return nil
        } catch {
            return error
        }
    }

    /// Device scopes hidutil was last given a mapping for; local only, never synced.
    var appliedScopes: Set<Scope> {
        get {
            guard let data = defaults.data(forKey: "appliedScopes") else { return [] }
            return (try? JSONDecoder().decode(Set<Scope>.self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "appliedScopes") }
    }

    /// Reads a value the old `AppModel` stored as JSON data.
    private func legacy<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
