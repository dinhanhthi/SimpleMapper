<p align="center"><img src="public/logo_256.png" width="128" alt="SimpleMapper icon"></p>

# SimpleMapper

An ultra-simple alternative to Karabiner-Elements for macOS: a menu bar app that remaps exactly one key, for all keyboards or for one keyboard. The default mapping is `non_us_backslash` (the § key) to `grave_accent_and_tilde` (backtick and tilde).

## Features

- One mapping: pick From and To from every keyboard key plus `fn`, named as in Karabiner-Elements ([full list](docs/KEYS.md)).
- Apply it to all keyboards or to one keyboard, built-in or external.
- Detect key: press a key to see its name and use it as From or To, or to select the keyboard it came from.
- On/off switch, Launch at login, automatic updates.
- No driver, no kernel extension, no Accessibility permission.

## Install

1. Download the notarized `SimpleMapper-X.Y.Z.dmg` from [GitHub Releases](https://github.com/dinhanhthi/SimpleMapper/releases).
2. Open it and drag SimpleMapper to `/Applications`.
3. Launch it. It updates itself via Sparkle (also: Check for Updates in its window).

Requires macOS 13 or later.

## Usage

Click the SimpleMapper icon (the app logo) in the menu bar:

- **From / To**: choose the key to remap and the key it should type, by category.
- **Detect key**: press any key to identify it, then click Use as From, Use as To or Use this keyboard.
- **Keyboard**: All keyboards, or one connected keyboard (a saved keyboard stays selected while unplugged).
- **Switch** (top right): turn the mapping on or off.
- **Launch at login**, **Check for Updates**, **Quit**.

## How it works

- SimpleMapper sets Apple's `UserKeyMapping` with `/usr/bin/hidutil`, optionally limited to one keyboard with `--matching`. The default mapping equals one command, shown in [docs/KEYS.md](docs/KEYS.md#equivalent-command).
- `hidutil` mappings do not survive a restart, so the app re-applies the mapping at launch and whenever a keyboard is connected.
- Quitting the app or turning the switch off clears the mapping.
- Detect key asks for Input Monitoring the first time you use it. It listens only until one key is pressed (or 10 seconds pass), then stops.

## Caveats

- Quit Karabiner-Elements. It seizes keyboards, so `hidutil` mappings have no effect while it runs.
- Applying, turning off or quitting resets any other `UserKeyMapping` set by other tools or by hand with `hidutil`.
- ISO keyboards may swap the § and backtick keys (`non_us_backslash` and `grave_accent_and_tilde`). Use Detect key to see what a key really sends.

## Development

```sh
brew install xcodegen
scripts/dev.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, tests and code layout. Releases are local and maintainer-only: `/cf-ship`, see [docs/RELEASING.md](docs/RELEASING.md).

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT, see [LICENSE](LICENSE).
