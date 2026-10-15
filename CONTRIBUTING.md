# Contributing to SimpleMapper

Thanks for helping. SimpleMapper stays small on purpose: a window and a menu bar menu. Please open an issue before larger changes.

## Prerequisites

- macOS 13+ to run the app.
- Xcode 26+ to compile it (the app icon is an Icon Composer `.icon`).
- XcodeGen:

  ```sh
  brew install xcodegen
  ```

## Setup

Generate the Xcode project:

```sh
xcodegen generate
```

`SimpleMapper.xcodeproj` is generated from `project.yml` and gitignored. Change settings, targets and packages in `project.yml`, never in the `.xcodeproj`.

## Run

```sh
scripts/dev.sh           # xcodegen generate, Debug build, launch
scripts/dev.sh --clean   # clean build first
```

Quit Karabiner-Elements while testing: it seizes keyboards, so `hidutil` mappings have no effect while it runs.

## Tests

```sh
xcodebuild test -project SimpleMapper.xcodeproj -scheme SimpleMapper
```

Unit tests cover the pure and injectable parts:

- `Settings`: JSON codec, validation, merge (device wins over All) and migration of the old single mapping.
- `Remapper`: the apply and clear command planner, with a fake runner instead of `hidutil`.
- `SettingsStore`: local file, iCloud copy and restore, with temp folders and a private `UserDefaults` suite.
- `KeyCatalog`.

`AppModel.start()` never runs under tests (the app skips all setup when it runs as a test host). Tests must never touch `hidutil`, the real Application Support folder, iCloud Drive or `UserDefaults.standard`.

## Screenshots and measurements

```sh
scripts/screenshots.sh   # README screenshots into assets/screenshots/
scripts/measure.sh       # RAM and CPU of SimpleMapper vs Karabiner-Elements
```

`screenshots.sh` builds Debug and runs the app in demo mode (`SIMPLEMAPPER_DEMO=1`, compiled only in Debug): fixed demo settings in a temp folder, iCloud off and no `hidutil` calls, so your settings and keyboard are untouched. A SimpleMapper that was running is quit during the capture (its mappings are cleared meanwhile) and relaunched in the background at the end. It needs Screen Recording permission for the terminal. `measure.sh [seconds]` samples the running processes with `top`, so start SimpleMapper (a Release build) and Karabiner-Elements first.

## Xcode cache

Never pass `-derivedDataPath` to local `xcodebuild` builds and tests. The default DerivedData folder is the one Xcode uses, so Xcode's Run reuses the CLI build, and the app path stays stable so the Input Monitoring grant survives rebuilds.

## Code layout

- `SimpleMapper/SimpleMapperApp.swift`: AppKit entry point (no SwiftUI `App`), the main window and About panel, applies the mappings at launch and clears them on quit.
- `SimpleMapper/MainView.swift`: the main window in SwiftUI (keyboard picker, mapping list, New mapping with Detect key, Import and Export).
- `SimpleMapper/MenuBarView.swift`: the menu bar menu, an AppKit `StatusMenu` (no SwiftUI, for a small footprint).
- `SimpleMapper/AppModel.swift`: app state, editing rules, import/export, launch at login.
- `SimpleMapper/Settings.swift`: the settings model, JSON codec, validation and merge.
- `SimpleMapper/SettingsStore.swift`: the local settings file, the iCloud Drive copy and restore.
- `SimpleMapper/Remapper.swift`: plans and runs the `/usr/bin/hidutil` commands.
- `SimpleMapper/KeyCatalog.swift`: the list of keys, names and HID usages.
- `SimpleMapper/KeyboardMonitor.swift`: lists connected keyboards and reports reconnects.
- `SimpleMapper/KeyDetector.swift`: Detect key (one key press, Input Monitoring).
- `SimpleMapper/Updater.swift`: Sparkle updater.
- `SimpleMapper/Info.plist`: Sparkle keys, merged into the generated Info.plist.
- `SimpleMapper/logo.icon`: app icon.
- `SimpleMapper/Assets.xcassets`: `MenuBarIcon` (menu bar template image) and `AboutLogo` (logo shown in the About panel).
- `SimpleMapperTests/`: unit tests.
- `scripts/`: dev, screenshots, measure and release scripts.

## Adding a key

1. Add one `Key(` entry per line to `KeyCatalog.all` in `SimpleMapper/KeyCatalog.swift`, with the Karabiner-Elements name and the usage `(page << 32) | usage`. There are no default keys: the New mapping box starts empty.
2. Add the matching row to `docs/KEYS.md`. The row count must equal the number of `Key(` entries:

   ```sh
   test "$(grep -c '^| `' docs/KEYS.md)" = "$(grep -c 'Key(' SimpleMapper/KeyCatalog.swift)"
   ```

## Commit style

One-line conventional commits: `<type>(<scope>): <summary>`, for example `fix(remapper): clear the previous keyboard mapping`. Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`. No body.

## Releases

Releases are maintainer-only: see [docs/RELEASING.md](docs/RELEASING.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
