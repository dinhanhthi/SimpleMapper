# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Menu bar app that remaps one key, by default § (`non_us_backslash`) to backtick (`grave_accent_and_tilde`).
- From and To pickers with every keyboard key plus `fn`, grouped by category with Karabiner-Elements names.
- Apply the mapping to all keyboards or to one keyboard, including the built-in one.
- Detect key: press a key to use it as From or To, or to pick the keyboard it came from.
- On/off switch; the mapping is re-applied at launch and when a keyboard reconnects, and cleared on Quit.
- Launch at login.
- Automatic updates via Sparkle, plus Check for Updates.
