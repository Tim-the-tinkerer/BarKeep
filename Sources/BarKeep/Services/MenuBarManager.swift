import AppKit
import SwiftUI
import BarKeepCore

/// Hidden Bar–style menu bar manager (Tahoe-hardened).
///
/// ```
/// [ apps to hide ]  │  BK  [ system: Wi‑Fi … Clock ]
/// ```
///
/// Collapse sets the divider `NSStatusItem.length` to 10 000 pt so every item
/// ordered left of │ is pushed off-screen. Excluded apps belong in the keepers
/// zone between │ and BK so they stay visible. On macOS 26 status items are
/// hosted by Control Center scenes; preferred positions must stay valid.
@MainActor
final class MenuBarManager: NSObject {
    private enum Lengths {
        static let control: CGFloat = 36
        /// Thin visible mark when expanded. `variableLength` is unreliable for a
        /// glyph-only item after a 10k collapse on Tahoe, so use a fixed slot.
        static let dividerExpanded: CGFloat = 16
        /// System hard maximum for `NSStatusItem.length` (Hidden Bar / menubar-hide).
        static let collapsed: CGFloat = 10_000
    }

    private enum Autosave {
        static let control = "barkeep_control"
        static let divider = "barkeep_divider"
    }

    private enum Prefs {
        static let collapsed = "barKeepIsCollapsed"
        static let seededPlacement = "barKeepDidSeedPlacement"
    }

    /// Preferred-position defaults. Higher value = further left.
    /// Divider must be strictly greater (left of) control. Gap grows when the
    /// exclusions list needs a keepers zone between │ and BK.
    private enum Seed {
        static let control: Double = 250
        static let divider: Double = 265
        static let minGap: Double = 10
        /// When there are no exclusions, keep │ flush against BK.
        static let maxGapWithoutExclusions: Double = 40
    }

    private(set) var settings: AppSettings
    private var isCollapsed = false
    private var isToggling = false

    private var controlItem: NSStatusItem?
    private var dividerItem: NSStatusItem?

    private var autoHideTimer: Timer?
    private var hoverMonitor: EventMonitor?
    private var screenObserver: NSObjectProtocol?

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        // Pin positions BEFORE creating items (Tahoe parks new items off-screen
        // on a full bar, and a previous collapse can scramble saved order).
        pinPreferredPositions(reason: "start")
        installControlItems()
        observeScreenChanges()

        // Always begin expanded so a previous broken collapse cannot hide BK.
        UserDefaults.standard.set(false, forKey: Prefs.collapsed)
        isCollapsed = false
        applyExpanded()
        pinControlAppearance()
        configureHover()

        logGeometry("start-expanded")

        if !settings.exclusions.isEmpty {
            applyExclusionsLayout(reason: "start")
        }

        // Optional: collapse after layout settles (user preference).
        if settings.startCollapsed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self, !self.isCollapsed else { return }
                self.collapse(reason: "startCollapsed")
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
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        if isCollapsed {
            isCollapsed = false
            UserDefaults.standard.set(false, forKey: Prefs.collapsed)
            dividerItem?.length = Lengths.dividerExpanded
        }

        // Preserve last good preferred positions across remove.
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
        let exclusionsChanged = settings.exclusions != newSettings.exclusions
        settings = newSettings
        settings.save()

        if hoverChanged || newSettings.showOnHover {
            configureHover()
        }

        if exclusionsChanged {
            applyExclusionsLayout(reason: "settings")
        }

        if settings.autoHide && !isCollapsed {
            scheduleAutoHide()
        } else {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        }
        NotificationCenter.default.post(name: .barKeepSettingsChanged, object: nil)
    }

    /// Open keepers gap for exclusions and write preferred positions for listed apps.
    func applyExclusionsLayout(reason: String) {
        let count = settings.exclusions.count
        let gap = ExclusionPlacer.ensureKeepersGap(
            controlKey: preferredKey(Autosave.control),
            dividerKey: preferredKey(Autosave.divider),
            exclusionCount: count
        )
        // Re-read after ensure — pinPreferredPositions may further normalize.
        let pinned = pinPreferredPositions(reason: "exclusions-\(reason)")
        let controlPos = pinned.control
        let dividerPos = max(pinned.divider, gap.divider)

        if count > 0 {
            setPreferredPosition(Autosave.divider, value: dividerPos)
            let result = ExclusionPlacer.placeExclusions(
                settings.exclusions,
                controlPosition: controlPos,
                dividerPosition: dividerPos
            )
            NSLog(
                "BarKeep: keepers apply (%@) count=%d appsTouched=%d keys=%d noKeys=%@ gap=%.0f…%.0f",
                reason, count, result.appsTouched, result.keysUpdated,
                result.appsWithoutKeys.joined(separator: ","),
                controlPos, dividerPos
            )
        } else {
            NSLog("BarKeep: keepers cleared (%@); tight gap control=%.0f divider=%.0f", reason, controlPos, dividerPos)
        }

        // Best-effort: if we can still see a listed app left of │, log a ⌘-drag hint.
        if !isCollapsed, let dividerX = dividerItem?.button?.window?.frame.minX {
            let misplaced = settings.exclusions.filter {
                MenuBarAppScanner.exclusionWindowsLeftOf(dividerX: dividerX, exclusion: $0)
            }
            if !misplaced.isEmpty {
                NSLog(
                    "BarKeep: keepers still left of │ (⌘-drag into zone): %@",
                    misplaced.map(\.name).joined(separator: ", ")
                )
            }
        }
    }

    // MARK: - Preferred positions

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

    /// Ensure divider preferred position is left of (greater than) control.
    /// Gap size depends on exclusion count (keepers zone).
    @discardableResult
    private func pinPreferredPositions(reason: String) -> (control: Double, divider: Double) {
        let d = UserDefaults.standard
        let storedC = d.object(forKey: preferredKey(Autosave.control)) as? Double
        let storedD = d.object(forKey: preferredKey(Autosave.divider)) as? Double
        let exclusionCount = settings.exclusions.count
        let minGap = Seed.minGap + Double(exclusionCount) * 28
        let maxGap = exclusionCount == 0
            ? Seed.maxGapWithoutExclusions
            : max(minGap + 20, Double(exclusionCount) * 40 + 30)

        let controlPos: Double
        let dividerPos: Double

        if let c = storedC, let s = storedD,
           c > 0, s > 0, c <= 10_000, s <= 10_000,
           s > c,
           (s - c) >= minGap, (s - c) <= maxGap {
            controlPos = c
            dividerPos = s
            NSLog("BarKeep: positions ok (%@) control=%.0f divider=%.0f excl=%d", reason, c, s, exclusionCount)
        } else if let c = storedC, let s = storedD,
                  c > 0, s > 0, c <= 10_000, s <= 10_000, s > c {
            // Order ok but gap wrong for current exclusion count.
            controlPos = c
            dividerPos = c + minGap
            NSLog(
                "BarKeep: adjust gap (%@) control=%.0f divider=%.0f→%.0f excl=%d",
                reason, c, s, dividerPos, exclusionCount
            )
        } else {
            let plan = ExclusionPlacer.keepersGap(exclusionCount: exclusionCount)
            controlPos = plan.control
            dividerPos = plan.divider
            NSLog(
                "BarKeep: reset positions (%@) excl=%d control=%.0f divider=%.0f",
                reason, exclusionCount, controlPos, dividerPos
            )
        }

        setPreferredPosition(Autosave.control, value: controlPos)
        setPreferredPosition(Autosave.divider, value: dividerPos)
        d.set(true, forKey: Prefs.seededPlacement)
        return (controlPos, dividerPos)
    }

    // MARK: - Install

    private func installControlItems() {
        // Creation order: control first (tends right), divider second (tends left).
        let control = NSStatusBar.system.statusItem(withLength: Lengths.control)
        control.autosaveName = NSStatusItem.AutosaveName(Autosave.control)
        control.isVisible = true
        if let button = control.button {
            button.target = self
            button.action = #selector(controlClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("BarKeep")
            button.setAccessibilityRole(.button)
            button.setAccessibilityHelp(
                "Left-click to hide or show menu bar icons left of the divider. Right-click for the menu."
            )
        }
        controlItem = control

        let divider = NSStatusBar.system.statusItem(withLength: Lengths.dividerExpanded)
        divider.autosaveName = NSStatusItem.AutosaveName(Autosave.divider)
        divider.isVisible = true
        if let button = divider.button {
            button.setAccessibilityLabel("BarKeep hide boundary")
            button.setAccessibilityHelp(
                "Command-drag app icons fully left of this mark to hide them when collapsed."
            )
        }
        dividerItem = divider

        applyExpanded()
        pinControlAppearance()
    }

    // MARK: - Toggle

    func toggleHiddenSection() {
        guard !isToggling else { return }
        isToggling = true
        if isCollapsed {
            expand(reason: "toggle")
        } else {
            collapse(reason: "toggle")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isToggling = false
        }
    }

    // MARK: - Collapse / expand

    private var isMouseInMenuBar: Bool {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.contains { screen in
            mouse.x >= screen.frame.minX
                && mouse.x <= screen.frame.maxX
                && mouse.y >= screen.visibleFrame.maxY
                && mouse.y <= screen.frame.maxY
        }
    }

    /// On-screen: divider must sit left of BK (smaller X).
    private var isDividerLeftOfControlOnScreen: Bool? {
        guard
            let controlX = controlItem?.button?.window?.frame.minX,
            let dividerX = dividerItem?.button?.window?.frame.minX
        else { return nil }
        return dividerX <= controlX + 2
    }

    private func observeScreenChanges() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isCollapsed {
                    self.dividerItem?.length = Lengths.collapsed
                    self.pinControlAppearance()
                }
            }
        }
    }

    private func collapse(reason: String) {
        guard !isCollapsed else { return }

        // If on-screen order is wrong, fix positions and recreate before hiding.
        if let ok = isDividerLeftOfControlOnScreen, !ok {
            NSLog("BarKeep: on-screen order wrong before collapse (%@); repairing", reason)
            repairPlacementAndRestart(collapsedAfter: true)
            return
        }

        // Keep exclusion gap / preferred positions current before inflating spacer.
        if !settings.exclusions.isEmpty {
            applyExclusionsLayout(reason: "pre-collapse")
        }

        isCollapsed = true
        UserDefaults.standard.set(true, forKey: Prefs.collapsed)

        // Do not thrash isVisible / length on the control during collapse — only
        // inflate the divider. Menubar-hide: never use isVisible to hide icons.
        dividerItem?.length = Lengths.collapsed
        if let button = dividerItem?.button {
            button.title = ""
            button.image = nil
            button.isHighlighted = false
        }
        pinControlAppearance()

        logGeometry("collapsed:\(reason)")

        // Re-assert after layout settles (Control Center scene hosts can lag).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCollapsed else { return }
            if self.dividerItem?.length != Lengths.collapsed {
                self.dividerItem?.length = Lengths.collapsed
            }
            self.pinControlAppearance()
            self.logGeometry("collapsed-async:\(reason)")
        }

        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func expand(reason: String) {
        guard isCollapsed else { return }
        isCollapsed = false
        UserDefaults.standard.set(false, forKey: Prefs.collapsed)
        applyExpanded()
        pinControlAppearance()
        // Collapse/expand can scramble preferred positions on Tahoe — re-pin values
        // without destroying user placement when the pair is still valid.
        pinPreferredPositions(reason: "after-expand")

        if settings.autoHide {
            scheduleAutoHide()
        }
        logGeometry("expanded:\(reason)")
    }

    private func applyExpanded() {
        dividerItem?.isVisible = true
        dividerItem?.length = Lengths.dividerExpanded
        if let button = dividerItem?.button {
            button.title = "│"
            button.font = NSFont.systemFont(ofSize: 14, weight: .bold)
            button.image = nil
            button.toolTip = "Hide boundary — ⌘-drag app icons fully LEFT of this line"
        }
    }

    /// Keep BK visible and labeled. Avoid resetting divider length here.
    private func pinControlAppearance() {
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

    private func logGeometry(_ tag: String) {
        let cFrame = controlItem?.button?.window?.frame
        let dFrame = dividerItem?.button?.window?.frame
        let cLen = controlItem?.length ?? -1
        let dLen = dividerItem?.length ?? -1
        let cPos = preferredPosition(Autosave.control) ?? -1
        let dPos = preferredPosition(Autosave.divider) ?? -1
        NSLog(
            "BarKeep: [%@] collapsed=%d cLen=%.0f dLen=%.0f cPos=%.0f dPos=%.0f cWin=%@ dWin=%@",
            tag,
            isCollapsed ? 1 : 0,
            cLen, dLen, cPos, dPos,
            cFrame.map { NSStringFromRect($0) } ?? "nil",
            dFrame.map { NSStringFromRect($0) } ?? "nil"
        )
    }

    /// Recreate status items after fixing preferred positions.
    private func repairPlacementAndRestart(collapsedAfter: Bool) {
        UserDefaults.standard.removeObject(forKey: preferredKey(Autosave.control))
        UserDefaults.standard.removeObject(forKey: preferredKey(Autosave.divider))
        UserDefaults.standard.set(false, forKey: Prefs.seededPlacement)
        pinPreferredPositions(reason: "repair")

        let wasSettings = settings
        stop()
        settings = wasSettings
        installControlItems()
        observeScreenChanges()
        isCollapsed = false
        applyExpanded()
        pinControlAppearance()
        configureHover()

        if collapsedAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.collapse(reason: "repair")
            }
        }
    }

    // MARK: - Clicks

    @objc private func controlClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleHiddenSection()
            return
        }
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

        let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckUpdates), keyEquivalent: "")
        checkUpdates.target = self
        checkUpdates.isEnabled = true
        menu.addItem(checkUpdates)

        let github = NSMenuItem(title: "BarKeep on GitHub…", action: #selector(menuOpenGitHub), keyEquivalent: "")
        github.target = self
        github.isEnabled = true
        menu.addItem(github)

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

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func menuToggle() { toggleHiddenSection() }
    @objc private func menuSettings() { showSettingsWindow() }
    @objc private func menuCheckUpdates() { UpdateChecker.checkForUpdates(interactive: true) }
    @objc private func menuOpenGitHub() { UpdateChecker.openRepository() }
    @objc private func menuHelpBook() { HelpPresenter.showHelp() }
    @objc private func menuHelp() { showOnboarding() }

    func showHelp() {
        HelpPresenter.showHelp()
    }

    @objc private func menuResetPosition() {
        let alert = NSAlert()
        alert.messageText = "Reset BarKeep position?"
        alert.informativeText = """
        Moves │ and BK next to each other, just left of the system icon area.

        Then ⌘-drag app icons you want hidden fully LEFT of │. Icons between │ and BK stay visible; system icons should sit RIGHT of BK.
        """
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        repairPlacementAndRestart(collapsedAfter: false)
    }

    // MARK: - Settings window

    func showSettingsWindow() {
        let makeView = { [weak self] () -> SettingsView in
            SettingsView(
                settings: self?.settings ?? .default,
                onChange: { [weak self] updated in self?.applySettings(updated) },
                onClose: { [weak self] in self?.settingsWindow?.close() },
                onExclusionsChanged: { [weak self] in
                    self?.applyExclusionsLayout(reason: "settings-ui")
                }
            )
        }

        if let settingsWindow {
            settingsWindow.contentViewController = NSHostingController(rootView: makeView())
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: makeView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
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
        autoHideTimer = nil
        guard settings.autoHide else { return }
        let interval = max(1, min(settings.autoHideSeconds, 600))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settings.autoHide, !self.isCollapsed else { return }
                if self.isMouseInMenuBar || (self.settingsWindow?.isVisible == true) {
                    self.scheduleAutoHide()
                    return
                }
                self.collapse(reason: "autoHide")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoHideTimer = timer
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
                    self.expand(reason: "hover")
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
            // Keep window for reuse; content is refreshed on next show.
        }
    }
}
