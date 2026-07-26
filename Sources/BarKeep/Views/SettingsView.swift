import SwiftUI

struct SettingsView: View {
    @State private var settings: AppSettings
    var onChange: (AppSettings) -> Void
    var onClose: () -> Void

    init(settings: AppSettings, onChange: @escaping (AppSettings) -> Void, onClose: @escaping () -> Void) {
        _settings = State(initialValue: settings)
        self.onChange = onChange
        self.onClose = onClose
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
                    Text("Your arrangement is saved by macOS; BarKeep does not reset it on launch.")
                    Text("Right-click BK → Reset BarKeep Position if │/BK landed in the wrong place.")
                    Button("Open BarKeep Help…") {
                        HelpPresenter.showHelp()
                    }
                }

                Section("About") {
                    Text(versionLine)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 420, minHeight: 480)
        .onChange(of: settings) { newValue in
            if newValue.launchAtLogin != LaunchAtLogin.isEnabled {
                LaunchAtLogin.setEnabled(newValue.launchAtLogin)
            }
            onChange(newValue)
        }
        .onAppear {
            var s = settings
            s.launchAtLogin = LaunchAtLogin.isEnabled
            // Avoid no-op write loops if already in sync.
            if s != settings {
                settings = s
            }
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.1.1"
        let build = info?["CFBundleVersion"] as? String ?? "3"
        return "BarKeep \(version) (\(build))"
    }
}
