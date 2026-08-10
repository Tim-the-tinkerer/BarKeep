# Changelog

All notable changes to **BarKeep** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/).

## [1.2.2] - 2026-08-09

### Added

- **Check for Updates…** via GitHub Releases (`https://github.com/Tim-the-tinkerer/BarKeep`)
- Menu items: app menu, BK right-click menu, Help → GitHub / Releases
- Settings → Updates: check, open repo, open releases

## [1.2.1] - 2026-08-09

### Fixed

- **Exclusions list empty on Tahoe**: status item windows are hosted by Control Center, so window-list discovery found nothing. Candidates now come from running menu bar utilities (`LSUIElement` / accessory apps), status-item preference domains, and a manual “Add by name” field

## [1.2.0] - 2026-08-09

### Added

- **Exclusions list** (Settings → Always show): pick running menu bar apps that should stay visible when collapsed
- Opens a keepers zone between │ and BK sized for the exclusion count
- Writes those apps’ `NSStatusItem Preferred Position` prefs when possible (sticks after relaunch); ⌘-drag once if an app ignores prefs while running
- Refresh list + “Apply keepers zone” actions

## [1.1.3] - 2026-08-09

### Fixed

- **Hide zone was empty**: preferred-position gap between │ and BK had grown large (~200 units), so app icons sat *between* them and never entered the hide zone. │ is now kept flush left of BK (10–40 unit gap); oversized gaps are tightened on launch
- Collapse always uses the system max spacer (**10 000 pt**) instead of a derived width
- Re-pin / repair on-screen order if │ and BK swap (Tahoe scramble after collapse)
- Less thrashing of status-item visibility during collapse (Control Center hosts items as scenes on macOS 26)

## [1.1.2] - 2026-08-09

### Fixed

- **macOS Tahoe collapse**: spacer length uses widest attached screen × 2 (cap 10 000 pt), matching Hidden Bar — previous 3 500 pt cap often left icons only shifted, not hidden
- Refuse collapse when │ sits right of BK (would hide the control); log and keep BK clickable
- Auto-hide timer no longer double-scheduled; defers while the pointer is in the menu bar or Settings is open
- Re-apply collapse length on display layout changes
- Force status-item visibility on every pin (Tahoe can park new items off-screen when the bar is full)
- `startCollapsed` waits ~1.5s so late-launching icons can settle first

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
