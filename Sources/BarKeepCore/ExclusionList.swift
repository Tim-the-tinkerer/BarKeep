import Foundation

/// One menu-bar app the user wants to try to keep visible when BarKeep collapses.
/// Placement is best-effort: BarKeep reserves the │–BK zone and may write preferred
/// positions; live icons often still need a ⌘-drag or app relaunch.
public struct ExclusionEntry: Equatable, Codable, Identifiable, Hashable, Sendable {
    /// Stable id: bundle identifier when known, otherwise `name:` + display name.
    public var id: String
    /// Menu-bar / process display name (e.g. "Dropbox").
    public var name: String
    /// Bundle identifier when known (used to write preferred-position prefs).
    public var bundleIdentifier: String?

    public init(id: String, name: String, bundleIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    public static func make(name: String, bundleIdentifier: String?) -> ExclusionEntry {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return ExclusionEntry(id: bundleIdentifier, name: name, bundleIdentifier: bundleIdentifier)
        }
        return ExclusionEntry(id: "name:\(name)", name: name, bundleIdentifier: nil)
    }
}

/// Pure list helpers for the keepers / exclusions feature.
public enum ExclusionList {
    /// Deduplicate by bundle id (or entry id), sort by display name.
    public static func unique(_ list: [ExclusionEntry]) -> [ExclusionEntry] {
        var seen = Set<String>()
        var out: [ExclusionEntry] = []
        for e in list {
            let key = e.bundleIdentifier ?? e.id
            if seen.insert(key).inserted {
                out.append(e)
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func contains(
        _ list: [ExclusionEntry],
        name: String,
        bundleIdentifier: String?
    ) -> Bool {
        if let bundleIdentifier, list.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return true
        }
        let lowered = name.lowercased()
        return list.contains { $0.name.lowercased() == lowered }
    }

    /// Clamp auto-hide delay to a sane range (seconds).
    public static func clampAutoHideSeconds(_ value: Double) -> Double {
        if value == 0 { return 10 }
        return max(1, min(value, 600))
    }
}
