import Foundation

/// Pure version-string helpers used by update checks (and tests).
public enum VersionCompare {
    /// Normalize a Git tag like `v1.2.3` / `1.2.3-beta` → comparable core `1.2.3` plus suffix tokens.
    public static func normalizeTag(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("v"), t.count > 1,
           t.dropFirst().first?.isNumber == true {
            t = String(t.dropFirst())
        }
        return t
    }

    /// - Returns: `.orderedAscending` if `lhs` < `rhs` (update available when current < latest).
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parse(normalizeTag(lhs))
        let right = parse(normalizeTag(rhs))

        let n = max(left.numeric.count, right.numeric.count)
        for i in 0..<n {
            let x = i < left.numeric.count ? left.numeric[i] : 0
            let y = i < right.numeric.count ? right.numeric[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }

        // Equal numeric core: a release without prerelease suffix sorts *after* one with a suffix
        // (1.2.3 > 1.2.3-beta). Empty suffix is "final".
        if left.prerelease.isEmpty && right.prerelease.isEmpty {
            return .orderedSame
        }
        if left.prerelease.isEmpty { return .orderedDescending }
        if right.prerelease.isEmpty { return .orderedAscending }

        // Compare prerelease tokens lexicographically / numerically where possible.
        let a = left.prerelease
        let b = right.prerelease
        let m = max(a.count, b.count)
        for i in 0..<m {
            if i >= a.count { return .orderedAscending }
            if i >= b.count { return .orderedDescending }
            let cmp = comparePrereleaseToken(a[i], b[i])
            if cmp != .orderedSame { return cmp }
        }
        return .orderedSame
    }

    // MARK: - Internals

    struct Parsed: Equatable {
        var numeric: [Int]
        var prerelease: [String]
    }

    static func parse(_ version: String) -> Parsed {
        // Split core from prerelease on first `-` or first non-numeric/non-dot run after digits.
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Parsed(numeric: [0], prerelease: [])
        }

        var core = trimmed
        var pre: [String] = []

        if let dash = trimmed.firstIndex(of: "-") {
            core = String(trimmed[..<dash])
            let rest = String(trimmed[trimmed.index(after: dash)...])
            pre = rest.split(separator: ".").map(String.init).filter { !$0.isEmpty }
        } else if let plus = trimmed.firstIndex(of: "+") {
            // Build metadata ignored for precedence (SemVer-ish).
            core = String(trimmed[..<plus])
        }

        // Also strip trailing junk from core: "1.2.3beta" → numeric 1.2.3 + pre ["beta"]
        var numeric: [Int] = []
        var trailingAlpha = ""
        for part in core.split(separator: ".") {
            let digits = part.prefix(while: \.isNumber)
            if digits.isEmpty {
                trailingAlpha = String(part)
                break
            }
            numeric.append(Int(digits) ?? 0)
            if digits.count < part.count {
                trailingAlpha = String(part[digits.endIndex...])
                break
            }
        }
        if numeric.isEmpty { numeric = [0] }
        if !trailingAlpha.isEmpty {
            pre.insert(trailingAlpha, at: 0)
        }

        return Parsed(numeric: numeric, prerelease: pre)
    }

    private static func comparePrereleaseToken(_ a: String, _ b: String) -> ComparisonResult {
        let an = Int(a)
        let bn = Int(b)
        if let an, let bn {
            if an < bn { return .orderedAscending }
            if an > bn { return .orderedDescending }
            return .orderedSame
        }
        // Numeric identifiers have lower precedence than non-numeric (SemVer).
        if an != nil && bn == nil { return .orderedAscending }
        if an == nil && bn != nil { return .orderedDescending }
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}
