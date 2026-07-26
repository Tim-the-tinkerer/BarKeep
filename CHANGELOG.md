# Changelog

All notable changes to **BarKeep** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [1.1.1] - 2026-07-26

### Fixed

- Settings window refreshes content on reopen (no stale toggles)
- Status menu uses `popUpContextMenu` instead of attach/performClick race
- Second app launch activates the existing instance and opens Settings
- Notification observers removed on quit; expand spacer before removing status items
- `startCollapsed` actually collapses after layout settles (~1s)
- Auto-hide interval clamped; timer runs in common run-loop modes
- Hover uses the screen under the mouse (multi-monitor)
- Accessibility labels/help on status items
- Hotkey fully tears down handler on disable/failure
- Removed unused `SystemStatusItems` dead code and obsolete settings fields
- Onboarding copy no longer claims collapse is “blocked”
- Help web view appearance wiring simplified

## [1.1.0] - 2026-07-26

### Added

- In-app **Help** window (HTML help book) with arrange guide, settings reference, and troubleshooting
- **CHANGELOG.md** and updated **README**
- Right-click menu: Settings, Help, Reset BarKeep Position, Quit
- Main menu entries for About, Settings, Help, and Quit
- First-run onboarding tips
- Optional auto-hide after delay, show on hover, launch at login, global hotkey **⌃⌘B**
- Reset BarKeep Position command (re-seeds │ and BK without reshuffling other apps)

### Changed

- Collapse uses a Hidden Bar / Ice–style large spacer so icons left of │ actually leave the menu bar (not just shift)
- Status item placement is seeded once and then left alone so ⌘-drag order is remembered
- Always launches expanded so a previous broken collapse cannot hide the chevron
- Version **1.1.0** (build 2)

### Fixed

- Multi-monitor false positives that blocked collapse or undid it immediately (“bounce”)
- Chevron disappearing after an oversized spacer claimed the whole bar
- Safety checks that auto-expanded right after collapse
- Aggressive preferred-position rewrites that forgot user arrangement every launch

## [1.0.0] - 2026-07-26

### Added

- Initial menu bar manager: │ divider + **BK** control
- Click to collapse / expand icons left of the divider
- Settings window and basic preferences
- App icon, ad-hoc signed `BarKeep.app` via `./build-app.sh`
