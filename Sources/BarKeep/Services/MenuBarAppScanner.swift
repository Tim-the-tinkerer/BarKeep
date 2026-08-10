import AppKit
import CoreGraphics
import Foundation

/// A third-party (or user) app that is a candidate for the exclusions list.
struct MenuBarApp: Equatable, Identifiable, Hashable {
    var id: String { bundleIdentifier ?? "name:\(name)" }
    var name: String
    var bundleIdentifier: String?
    /// How many status-item-sized windows we attributed to this owner (0 if inferred only).
    var statusItemCount: Int
    /// Where we learned about this app.
    var source: Source

    enum Source: String, Equatable, Hashable {
        case windowList
        case accessoryProcess
        case statusItemPrefs
        case manual
    }
}

/// Discovers apps that likely own menu bar status items.
///
/// On macOS Tahoe, third-party status item *windows* are often hosted under
/// Control Center, so `CGWindowList` owner names are useless. We therefore
/// combine three signals:
/// 1. Accessory (`LSUIElement`) running processes (typical menu bar apps)
/// 2. Preference domains that already store `NSStatusItem Preferred Position`
/// 3. Any non-system window-list owners still visible in the menu bar band
enum MenuBarAppScanner {
    private static let positionKeyPrefix = "NSStatusItem Preferred Position "

    private static let ignoredBundlePrefixes: [String] = [
        "com.apple.",
        "com.applee.", // typo-safe no-op
    ]

    private static let ignoredBundleIDs: Set<String> = [
        "com.barkeep.app",
        "com.apple.loginwindow",
        "com.apple.dock",
        "com.apple.dock.extra",
        "com.apple.dock.helper",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.WindowManager",
        "com.apple.wallpaper.agent",
        "com.apple.ViewBridgeAuxiliary",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.wifi.WiFiAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.backgroundtaskmanagement.agent",
        "com.apple.CoreSimulator.CoreSimulatorService",
        "com.apple.CoreSimulator.SimulatorTrampoline",
    ]

    private static let ignoredNames: Set<String> = [
        "Window Server", "WindowServer", "Control Center", "SystemUIServer",
        "BarKeep", "Notification Center", "Spotlight", "Dock", "loginwindow",
        "TextInputMenuAgent", "WiFiAgent", "BentoBox", "Finder",
        "ViewBridgeAuxiliary", "Wallpaper", "WindowManager",
    ]

    /// Best-effort list of exclusion candidates, newest scan each call.
    static func runningMenuBarApps() -> [MenuBarApp] {
        var byKey: [String: MenuBarApp] = [:]

        func upsert(_ app: MenuBarApp) {
            guard !shouldIgnore(name: app.name, bundleIdentifier: app.bundleIdentifier) else { return }
            let key = app.bundleIdentifier ?? app.id
            if let existing = byKey[key] {
                // Prefer richer metadata / higher window counts.
                byKey[key] = MenuBarApp(
                    name: existing.name.count >= app.name.count ? existing.name : app.name,
                    bundleIdentifier: existing.bundleIdentifier ?? app.bundleIdentifier,
                    statusItemCount: max(existing.statusItemCount, app.statusItemCount),
                    source: rank(existing.source) >= rank(app.source) ? existing.source : app.source
                )
            } else {
                byKey[key] = app
            }
        }

        for app in appsFromAccessoryProcesses() { upsert(app) }
        for app in appsFromStatusItemPreferences() { upsert(app) }
        for app in appsFromWindowList() { upsert(app) }

        return byKey.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Whether any status-item window for this exclusion sits left of `dividerX`.
    /// On Tahoe this often cannot see third-party windows (hosted by Control Center).
    static func exclusionWindowsLeftOf(dividerX: CGFloat, exclusion: ExclusionEntry) -> Bool {
        let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for w in info {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            let pid = w[kCGWindowOwnerPID as String] as? pid_t
            let bid = bundleID(forPID: pid)
            let matches: Bool
            if let eb = exclusion.bundleIdentifier, let bid, eb == bid {
                matches = true
            } else {
                matches = owner.caseInsensitiveCompare(exclusion.name) == .orderedSame
            }
            guard matches else { continue }

            let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let height = bounds["Height"] ?? 0
            let x = bounds["X"] ?? 0
            let width = bounds["Width"] ?? 0
            guard height > 0, height <= 48 else { continue }
            if x + width / 2 < dividerX - 2 {
                return true
            }
        }
        return false
    }

    // MARK: - Sources

    /// LSUIElement / accessory apps currently running — primary signal on Tahoe.
    private static func appsFromAccessoryProcesses() -> [MenuBarApp] {
        var out: [MenuBarApp] = []
        for app in NSWorkspace.shared.runningApplications {
            // Menu bar utilities are almost always `.accessory` (LSUIElement).
            // Also accept `.regular` only when they already have status-item prefs
            // (handled elsewhere); here stick to accessory to avoid listing every GUI app.
            guard app.activationPolicy == .accessory else { continue }
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bid = app.bundleIdentifier
            guard !name.isEmpty else { continue }
            // Skip XPC helpers / agents that are not user-facing menu extras.
            if let bid {
                let lower = bid.lowercased()
                if lower.contains(".xpc")
                    || lower.contains("plugincontainer")
                    || lower.contains("viewservice")
                    || lower.contains("widgetextension")
                    || lower.contains("uikitsystem")
                    || lower.hasPrefix("com.apple.") {
                    continue
                }
            }

            out.append(MenuBarApp(
                name: name,
                bundleIdentifier: bid,
                statusItemCount: 0,
                source: .accessoryProcess
            ))
        }
        return out
    }

    /// Domains under ~/Library/Preferences that already store status-item positions.
    private static func appsFromStatusItemPreferences() -> [MenuBarApp] {
        let fm = FileManager.default
        let prefs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
        guard let files = try? fm.contentsOfDirectory(
            at: prefs,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var out: [MenuBarApp] = []
        for url in files where url.pathExtension == "plist" {
            let domain = url.deletingPathExtension().lastPathComponent
            guard !shouldIgnore(name: domain, bundleIdentifier: domain) else { continue }
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { continue }
            let keys = dict.keys.filter { $0.hasPrefix(positionKeyPrefix) }
            guard !keys.isEmpty else { continue }

            let name = displayName(forBundleID: domain) ?? friendlyName(fromDomain: domain)
            out.append(MenuBarApp(
                name: name,
                bundleIdentifier: domain,
                statusItemCount: keys.count,
                source: .statusItemPrefs
            ))
        }
        return out
    }

    /// Fallback: owners still visible as their own process in the menu bar strip.
    private static func appsFromWindowList() -> [MenuBarApp] {
        let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var bundles: [String: String] = [:]

        for w in info {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            guard !owner.isEmpty, !ignoredNames.contains(owner) else { continue }

            let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let height = bounds["Height"] ?? 0
            let width = bounds["Width"] ?? 0
            let y = bounds["Y"] ?? 9999
            // Status items are short. Accept y≈0 (CG) or Cocoa menu-bar band.
            guard height > 2, height <= 48, width > 4, width <= 500 else { continue }
            guard y <= 80 || isInMenuBarBand(y: y, height: height) else { continue }

            let pid = w[kCGWindowOwnerPID as String] as? pid_t
            let bid = bundleID(forPID: pid)
            let key = bid ?? "name:\(owner)"
            counts[key, default: 0] += 1
            names[key] = owner
            if let bid { bundles[key] = bid }
        }

        return counts.map { key, count in
            MenuBarApp(
                name: names[key] ?? key,
                bundleIdentifier: bundles[key],
                statusItemCount: count,
                source: .windowList
            )
        }
    }

    // MARK: - Helpers

    private static func rank(_ source: MenuBarApp.Source) -> Int {
        switch source {
        case .windowList: return 3
        case .statusItemPrefs: return 2
        case .accessoryProcess: return 1
        case .manual: return 0
        }
    }

    private static func shouldIgnore(name: String, bundleIdentifier: String?) -> Bool {
        if ignoredNames.contains(name) { return true }
        if name.caseInsensitiveCompare("BarKeep") == .orderedSame { return true }
        if let bid = bundleIdentifier {
            if ignoredBundleIDs.contains(bid) { return true }
            if bid == Bundle.main.bundleIdentifier { return true }
            for prefix in ignoredBundlePrefixes where bid.hasPrefix(prefix) {
                // Allow non-system after filter; all com.apple.* ignored.
                return true
            }
        }
        return false
    }

    private static func bundleID(forPID pid: pid_t?) -> String? {
        guard let pid else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func displayName(forBundleID bid: String) -> String? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
           let name = app.localizedName, !name.isEmpty {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return nil
    }

    private static func friendlyName(fromDomain domain: String) -> String {
        // com.example.MyApp → MyApp
        if let last = domain.split(separator: ".").last, !last.isEmpty {
            return String(last)
        }
        return domain
    }

    private static func isInMenuBarBand(y: CGFloat, height: CGFloat) -> Bool {
        for screen in NSScreen.screens {
            let top = screen.frame.maxY
            let bandMin = screen.visibleFrame.maxY - 4
            if y + height >= bandMin && y <= top + 2 {
                return true
            }
        }
        if y >= 0, y <= 48 { return true }
        return false
    }
}
