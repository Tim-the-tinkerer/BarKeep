import AppKit
import SwiftUI

/// Hidden Bar–style menu bar manager.
///
/// ```
/// [ app icons to hide ]  │spacer│  BK  [ system: Wi‑Fi … Clock ]
/// ```
///
/// Collapse expands the divider length so icons left of it leave the bar.
/// Expand restores a thin │. BK is re-pinned after every length change.
@MainActor
final class MenuBarManager: NSObject {
    private enum Lengths {
        static let control: CGFloat = 40
        static let dividerExpanded: CGFloat = 18
        /// Ice / Hidden Bar use thousands of points so items fully leave the bar.
        static let collapsedMin: CGFloat = 1_000
        static let collapsedMax: CGFloat = 3_500
    }

    private enum Autosave {
        static let control = "barkeep_control"
        static let divider = "barkeep_divider"
    }

    private enum Prefs {
        static let collapsed = "barKeepIsCollapsed"
        static let seededPlacement = "barKeepDidSeedPlacement"
    }

    private(set) var settings: AppSettings
    private var isCollapsed = false
    private var isToggling = false

    private var controlItem: NSStatusItem?
    private var dividerItem: NSStatusItem?

    private var autoHideTimer: Timer?
    private var hoverMonitor: EventMonitor?

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        seedPlacementOnceIfNeeded()
        installControlItems()

        // Always begin expanded so a previous broken collapse cannot hide BK.
        UserDefaults.standard.set(false, forKey: Prefs.collapsed)
        isCollapsed = false
        applyExpanded()
        pinControl()
        configureHover()

        // Optional: collapse after layout settles (user preference).
        if settings.startCollapsed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, !self.isCollapsed else { return }
                self.collapse()
            }
        }

        if !settings.didShowOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    func stop() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        hoverMonitor?.stop()
        hoverMonitor = nil

        // Leave the menu bar clean if we were collapsed.
        if isCollapsed {
            isCollapsed = false
            UserDefaults.standard.set(false, forKey: Prefs.collapsed)
            dividerItem?.length = Lengths.dividerExpanded
        }

        let cPos = preferredPosition(Autosave.control)
        let dPos = preferredPosition(Autosave.divider)

        if let controlItem {
            NSStatusBar.system.removeStatusItem(controlItem)
        }
        if let dividerItem {
            NSStatusBar.system.removeStatusItem(dividerItem)
        }
        controlItem = nil
        dividerItem = nil

        if let cPos { setPreferredPosition(Autosave.control, value: cPos) }
        if let dPos { setPreferredPosition(Autosave.divider, value: dPos) }
    }

    func applySettings(_ newSettings: AppSettings) {
        let hoverChanged = settings.showOnHover != newSettings.showOnHover
        settings = newSettings
        settings.save()

        if hoverChanged || newSettings.showOnHover {
            configureHover()
        }

        if settings.autoHide && !isCollapsed {
            scheduleAutoHide()
        } else {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        }
        NotificationCenter.default.post(name: .barKeepSettingsChanged, object: nil)
    }

    // MARK: - Placement

    /// Lower preferredPosition = further right (near clock).
    private func seedPlacementOnceIfNeeded() {
        let d = UserDefaults.standard
        if d.bool(forKey: Prefs.seededPlacement),
           d.object(forKey: preferredKey(Autosave.control)) != nil {
            return
        }
        // Sit left of a typical system cluster (Sound/Wi‑Fi ~150–520).
        // Higher number = further left among status items.
        setPreferredPosition(Autosave.control, value: 540)
        setPreferredPosition(Autosave.divider, value: 541)
        d.set(true, forKey: Prefs.seededPlacement)
    }

    private func preferredKey(_ name: String) -> String {
        "NSStatusItem Preferred Position \(name)"
    }

    private func setPreferredPosition(_ name: String, value: Double) {
        UserDefaults.standard.set(value, forKey: preferredKey(name))
    }

    private func preferredPosition(_ name: String) -> Double? {
        guard UserDefaults.standard.object(forKey: preferredKey(name)) != nil else { return nil }
        return UserDefaults.standard.double(forKey: preferredKey(name))
    }

    // MARK: - Install

    private func installControlItems() {
        // Create control first → tends to sit further right (closer to clock)
        // than the divider created second.
        let control = NSStatusBar.system.statusItem(withLength: Lengths.control)
        control.autosaveName = NSStatusItem.AutosaveName(Autosave.control)
        control.isVisible = true
        if let button = control.button {
            button.target = self
            button.action = #selector(controlClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("BarKeep")
            button.setAccessibilityRole(.button)
            button.setAccessibilityHelp("Left-click to hide or show menu bar icons left of the divider. Right-click for the menu.")
        }
        controlItem = control

        let divider = NSStatusBar.system.statusItem(withLength: Lengths.dividerExpanded)
        divider.autosaveName = NSStatusItem.AutosaveName(Autosave.divider)
        divider.isVisible = true
        if let button = divider.button {
            button.setAccessibilityLabel("BarKeep hide boundary")
            button.setAccessibilityHelp("Command-drag app icons left of this mark to hide them when BarKeep is collapsed.")
        }
        dividerItem = divider

        pinControl()
        applyExpanded()
    }

    // MARK: - Toggle

    func toggleHiddenSection() {
        guard !isToggling else { return }
        isToggling = true
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.isToggling = false
        }
    }

    // MARK: - Collapse / expand

    private func collapseLength() -> CGFloat {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? controlItem?.button?.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let width = screen?.frame.width ?? 1440
        return max(Lengths.collapsedMin, min(width + 100, Lengths.collapsedMax))
    }

    private func collapse() {
        isCollapsed = true
        UserDefaults.standard.set(true, forKey: Prefs.collapsed)

        pinControl()

        let length = collapseLength()
        dividerItem?.isVisible = true
        dividerItem?.length = length
        if let button = dividerItem?.button {
            button.title = ""
            button.image = nil
            button.cell?.isEnabled = false
            button.isHighlighted = false
        }

        pinControl()
        NSLog("BarKeep: collapsed length=%.0f", length)

        DispatchQueue.main.async { [weak self] in
            self?.pinControl()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pinControl()
        }

        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func expand() {
        isCollapsed = false
        UserDefaults.standard.set(false, forKey: Prefs.collapsed)
        applyExpanded()
        pinControl()

        if settings.autoHide {
            scheduleAutoHide()
        }
        NSLog("BarKeep: expanded")
    }

    private func applyExpanded() {
        dividerItem?.isVisible = true
        dividerItem?.length = Lengths.dividerExpanded
        if let button = dividerItem?.button {
            button.cell?.isEnabled = true
            button.title = "│"
            button.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            button.image = nil
            button.toolTip = "Hide boundary — ⌘-drag app icons LEFT of this line"
        }
        pinControl()
    }

    /// Always keep the chevron/status control present and clickable.
    private func pinControl() {
        guard let control = controlItem else { return }
        control.isVisible = true
        control.length = Lengths.control
        if let button = control.button {
            button.isHidden = false
            button.alphaValue = 1
            button.image = controlImage(collapsed: isCollapsed)
            button.image?.isTemplate = true
            button.title = "BK"
            button.imagePosition = .imageLeading
            button.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            button.toolTip = isCollapsed
                ? "BarKeep — click to show icons"
                : "BarKeep — click to hide icons left of │"
            button.setAccessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
        }
    }

    private func controlImage(collapsed: Bool) -> NSImage? {
        let name = collapsed ? "chevron.left.circle.fill" : "chevron.right.circle.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "BarKeep") else {
            return nil
        }
        let img = base.withSymbolConfiguration(config) ?? base
        img.isTemplate = true
        return img
    }

    // MARK: - Clicks

    @objc private func controlClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleHiddenSection()
            return
        }
        // Right-click or Control-click → menu (not toggle).
        if event.type == .rightMouseUp
            || event.type == .rightMouseDown
            || event.modifierFlags.contains(.control) {
            showControlMenu(relativeTo: sender, with: event)
            return
        }
        toggleHiddenSection()
    }

    private func showControlMenu(relativeTo button: NSStatusBarButton, with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggle = NSMenuItem(
            title: isCollapsed ? "Show Hidden Icons" : "Hide Icons Left of │",
            action: #selector(menuToggle),
            keyEquivalent: ""
        )
        toggle.target = self
        toggle.isEnabled = true
        menu.addItem(toggle)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        let helpBook = NSMenuItem(title: "BarKeep Help…", action: #selector(menuHelpBook), keyEquivalent: "")
        helpBook.target = self
        helpBook.isEnabled = true
        menu.addItem(helpBook)

        let tips = NSMenuItem(title: "How to Arrange Icons…", action: #selector(menuHelp), keyEquivalent: "")
        tips.target = self
        tips.isEnabled = true
        menu.addItem(tips)

        let reset = NSMenuItem(title: "Reset BarKeep Position…", action: #selector(menuResetPosition), keyEquivalent: "")
        reset.target = self
        reset.isEnabled = true
        menu.addItem(reset)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BarKeep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.isEnabled = true
        menu.addItem(quit)

        // popUpContextMenu is more reliable than attach-menu + performClick.
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func menuToggle() { toggleHiddenSection() }
    @objc private func menuSettings() { showSettingsWindow() }
    @objc private func menuHelpBook() { HelpPresenter.showHelp() }
    @objc private func menuHelp() { showOnboarding() }

    func showHelp() {
        HelpPresenter.showHelp()
    }

    @objc private func menuResetPosition() {
        let alert = NSAlert()
        alert.messageText = "Reset BarKeep position?"
        alert.informativeText = "Moves │ and BK just left of the system icon area. Other apps keep their order."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        UserDefaults.standard.removeObject(forKey: preferredKey(Autosave.control))
        UserDefaults.standard.removeObject(forKey: preferredKey(Autosave.divider))
        UserDefaults.standard.set(false, forKey: Prefs.seededPlacement)
        UserDefaults.standard.set(false, forKey: Prefs.collapsed)
        seedPlacementOnceIfNeeded()

        stop()
        installControlItems()
        isCollapsed = false
        applyExpanded()
        pinControl()
        configureHover()
    }

    // MARK: - Settings window

    func showSettingsWindow() {
        if let settingsWindow {
            // Refresh content so reopen after changes is not stale.
            let view = SettingsView(
                settings: settings,
                onChange: { [weak self] updated in self?.applySettings(updated) },
                onClose: { [weak self] in self?.settingsWindow?.close() }
            )
            settingsWindow.contentViewController = NSHostingController(rootView: view)
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(
            settings: settings,
            onChange: { [weak self] updated in self?.applySettings(updated) },
            onClose: { [weak self] in self?.settingsWindow?.close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BarKeep Settings"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Auto-hide / hover

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        guard settings.autoHide else { return }
        let interval = max(1, min(settings.autoHideSeconds, 600))
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if self?.isCollapsed == false {
                    self?.collapse()
                }
            }
        }
        if let autoHideTimer {
            RunLoop.main.add(autoHideTimer, forMode: .common)
        }
    }

    private func configureHover() {
        hoverMonitor?.stop()
        hoverMonitor = nil
        guard settings.showOnHover else { return }
        hoverMonitor = EventMonitor(mask: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settings.showOnHover else { return }
                let loc = NSEvent.mouseLocation
                guard let screen = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) })
                        ?? NSScreen.main
                else { return }
                guard loc.y >= screen.frame.maxY - 28, loc.x > screen.frame.midX else { return }
                if self.isCollapsed {
                    self.expand()
                } else if self.settings.autoHide {
                    self.scheduleAutoHide()
                }
            }
        }
        hoverMonitor?.start()
    }

    // MARK: - Onboarding

    func showOnboarding() {
        if let onboardingWindow, onboardingWindow.isVisible {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(onDone: { [weak self] in
            guard let self else { return }
            var s = self.settings
            s.didShowOnboarding = true
            self.applySettings(s)
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
        })
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "How BarKeep Works"
        window.contentViewController = hosting
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}

// MARK: - NSWindowDelegate

extension MenuBarManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            // Keep window for reuse but content is refreshed on next show.
        }
    }
}
