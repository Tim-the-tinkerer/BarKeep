# BarKeep

A lightweight **menu bar manager for macOS** — similar in spirit to Bartender, Ice, or Hidden Bar. Hide seldom-used status icons behind a chevron, then show them again with a click or **⌃⌘B**.

**Version 1.2.3** · **Apple Silicon** · macOS 13+ · menu-bar only (no Dock icon)

**Updates & source:** [github.com/Tim-the-tinkerer/BarKeep](https://github.com/Tim-the-tinkerer/BarKeep) — use **Check for Updates…** in the app (right-click BK or Settings).

## Features

- **Hide & show** menu bar app icons with **│** + **BK**
- **⌘-drag arrangement** — icons left of │ hide when collapsed; icons right of BK stay
- **Keepers list** — reserve the zone between │ and BK and *attempt* placement for chosen apps (not fully automatic; see below)
- **Global hotkey** `⌃⌘B` to toggle
- **Auto-hide** after a delay (optional)
- **Show on hover** over the menu bar (optional)
- **Launch at login**
- **In-app Help** (right-click BK → BarKeep Help…)
- No Accessibility or Screen Recording permission required

## Requirements

- **Apple Silicon** Mac (arm64 build; not a universal binary)
- macOS 13 Ventura or later
- Swift 5.9+ toolchain (Xcode or Command Line Tools) to build from source

## Build & run

```bash
cd ~/BarKeep
./build-app.sh
```

Builds a release **arm64** binary, assembles `BarKeep.app` (including the help book), **ad-hoc signs** it, and launches it.

```bash
./build-app.sh --no-launch   # build only
swift test                   # unit tests for pure logic
```

### Distribution note

Release builds are **ad-hoc signed** (not Developer ID + notarized). Downloads from GitHub may hit **Gatekeeper / quarantine** prompts (“cannot be opened because the developer cannot be verified”). That is expected for a personal, unsigned-for-distribution utility: right-click → Open, or clear quarantine after you trust the binary. Frictionless public install would need a paid Apple Developer ID and notarization.

## How to use

1. Launch **BarKeep** — **│** and **BK** appear in the menu bar.
2. Hold **⌘** and drag:
   - **App icons you want hidden** → fully **left of │**
   - **System icons** (Wi‑Fi, Bluetooth, Sound, Clock, …) → **right of BK**
3. **Click BK** (or press **⌃⌘B**) to collapse / expand.
4. **Right-click BK** for Settings, Help, Reset Position, and Quit.

```
[ hide these apps ]  │  [ keepers ]  BK  [ Wi‑Fi … Clock ]
```

## Settings

| Option | Default | Description |
|--------|---------|-------------|
| Start collapsed | Off | After launch, wait for icons to settle, then collapse |
| Auto-hide | Off | Collapse again after a delay when expanded |
| Show on hover | Off | Expand when the pointer is in the right half of the menu bar |
| Keepers | Empty | Reserve │–BK zone and *attempt* to place listed apps there |
| Launch at login | Off | Start with your Mac |
| Global hotkey ⌃⌘B | On | Toggle from the keyboard |
| Check for Updates… | — | Compares your version to the latest GitHub release |

### Keepers (not fully automatic)

BarKeep can **reserve** space between │ and BK and may write another app’s existing `NSStatusItem Preferred Position` keys via **CFPreferences only** (no full preference-plist rewrite). Live icons often move only after that app **relaunches**, and apps without a named status item **cannot** be positioned programmatically. The reliable step remains **⌘-dragging** the icon into the keepers zone once.

Conceptually: *“Reserve keeper positions and attempt to place these apps there.”*

## How it works

BarKeep uses the same public-API approach as Hidden Bar and Ice: when collapsed, a divider status item’s length expands so items to its **left** are pushed off-screen. Expanding restores a thin │. Your ⌘-drag order is stored by macOS; BarKeep seeds its own position once and does not rewrite it every launch.

## Project layout

```
BarKeep/
  Package.swift
  AppInfo.plist
  build-app.sh
  CHANGELOG.md
  README.md
  Help/BarKeep.help/
  Sources/BarKeepCore/        # pure logic (tested)
  Sources/BarKeep/            # app UI & status items
  Tests/BarKeepTests/
  Scripts/GenerateAppIcon.swift
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

Personal use. Not affiliated with Bartender, Ice, or Hidden Bar.
