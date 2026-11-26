#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

/// Shared detail-column chrome: the pane title, then its tiles, inside a scroll view that
/// fills the fixed window frame. KTD2 — the outer frame is fixed, so the scroll view is
/// pinned to `.infinity` rather than relying on ideal sizes (see
/// `docs/solutions/popover-scrollview-zero-height.md`).
struct SettingsPaneScaffold<Content: View>: View {
    private let title: String
    private let subtitle: String
    private let content: Content

    init(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        let _ = BenchCounters.hit("SettingsPaneScaffold")
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PDS.Space.l) {
                SettingsPaneHeading(title: title, subtitle: subtitle)
                content
            }
            .padding(PDS.Space.xl)
            // L9A: the window is resizable now, so the pane's measure is capped and
            // left-aligned rather than tracking the column. Without this a 1200pt-wide
            // window runs a help line the whole way across.
            .frame(maxWidth: SettingsView.detailContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("settings.scroll")
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}



// MARK: - Accounts

/// R9/KD7: one room per provider. The old "Subscription Usage" tile is gone — each
/// provider's on/off switch now rides its own group header in `AccountsSettingsTile`,
/// next to the accounts it governs, and its two display preferences moved to Appearance
/// in U3.
struct AccountsSettingsPane: View {
    let store: UsageStore
    let duplicateLoginLabels: [AccountKey: String]
    let surfaceBinding: (UsageSurface) -> Binding<Bool>

    var body: some View {
        let _ = BenchCounters.hit("AccountsSettingsPane")
        SettingsPaneScaffold(SettingsPane.accounts.label, subtitle: "Manage the subscriptions and logins Pacemark reads.") {
            AccountsSettingsTile(
                store: store,
                duplicateLoginLabels: duplicateLoginLabels,
                surfaceBinding: surfaceBinding
            )
        }
    }
}
