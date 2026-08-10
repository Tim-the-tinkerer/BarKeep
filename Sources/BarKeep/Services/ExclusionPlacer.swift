import AppKit
import Foundation
import BarKeepCore

/// Best-effort keepers placement for listed apps.
///
/// BarKeep **reserves** space between │ and BK, then *attempts* to write each
/// app’s existing `NSStatusItem Preferred Position *` keys via **CFPreferences
/// only** (no full-plist rewrite). Live icons often still require ⌘-drag or an
/// app relaunch; apps without a named autosaved status item cannot be placed.
enum ExclusionPlacer {
    private static let positionKeyPrefix = "NSStatusItem Preferred Position "

    struct Result: Equatable {
        var appsTouched: Int
        var keysUpdated: Int
        var gapControl: Double
        var gapDivider: Double
        /// Apps with no discoverable status-item position keys (⌘-drag required).
        var appsWithoutKeys: [String]
    }

    /// Preferred-position span for the keepers zone given exclusion count.
    static func keepersGap(exclusionCount: Int) -> KeepersLayout.GapPlan {
        KeepersLayout.keepersGap(exclusionCount: exclusionCount)
    }

    /// Open/adjust BarKeep's own │–BK gap for the current exclusion count.
    @discardableResult
    static func ensureKeepersGap(
        controlKey: String,
        dividerKey: String,
        exclusionCount: Int,
        defaults: UserDefaults = .standard
    ) -> (control: Double, divider: Double) {
        let storedC = defaults.object(forKey: controlKey) as? Double
        let storedD = defaults.object(forKey: dividerKey) as? Double
        let resolved = KeepersLayout.resolveStoredGap(
            storedControl: storedC,
            storedDivider: storedD,
            exclusionCount: exclusionCount
        )
        defaults.set(resolved.control, forKey: controlKey)
        defaults.set(resolved.divider, forKey: dividerKey)
        return resolved
    }

    /// Best-effort: write preferred positions for excluded apps into the keepers band
    /// using CFPreferences only.
    @discardableResult
    static func placeExclusions(
        _ exclusions: [ExclusionEntry],
        controlPosition: Double,
        dividerPosition: Double
    ) -> Result {
        let slots = KeepersLayout.slotPositions(
            controlPosition: controlPosition,
            dividerPosition: dividerPosition,
            count: exclusions.count
        )
        guard !slots.isEmpty else {
            return Result(
                appsTouched: 0,
                keysUpdated: 0,
                gapControl: controlPosition,
                gapDivider: dividerPosition,
                appsWithoutKeys: []
            )
        }

        var appsTouched = 0
        var keysUpdated = 0
        var appsWithoutKeys: [String] = []

        for (index, entry) in exclusions.enumerated() {
            let position = slots[index]
            let domains = preferenceDomains(for: entry)
            var updatedThisApp = false
            for domain in domains {
                let n = writePreferredPositionsCFOnly(inDomain: domain, position: position)
                if n > 0 {
                    keysUpdated += n
                    updatedThisApp = true
                }
            }
            if updatedThisApp {
                appsTouched += 1
                NSLog(
                    "BarKeep: keeper place (CFPreferences) '%@' pos=%.1f domains=%@",
                    entry.name, position, domains.joined(separator: ",")
                )
            } else {
                appsWithoutKeys.append(entry.name)
                NSLog(
                    "BarKeep: keeper '%@' has no NSStatusItem position keys — ⌘-drag between │ and BK",
                    entry.name
                )
            }
        }

        return Result(
            appsTouched: appsTouched,
            keysUpdated: keysUpdated,
            gapControl: controlPosition,
            gapDivider: dividerPosition,
            appsWithoutKeys: appsWithoutKeys
        )
    }

    // MARK: - CFPreferences only

    private static func preferenceDomains(for entry: ExclusionEntry) -> [String] {
        var domains: [String] = []
        if let bid = entry.bundleIdentifier, !bid.isEmpty {
            domains.append(bid)
        }
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName ?? ""
            if name.caseInsensitiveCompare(entry.name) == .orderedSame,
               let bid = app.bundleIdentifier,
               !domains.contains(bid) {
                domains.append(bid)
            }
        }
        return domains
    }

    /// Update every existing `NSStatusItem Preferred Position *` key via CFPreferences.
    /// Does **not** read or rewrite preference plist files on disk.
    private static func writePreferredPositionsCFOnly(inDomain domain: String, position: Double) -> Int {
        guard let cfKeys = CFPreferencesCopyKeyList(
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String] else {
            return 0
        }
        let keys = cfKeys.filter { $0.hasPrefix(positionKeyPrefix) }
        // If the app never set autosaveName, we cannot invent a key it will read.
        guard !keys.isEmpty else { return 0 }

        let number = position as CFNumber
        for key in keys {
            CFPreferencesSetAppValue(key as CFString, number, domain as CFString)
        }
        CFPreferencesAppSynchronize(domain as CFString)
        return keys.count
    }
}
