#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

struct AboutSettingsPane: View {
    let store: UsageStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var isOpeningFeedback = false

    var body: some View {
        let _ = BenchCounters.hit("AboutSettingsPane")
        SettingsPaneScaffold(SettingsPane.about.label, subtitle: "Version, feedback, and credits.") {
            SettingsLedgerTile {
                HStack(spacing: PDS.Space.s) {
                    SettingsAppIcon(size: 38)
                    VStack(alignment: .leading, spacing: PDS.Space.xs) {
                        Text("Pacemark").font(PopoverLedgerType.name)
                        Text(AppVersionLabel.plain.map { "Version \($0)" } ?? "Development build")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(PDS.Ink.inkSecondary)
                        SettingsLedgerHelp(AboutLinks.tagline)
                    }
                }
                .padding(.vertical, PDS.Space.xs)
                Button(action: openFeedback) {
                    SettingsLedgerControlRow(title: "Send feedback") {
                        destination(isOpeningFeedback ? "Preparing…" : "GitHub issue")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isOpeningFeedback)
                .accessibilityHint("Opens a prefilled GitHub issue in your browser")
                .accessibilityIdentifier("about.feedback")
            }

            SettingsLedgerTile("Credits and license") {
                credit("Made by Nikolai Fateev.")
                ForEach(MacAboutLinks.maker) { link($0) }
                credit("Based on Headroom by Kyle Zantos.")
                credit("Pacemark is distributed under the GNU General Public License v3.0.")
                link(MacAboutLinks.license)
            }
        }
    }

    private func credit(_ text: String) -> some View {
        SettingsLedgerHelp(text).frame(minHeight: PDS.Metrics.row + PDS.Space.xs, alignment: .leading)
    }

    private func link(_ link: AboutLink) -> some View {
        Link(destination: link.url) {
            SettingsLedgerControlRow(title: link.title) {
                destination(link.destination)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func destination(_ label: String) -> some View {
        HStack(spacing: PDS.Space.xs) {
            Text(label)
            Image(systemName: "arrow.up.right").accessibilityHidden(true)
        }
        .font(PopoverLedgerType.sentence)
        .foregroundStyle(PDS.Ink.link(scheme))
    }

    private func openFeedback() {
        guard !AppComposition.usesInertFeedback() else { return }
        isOpeningFeedback = true
        Task {
            defer { isOpeningFeedback = false }
            if let url = await MacFeedback.issueURL(store: store) {
                openURL(url)
            }
        }
    }
}
