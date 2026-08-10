import SwiftUI

struct SettingsView: View {
    @State private var settings: AppSettings
    @State private var runningMenuBarApps: [MenuBarApp] = []
    @State private var placementNote: String?
    @State private var manualName: String = ""
    @State private var didLoadApps = false
    var onChange: (AppSettings) -> Void
    var onClose: () -> Void
    /// Called when exclusions change so BarKeep can re-open the keepers gap / place apps.
    var onExclusionsChanged: (() -> Void)?

    init(
        settings: AppSettings,
        onChange: @escaping (AppSettings) -> Void,
        onClose: @escaping () -> Void,
        onExclusionsChanged: (() -> Void)? = nil
    ) {
        _settings = State(initialValue: settings)
        self.onChange = onChange
        self.onClose = onClose
        self.onExclusionsChanged = onExclusionsChanged
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BarKeep Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                Section("Hide & show") {
                    Toggle("Start collapsed", isOn: $settings.startCollapsed)
                    Text("After launch, wait about a second for icons to settle, then collapse.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Auto-hide after delay", isOn: $settings.autoHide)
                    if settings.autoHide {
                        Picker("Auto-hide after", selection: $settings.autoHideSeconds) {
                            Text("5 seconds").tag(5.0)
                            Text("10 seconds").tag(10.0)
                            Text("15 seconds").tag(15.0)
                            Text("30 seconds").tag(30.0)
                            Text("60 seconds").tag(60.0)
                        }
                    }
                    Toggle("Show on hover over menu bar", isOn: $settings.showOnHover)
                    Text("When enabled, moving the pointer into the right half of the menu bar expands hidden items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    // Current exclusions
                    if settings.exclusions.isEmpty {
                        Text("Nothing excluded yet. Choose apps below to keep visible when collapsed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(settings.exclusions) { entry in
                            HStack(alignment: .center, spacing: 8) {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.tint)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.body)
                                    if let bid = entry.bundleIdentifier {
                                        Text(bid)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer(minLength: 8)
                                Button {
                                    removeExclusion(id: entry.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red.opacity(0.85))
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from exclusions")
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Candidates
                    HStack {
                        Text("Add from running apps")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button {
                            refreshRunningApps()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }

                    if !didLoadApps {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Looking for menu bar apps…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if candidatesToAdd.isEmpty {
                        Text("No candidate apps found. Menu bar utilities usually appear here (Quitter, iStat, etc.). You can still add one by name below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(candidatesToAdd) { app in
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                    Text(candidateSubtitle(app))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Button("Always show") {
                                    addExclusion(app)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Manual add
                    Text("Add by name")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        TextField("App name (e.g. Dropbox)", text: $manualName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addManual() }
                        Button("Add") { addManual() }
                            .disabled(manualName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !settings.exclusions.isEmpty {
                        Button("Apply keepers zone") {
                            onExclusionsChanged?()
                            placementNote = "Opened space between │ and BK for \(settings.exclusions.count) exclusion(s). ⌘-drag those icons between │ and BK (or relaunch them) so they stay visible."
                        }
                        .controlSize(.small)
                    }

                    if let placementNote {
                        Text(placementNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Exclusions (always show)")
                } footer: {
                    Text("Excluded apps stay visible when collapsed by sitting between │ and BK. On macOS Tahoe, BarKeep finds menu bar apps from running utilities (not window ownership). ⌘-drag icons into the keepers zone once so placement sticks.")
                        .font(.caption)
                }

                Section("General") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    Toggle("Global hotkey ⌃⌘B", isOn: $settings.hotkeyEnabled)
                    Text("Toggles the hidden section from the keyboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Tips") {
                    Text("⌘-drag │ and BK so all system icons sit to the RIGHT of BK.")
                    Text("⌘-drag app icons to hide fully LEFT of │ — not onto “BK”.")
                    Text("Excluded apps belong BETWEEN │ and BK.")
                    Text("Right-click BK → Reset BarKeep Position if │/BK landed in the wrong place.")
                    Button("Open BarKeep Help…") {
                        HelpPresenter.showHelp()
                    }
                }

                Section("Updates") {
                    Text(versionLine)
                        .foregroundStyle(.secondary)
                    Text(UpdateChecker.repositoryURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack {
                        Button("Check for Updates…") {
                            UpdateChecker.checkForUpdates(interactive: true)
                        }
                        Button("Open GitHub…") {
                            UpdateChecker.openRepository()
                        }
                        Button("Releases…") {
                            UpdateChecker.openReleases()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 460, minHeight: 600)
        .onChange(of: settings) { newValue in
            if newValue.launchAtLogin != LaunchAtLogin.isEnabled {
                LaunchAtLogin.setEnabled(newValue.launchAtLogin)
            }
            onChange(newValue)
        }
        .onAppear {
            var s = settings
            s.launchAtLogin = LaunchAtLogin.isEnabled
            if s != settings {
                settings = s
            }
            // Defer scan so the window draws first; scanning prefs can take a moment.
            DispatchQueue.main.async {
                refreshRunningApps()
            }
        }
    }

    private var candidatesToAdd: [MenuBarApp] {
        runningMenuBarApps.filter { app in
            !settings.isExcluded(name: app.name, bundleIdentifier: app.bundleIdentifier)
        }
    }

    private func candidateSubtitle(_ app: MenuBarApp) -> String {
        var parts: [String] = []
        if let bid = app.bundleIdentifier {
            parts.append(bid)
        }
        switch app.source {
        case .windowList:
            parts.append("\(app.statusItemCount) icon(s)")
        case .statusItemPrefs:
            parts.append("has menu bar prefs")
        case .accessoryProcess:
            parts.append("menu bar app")
        case .manual:
            parts.append("manual")
        }
        return parts.joined(separator: " · ")
    }

    private func refreshRunningApps() {
        // Prefer a background scan so Settings stays responsive.
        let excluded = settings.exclusions
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = MenuBarAppScanner.runningMenuBarApps()
            DispatchQueue.main.async {
                self.runningMenuBarApps = apps
                self.didLoadApps = true
                if apps.isEmpty {
                    self.placementNote = "No menu bar utilities detected. Use “Add by name”, or launch the apps you want to exclude and hit Refresh."
                } else if self.placementNote?.contains("No menu bar") == true {
                    self.placementNote = nil
                }
                // Keep excluded list names stable even if scan is empty.
                _ = excluded
            }
        }
    }

    private func addExclusion(_ app: MenuBarApp) {
        var s = settings
        s.addExclusion(.make(name: app.name, bundleIdentifier: app.bundleIdentifier))
        settings = s
        placementNote = "“\(app.name)” added. ⌘-drag its icon between │ and BK so it stays visible when collapsed."
        onExclusionsChanged?()
        refreshRunningApps()
    }

    private func addManual() {
        let name = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        // Match a running app by name if possible for bundle id.
        let match = runningMenuBarApps.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        } ?? MenuBarAppScanner.runningMenuBarApps().first {
            $0.name.localizedCaseInsensitiveContains(name)
        }
        let entry = ExclusionEntry.make(
            name: match?.name ?? name,
            bundleIdentifier: match?.bundleIdentifier
        )
        var s = settings
        s.addExclusion(entry)
        settings = s
        manualName = ""
        placementNote = "“\(entry.name)” added. ⌘-drag its icon between │ and BK."
        onExclusionsChanged?()
        refreshRunningApps()
    }

    private func removeExclusion(id: String) {
        var s = settings
        s.removeExclusion(id: id)
        settings = s
        onExclusionsChanged?()
        refreshRunningApps()
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.2.2"
        let build = info?["CFBundleVersion"] as? String ?? "8"
        return "BarKeep \(version) (build \(build))"
    }
}
