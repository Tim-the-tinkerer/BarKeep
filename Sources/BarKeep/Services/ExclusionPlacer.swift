import AppKit
import Foundation

/// Places excluded apps into the keepers zone (between │ and BK) by writing
/// each app's `NSStatusItem Preferred Position *` defaults.
///
/// Live icons only move after that app recreates its status item (often on
/// relaunch) or the user ⌘-drags them. Writing prefs still makes placement
/// stick across reboots.
enum ExclusionPlacer {
    private static let positionKeyPrefix = "NSStatusItem Preferred Position "

    struct Result: Equatable {
        var appsTouched: Int
        var keysUpdated: Int
        var gapControl: Double
        var gapDivider: Double
    }

    /// Preferred-position span for the keepers zone given exclusion count.
    /// Higher preferred position = further left.
    static func keepersGap(exclusionCount: Int) -> (control: Double, divider: Double, slots: [Double]) {
        let count = max(0, exclusionCount)
        // Base: control near system cluster; divider further left with room for keepers.
        let control: Double = 250
        let slotStride: Double = 28
        let edgePad: Double = 14
        let needed = edgePad * 2 + Double(max(count, 1)) * slotStride
        let divider = control + max(needed, 30)
        var slots: [Double] = []
        if count > 0 {
            for i in 0..<count {
                // Left-to-right in the keepers zone: higher positions first (left).
                let slot = divider - edgePad - (Double(i) + 0.5) * slotStride
                slots.append(slot)
            }
        }
        return (control, divider, slots)
    }

    /// Open/adjust BarKeep's own │–BK gap for the current exclusion count,
    /// preserving the control position when possible.
    @discardableResult
    static func ensureKeepersGap(
        controlKey: String,
        dividerKey: String,
        exclusionCount: Int,
        defaults: UserDefaults = .standard
    ) -> (control: Double, divider: Double) {
        let plan = keepersGap(exclusionCount: exclusionCount)
        let storedC = defaults.object(forKey: controlKey) as? Double
        let control = (storedC != nil && storedC! > 0 && storedC! <= 10_000)
            ? storedC!
            : plan.control
        let minDivider = control + 14 + Double(max(exclusionCount, 0)) * 28
        let storedD = defaults.object(forKey: dividerKey) as? Double
        let divider: Double
        if let d = storedD, d > control + 10, d >= minDivider, d <= 10_000 {
            divider = d
        } else {
            divider = max(minDivider, control + plan.divider - plan.control)
        }
        defaults.set(control, forKey: controlKey)
        defaults.set(divider, forKey: dividerKey)
        return (control, divider)
    }

    /// Write preferred positions for excluded apps into the keepers band.
    @discardableResult
    static func placeExclusions(
        _ exclusions: [ExclusionEntry],
        controlPosition: Double,
        dividerPosition: Double
    ) -> Result {
        guard dividerPosition > controlPosition else {
            return Result(appsTouched: 0, keysUpdated: 0, gapControl: controlPosition, gapDivider: dividerPosition)
        }
        let span = dividerPosition - controlPosition
        let count = exclusions.count
        guard count > 0 else {
            return Result(appsTouched: 0, keysUpdated: 0, gapControl: controlPosition, gapDivider: dividerPosition)
        }

        var appsTouched = 0
        var keysUpdated = 0

        for (index, entry) in exclusions.enumerated() {
            // Evenly space keepers between control (right) and divider (left).
            let t = (Double(index) + 1.0) / (Double(count) + 1.0)
            // preferred: higher = left. divider is high, control is low.
            let position = dividerPosition - t * span

            let domains = preferenceDomains(for: entry)
            var updatedThisApp = false
            for domain in domains {
                let n = writePreferredPositions(inDomain: domain, position: position)
                if n > 0 {
                    keysUpdated += n
                    updatedThisApp = true
                }
            }
            if updatedThisApp {
                appsTouched += 1
                NSLog(
                    "BarKeep: exclusion place '%@' pos=%.1f domains=%@",
                    entry.name, position, domains.joined(separator: ",")
                )
            } else {
                NSLog("BarKeep: exclusion no status prefs for '%@' (⌘-drag between │ and BK)", entry.name)
            }
        }

        return Result(
            appsTouched: appsTouched,
            keysUpdated: keysUpdated,
            gapControl: controlPosition,
            gapDivider: dividerPosition
        )
    }

    // MARK: - Defaults I/O

    private static func preferenceDomains(for entry: ExclusionEntry) -> [String] {
        var domains: [String] = []
        if let bid = entry.bundleIdentifier, !bid.isEmpty {
            domains.append(bid)
        }
        // Also try running apps that match the display name.
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

    /// Update every `NSStatusItem Preferred Position *` key in the domain.
    private static func writePreferredPositions(inDomain domain: String, position: Double) -> Int {
        let prefsURL = preferenceFileURL(for: domain)
        var dict: [String: Any] = [:]
        if let existing = NSDictionary(contentsOf: prefsURL) as? [String: Any] {
            dict = existing
        }

        // Prefer CFPreferences so values merge with the live defaults database.
        var keys: [String] = []
        if let cfKeys = CFPreferencesCopyKeyList(
            domain as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String] {
            keys = cfKeys.filter { $0.hasPrefix(positionKeyPrefix) }
        }
        // Fall back to on-disk plist keys.
        if keys.isEmpty {
            keys = dict.keys.filter { $0.hasPrefix(positionKeyPrefix) }
        }
        // If the app never set autosaveName, we cannot invent a key that it will read.
        guard !keys.isEmpty else { return 0 }

        var updated = 0
        for key in keys {
            CFPreferencesSetAppValue(key as CFString, position as CFNumber, domain as CFString)
            dict[key] = position
            updated += 1
        }
        CFPreferencesAppSynchronize(domain as CFString)

        // Mirror to the plist when present (some apps only read the file).
        if FileManager.default.fileExists(atPath: prefsURL.path)
            || updated > 0 {
            (dict as NSDictionary).write(to: prefsURL, atomically: true)
        }
        return updated
    }

    private static func preferenceFileURL(for domain: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(domain).plist", isDirectory: false)
    }
}
