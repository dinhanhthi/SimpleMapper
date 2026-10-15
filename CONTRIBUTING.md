# Contributing to SimpleMapper

Thanks for helping. SimpleMapper stays small on purpose: one mapping, one menu bar window. Please open an issue before larger changes.

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

Unit tests must never run `hidutil` or change the keyboard: test the pure parts (`KeyCatalog`, `Remapper.mappingJSON`, `Remapper.arguments`). The app skips remapping when it runs as a test host.

## Xcode cache

Never pass `-derivedDataPath` to local `xcodebuild` builds and tests. The default DerivedData folder is the one Xcode uses, so Xcode's Run reuses the CLI build, and the app path stays stable so the Input Monitoring grant survives rebuilds.

## Code layout

- `SimpleMapper/SimpleMapperApp.swift`: app entry, `MenuBarExtra`, applies the mapping at launch and clears it on quit.
- `SimpleMapper/MenuBarView.swift`: the menu bar window (From/To, Detect key, Keyboard picker, Launch at login).
- `SimpleMapper/AppModel.swift`: persisted state (UserDefaults), apply/clear, launch at login.
- `SimpleMapper/Remapper.swift`: builds and runs the `/usr/bin/hidutil` commands.
- `SimpleMapper/KeyCatalog.swift`: the list of keys, names and HID usages.
- `SimpleMapper/KeyboardMonitor.swift`: lists connected keyboards and reports reconnects.
- `SimpleMapper/KeyDetector.swift`: Detect key (one key press, Input Monitoring).
- `SimpleMapper/Updater.swift`: Sparkle updater.
- `SimpleMapper/Info.plist`: Sparkle keys, merged into the generated Info.plist.
- `SimpleMapper/logo.icon`: app icon.
- `SimpleMapperTests/`: unit tests.
- `scripts/`: dev and release scripts.

## Adding a key

1. Add one `Key(` entry per line to `KeyCatalog.all` in `SimpleMapper/KeyCatalog.swift`, with the Karabiner-Elements name and the usage `(page << 32) | usage`.
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
