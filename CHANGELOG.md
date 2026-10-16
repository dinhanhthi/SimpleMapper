# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Menu bar menu shows whether Input Monitoring (needed by Detect key) is granted, with Grant Input Monitoring… to ask for it.

### Changed

- Requires macOS 14 or later.

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
