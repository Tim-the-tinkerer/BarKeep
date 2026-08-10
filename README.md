# BarKeep

A lightweight **menu bar manager for macOS** — similar in spirit to Bartender, Ice, or Hidden Bar. Hide seldom-used status icons behind a chevron, then show them again with a click or **⌃⌘B**.

**Version 1.2.2** · macOS 13+ · menu-bar only (no Dock icon)

**Updates:** [github.com/Tim-the-tinkerer/BarKeep](https://github.com/Tim-the-tinkerer/BarKeep) — use **Check for Updates…** in the app (right-click BK or Settings).

## Features

- **Hide & show** menu bar app icons with **│** + **BK**
- **⌘-drag arrangement** — icons left of │ hide when collapsed; icons right of BK stay
- **Exclusions list** — pick apps that always stay visible (keepers zone between │ and BK)
- **Global hotkey** `⌃⌘B` to toggle
- **Auto-hide** after a delay (optional)
- **Show on hover** over the menu bar (optional)
- **Launch at login**
- **In-app Help** (right-click BK → BarKeep Help…)
- No Accessibility or Screen Recording permission required

## Requirements

- macOS 13 Ventura or later
- Swift 5.9+ toolchain (Xcode or Command Line Tools)

## Build & run

```bash
cd ~/BarKeep
./build-app.sh
```

Builds a release binary, assembles `BarKeep.app` (including the help book), ad-hoc signs it, and launches it.

```bash
./build-app.sh --no-launch   # build only
```

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
| Start collapsed | Off | After launch, wait ~1s for icons to settle, then collapse |
| Auto-hide | Off | Collapse again after a delay when expanded |
| Show on hover | Off | Expand when the pointer is in the right half of the menu bar |
| Exclusions | Empty | Apps that always stay visible (between │ and BK) |
| Launch at login | Off | Start with your Mac |
| Global hotkey ⌃⌘B | On | Toggle from the keyboard |

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
  Help/BarKeep.help/          # in-app help book
  Sources/BarKeep/
    MainEntry.swift
    Models/AppSettings.swift
    Services/MenuBarManager.swift
    Services/HotkeyManager.swift
    Services/EventMonitor.swift
    Services/LaunchAtLogin.swift
    Services/HelpPresenter.swift
    Views/SettingsView.swift
    Views/OnboardingView.swift
  Scripts/GenerateAppIcon.swift
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

Personal use. Not affiliated with Bartender, Ice, or Hidden Bar.
