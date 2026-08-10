import Foundation
import BarKeepCore

/// User preferences for BarKeep. Persisted via `UserDefaults`.
struct AppSettings: Equatable {
    /// Collapse hidden items after a delay when expanded.
    var autoHide: Bool
    /// Seconds to wait before auto-collapsing (when `autoHide` is on).
    var autoHideSeconds: Double
    /// Expand hidden section when the pointer enters the menu bar near the control.
    var showOnHover: Bool
    /// Collapse shortly after launch (after status items settle).
    var startCollapsed: Bool
    /// Launch BarKeep when you log in.
    var launchAtLogin: Bool
    /// Global hotkey enabled (⌃⌘B).
    var hotkeyEnabled: Bool
    /// Onboarding tip already dismissed.
    var didShowOnboarding: Bool
    /// Apps for which BarKeep reserves the keepers zone and *attempts* placement.
    /// Not a guarantee: live icons may still need ⌘-drag or a relaunch.
    var exclusions: [ExclusionEntry]

    static let `default` = AppSettings(
        autoHide: false,
        autoHideSeconds: 10,
        showOnHover: false,
        startCollapsed: false,
        launchAtLogin: false,
        hotkeyEnabled: true,
        didShowOnboarding: false,
        exclusions: []
    )

    private enum Keys {
        static let autoHide = "autoHide"
        static let autoHideSeconds = "autoHideSeconds"
        static let showOnHover = "showOnHover"
        static let startCollapsed = "startCollapsed"
        static let launchAtLogin = "launchAtLogin"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let didShowOnboarding = "didShowOnboarding"
        static let exclusions = "exclusions"
    }

    static func load() -> AppSettings {
        let d = UserDefaults.standard
        var s = AppSettings.default
        if d.object(forKey: Keys.autoHide) != nil {
            s.autoHide = d.bool(forKey: Keys.autoHide)
        }
        if d.object(forKey: Keys.autoHideSeconds) != nil {
            s.autoHideSeconds = ExclusionList.clampAutoHideSeconds(d.double(forKey: Keys.autoHideSeconds))
        }
        if d.object(forKey: Keys.showOnHover) != nil {
            s.showOnHover = d.bool(forKey: Keys.showOnHover)
        }
        if d.object(forKey: Keys.startCollapsed) != nil {
            s.startCollapsed = d.bool(forKey: Keys.startCollapsed)
        }
        if d.object(forKey: Keys.launchAtLogin) != nil {
            s.launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        }
        if d.object(forKey: Keys.hotkeyEnabled) != nil {
            s.hotkeyEnabled = d.bool(forKey: Keys.hotkeyEnabled)
        }
        if d.object(forKey: Keys.didShowOnboarding) != nil {
            s.didShowOnboarding = d.bool(forKey: Keys.didShowOnboarding)
        }
        if let data = d.data(forKey: Keys.exclusions),
           let decoded = try? JSONDecoder().decode([ExclusionEntry].self, from: data) {
            s.exclusions = ExclusionList.unique(decoded)
        }
        return s
    }

    func save() {
        let d = UserDefaults.standard
        d.set(autoHide, forKey: Keys.autoHide)
        d.set(ExclusionList.clampAutoHideSeconds(autoHideSeconds), forKey: Keys.autoHideSeconds)
        d.set(showOnHover, forKey: Keys.showOnHover)
        d.set(startCollapsed, forKey: Keys.startCollapsed)
        d.set(launchAtLogin, forKey: Keys.launchAtLogin)
        d.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled)
        d.set(didShowOnboarding, forKey: Keys.didShowOnboarding)
        if let data = try? JSONEncoder().encode(ExclusionList.unique(exclusions)) {
            d.set(data, forKey: Keys.exclusions)
        }
    }

    mutating func addExclusion(_ entry: ExclusionEntry) {
        exclusions = ExclusionList.unique(exclusions + [entry])
    }

    mutating func removeExclusion(id: String) {
        exclusions.removeAll { $0.id == id }
    }

    func isExcluded(name: String, bundleIdentifier: String?) -> Bool {
        ExclusionList.contains(exclusions, name: name, bundleIdentifier: bundleIdentifier)
    }
}

extension Notification.Name {
    static let barKeepSettingsChanged = Notification.Name("BarKeepSettingsChanged")
}
