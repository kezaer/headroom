#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct NotificationBannerPreview: View {
    let store: UsageStore

    var body: some View {
        let fixture = SettingsPreviewFixtures()
        SettingsLedgerTile("Banner preview") {
            if let rule = store.reminderRules.first {
                let scope = store.reminderScope
                let preview = NotificationContent.reminderPreview(
                    rule: rule, scope: scope, candidates: store.summaryCandidates(at: fixture.now), now: fixture.now
                ) ?? NotificationContent.reminderPreview(
                    rule: rule, scope: scope, candidates: fixture.candidates, now: fixture.now
                )
                if let preview {
                    banner(preview)
                } else {
                    SettingsLedgerHelp("Choose a limit family with a window longer than the reminder’s lead time.")
                }
            } else {
                SettingsLedgerHelp("Add a reminder to see an example.")
            }
        }
    }

    private func banner(_ content: NotificationContent) -> some View {
        HStack(spacing: PDS.Space.s) {
            SettingsAppIcon(size: 28)
            VStack(alignment: .leading, spacing: PDS.Space.xs) {
                HStack {
                    Text("Pacemark").font(PopoverLedgerType.name)
                    Spacer()
                    Text("now").font(PopoverLedgerType.sentence).foregroundStyle(PDS.Ink.inkTertiary)
                }
                Text(content.title).font(PopoverLedgerType.name)
                Text(content.body).font(PopoverLedgerType.sentence)
                    .foregroundStyle(PDS.Ink.inkSecondary)
            }
        }
        .padding(PDS.Space.s)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: PDS.Radius.card))
        .padding(.bottom, PDS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
