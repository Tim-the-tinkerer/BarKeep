import AppKit
import Foundation

/// Checks GitHub Releases for a newer BarKeep and opens the project page.
@MainActor
enum UpdateChecker {
    static let repositoryURL = URL(string: "https://github.com/Tim-the-tinkerer/BarKeep")!
    static let releasesURL = URL(string: "https://github.com/Tim-the-tinkerer/BarKeep/releases")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/Tim-the-tinkerer/BarKeep/releases/latest")!

    private static var isChecking = false

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// Opens the GitHub repository in the default browser.
    static func openRepository() {
        NSWorkspace.shared.open(repositoryURL)
    }

    /// Opens the GitHub Releases page.
    static func openReleases() {
        NSWorkspace.shared.open(releasesURL)
    }

    /// Query GitHub for the latest release and present an alert.
    /// - Parameter interactive: When `true`, always show a result alert (menu “Check for Updates…”).
    ///   When `false`, only alert if a newer release exists (optional silent launch check).
    static func checkForUpdates(interactive: Bool = true) {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            do {
                let latest = try await fetchLatestRelease()
                let comparison = compareVersions(currentVersion, latest.tagVersion)
                await presentResult(
                    latest: latest,
                    comparison: comparison,
                    interactive: interactive
                )
            } catch {
                if interactive {
                    presentError(error)
                } else {
                    NSLog("BarKeep: update check failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Network

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: String
        let body: String?
        let prerelease: Bool
        let draft: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case body
            case prerelease
            case draft
        }

        /// Normalize `v1.2.3` / `1.2.3` → `1.2.3`
        var tagVersion: String {
            let t = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasPrefix("v") {
                return String(t.dropFirst())
            }
            return t
        }
    }

    private static func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("BarKeep/\(currentVersion) (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            // 404 = no releases published yet → treat as “up to date” / point to repo.
            if http.statusCode == 404 {
                throw UpdateError.noReleases
            }
            guard (200...299).contains(http.statusCode) else {
                throw UpdateError.httpStatus(http.statusCode)
            }
        }

        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)
        if release.draft {
            throw UpdateError.noReleases
        }
        return release
    }

    // MARK: - Compare

    /// - Returns: `.orderedAscending` if `lhs` < `rhs` (update available when current < latest)
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = versionParts(lhs)
        let b = versionParts(rhs)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .split(whereSeparator: { $0 == "." || $0 == "-" })
            .map { part in
                let digits = part.prefix(while: \.isNumber)
                return Int(digits) ?? 0
            }
    }

    // MARK: - UI

    private static func presentResult(
        latest: GitHubRelease,
        comparison: ComparisonResult,
        interactive: Bool
    ) async {
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch comparison {
        case .orderedAscending:
            // current < latest
            alert.messageText = "Update available"
            alert.informativeText = """
            BarKeep \(latest.tagVersion) is available (you have \(currentVersion)).

            Download the latest release from GitHub, or open the project page for notes and builds.
            """
            alert.addButton(withTitle: "View Release…")
            alert.addButton(withTitle: "Open GitHub…")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: latest.htmlURL) {
                    NSWorkspace.shared.open(url)
                } else {
                    openReleases()
                }
            } else if response == .alertSecondButtonReturn {
                openRepository()
            }

        case .orderedSame, .orderedDescending:
            guard interactive else { return }
            alert.messageText = comparison == .orderedSame
                ? "You’re up to date"
                : "You’re on a newer build"
            if comparison == .orderedSame {
                alert.informativeText = """
                BarKeep \(currentVersion) (build \(currentBuild)) is the latest release on GitHub (\(latest.tagVersion)).

                Project: \(repositoryURL.absoluteString)
                """
            } else {
                alert.informativeText = """
                You’re running BarKeep \(currentVersion), which is newer than the latest GitHub release (\(latest.tagVersion)).

                Project: \(repositoryURL.absoluteString)
                """
            }
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open GitHub…")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                openRepository()
            }
        }
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t check for updates"
        if let updateError = error as? UpdateError {
            alert.informativeText = updateError.localizedDescription + "\n\nYou can still open the project on GitHub."
        } else {
            alert.informativeText = error.localizedDescription + "\n\nYou can still open the project on GitHub."
        }
        alert.addButton(withTitle: "Open GitHub…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openRepository()
        }
    }

    private enum UpdateError: LocalizedError {
        case noReleases
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .noReleases:
                return "No published releases were found on GitHub yet."
            case .httpStatus(let code):
                return "GitHub returned HTTP \(code)."
            }
        }
    }
}
