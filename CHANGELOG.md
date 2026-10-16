# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.2] - 2026-10-16

### Added

- Checks for updates in the background at launch and daily; a green update button next to the keyboard picker (and "Update Available…" in the menu bar menu) shows when a new version is available.

## [1.1.1] - 2026-10-16

### Added

- Key menus have Detect auto…, which opens a sheet that detects the next key press so you can use it right away.
- Each keyboard's list also shows the All keyboards mappings. Changing one on a keyboard gives that keyboard its own copy; a dot shows whether it still matches All (click a gray dot to take the All values again), and the stack button in All keyboards makes every keyboard use that mapping again.

### Changed

- Buttons in the New mapping window are capsules, and row icon buttons react on hover and press.
- The About window spaces out its description, link and license lines.

### Fixed

- Detect key shows Grant Access… when Input Monitoring is missing or no longer valid.

## [1.1.0] - 2026-10-16

### Added

- Menu bar menu shows whether Input Monitoring (needed by Detect key) is granted, with Grant Input Monitoring… to ask for it.
- Theme button in the main window's toolbar to switch between Light and Dark (the system appearance until it is used).

### Changed

- Main window redesigned with Liquid Glass: the keyboard picker sits in the toolbar next to the window buttons, Import, Export and + (New mapping) are icons on the right, and the window shows only the mapping list, one rounded row per mapping with a compact on/off switch. Long key names end with an ellipsis.
- New mapping opens in its own small window from +; detected keys show in a key-cap box.
- Requires macOS 14 or later.

### Fixed

- After Detect key, Use as From and Use as To hide the detected key once it is used.

## [1.0.0] - 2026-10-16

### Added

- Main window with a mapping list per keyboard: an All keyboards list plus one list per keyboard (built-in or external); the keyboard's own entry wins on the same From key.
- Per-row on/off toggle, From and To pickers with every keyboard key plus `fn`, grouped by category with Karabiner-Elements names.
- Detect key: press a key to use it as From or To, or to pick the keyboard it came from.
- Import and export of the settings as JSON.
- Settings file in Application Support, copied to iCloud Drive on every save and restored from it when the local file is missing (reinstall, new Mac).
- Menu bar menu: Open SimpleMapper, Launch at login, number of active mappings, Check for Updates, About, Quit with confirmation.
- About panel with the app logo.
- Mappings are re-applied at launch and when a keyboard reconnects, and cleared on Quit.
- Dock icon only while the window is open; a login launch stays in the menu bar.
- Automatic updates via Sparkle.
- A fresh install starts with no mappings. The previous single mapping of pre-release builds is migrated once.
