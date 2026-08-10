import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("How BarKeep works")
                        .font(.title2.weight(.semibold))
                    Text("Hide app icons — keep system icons")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            step(
                number: 1,
                title: "Park │ BK left of system icons",
                detail: "⌘-drag the │ mark and BK until Wi‑Fi, Bluetooth, Sound, and Clock are all to the RIGHT of BK."
            )
            step(
                number: 2,
                title: "Hide zone = left of │ only",
                detail: "⌘-drag app icons you want hidden fully LEFT of │. Icons between │ and BK stay visible (exclusions / keepers). Or add apps under Settings → Exclusions. Dropping something on “BK” does nothing special."
            )
            step(
                number: 3,
                title: "Click BK to hide / show",
                detail: "Click BK (or press ⌃⌘B) to collapse and expand. Icons left of │ disappear when collapsed; system icons on the right stay put."
            )
            step(
                number: 4,
                title: "If layout is wrong",
                detail: "Right-click BK → Reset BarKeep Position. That only moves │ and BK; it does not reshuffle other apps. Full guide: BarKeep Help…"
            )

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Got it") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460, height: 400)
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
