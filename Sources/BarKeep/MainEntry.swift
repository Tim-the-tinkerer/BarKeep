import AppKit
import SwiftUI

/// Strongly retained for the process lifetime. `NSApplication.delegate` is weak.
private enum AppOwnership {
    static var delegate: AppDelegate?
}

private extension Notification.Name {
    static let barKeepActivateExisting = Notification.Name("com.barkeep.app.activateExisting")
}

@main
struct MainEntry {
    static func main() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                // Ask the running instance to present UI, then exit.
                DistributedNotificationCenter.default().postNotificationName(
                    .barKeepActivateExisting,
                    object: bundleID,
                    userInfo: nil,
                    deliverImmediately: true
                )
                others.first?.activate(options: [.activateIgnoringOtherApps])
                exit(0)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppOwnership.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private let hotkeyManager = HotkeyManager()
    private var settings = AppSettings.load()
    private var settingsObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let manager = MenuBarManager(settings: settings)
        menuBarManager = manager
        manager.start()

        configureHotkey()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .barKeepSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.settings = AppSettings.load()
                self?.configureHotkey()
            }
        }

        activateObserver = DistributedNotificationCenter.default().addObserver(
            forName: .barKeepActivateExisting,
            object: Bundle.main.bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.menuBarManager?.showSettingsWindow()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let activateObserver {
            DistributedNotificationCenter.default().removeObserver(activateObserver)
        }
        hotkeyManager.unregister()
        menuBarManager?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarManager?.showSettingsWindow()
        return false
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "BarKeep")
        appMenuItem.submenu = appMenu

        let about = appMenu.addItem(
            withTitle: "About BarKeep",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self

        let checkUpdates = appMenu.addItem(
            withTitle: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkUpdates.target = self

        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = appMenu.addItem(
            withTitle: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit BarKeep",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let helpMenuItem = NSMenuItem()
        mainMenu.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu

        let helpItem = helpMenu.addItem(
            withTitle: "BarKeep Help",
            action: #selector(openHelp),
            keyEquivalent: "?"
        )
        helpItem.keyEquivalentModifierMask = .command
        helpItem.target = self

        let tipsItem = helpMenu.addItem(
            withTitle: "How to Arrange Icons…",
            action: #selector(openArrangeTips),
            keyEquivalent: ""
        )
        tipsItem.target = self

        helpMenu.addItem(NSMenuItem.separator())

        let githubItem = helpMenu.addItem(
            withTitle: "BarKeep on GitHub…",
            action: #selector(openGitHub),
            keyEquivalent: ""
        )
        githubItem.target = self

        let releasesItem = helpMenu.addItem(
            withTitle: "Release Notes on GitHub…",
            action: #selector(openReleases),
            keyEquivalent: ""
        )
        releasesItem.target = self

        NSApp.mainMenu = mainMenu
    }

    private func configureHotkey() {
        hotkeyManager.setEnabled(settings.hotkeyEnabled) { [weak self] in
            self?.menuBarManager?.toggleHiddenSection()
        }
    }

    @objc private func openSettings() {
        menuBarManager?.showSettingsWindow()
    }

    @objc private func openHelp() {
        HelpPresenter.showHelp()
    }

    @objc private func openArrangeTips() {
        menuBarManager?.showOnboarding()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.checkForUpdates(interactive: true)
    }

    @objc private func openGitHub() {
        UpdateChecker.openRepository()
    }

    @objc private func openReleases() {
        UpdateChecker.openReleases()
    }

    @objc private func showAbout() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.3"
        let build = info?["CFBundleVersion"] as? String ?? "9"
        let alert = NSAlert()
        alert.messageText = "BarKeep"
        alert.informativeText = """
        Version \(version) (\(build))

        A menu bar manager for macOS. Hide seldom-used status icons behind a chevron, then reveal them with a click or ⌃⌘B.

        Hold ⌘ and drag icons to arrange what stays visible.

        Updates & source: \(UpdateChecker.repositoryURL.absoluteString)
        """
        alert.alertStyle = .informational
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Check for Updates…")
        alert.addButton(withTitle: "GitHub…")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            UpdateChecker.checkForUpdates(interactive: true)
        } else if response == .alertThirdButtonReturn {
            UpdateChecker.openRepository()
        }
    }
}
