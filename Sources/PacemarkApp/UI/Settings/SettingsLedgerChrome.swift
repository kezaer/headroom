#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct SettingsLedgerTile<Accessory: View, Content: View>: View {
    let title: String?
    var provider: ProviderID? = nil
    @ViewBuilder let caption: () -> Accessory
    @ViewBuilder let content: () -> Content

    init(title: String?, provider: ProviderID? = nil, @ViewBuilder caption: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.provider = provider
        self.caption = caption
        self.content = content
    }

    init(accountsProvider title: String, provider: ProviderID, @ViewBuilder actions: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, provider: provider, caption: actions, content: content)
    }

    var body: some View {
        PDSCard(title, mark: {
            if let provider { ProviderLogoView(providerID: provider, size: PDS.Metrics.providerMark) }
        }, accessory: caption, content: content)
    }
}

extension SettingsLedgerTile where Accessory == EmptyView {
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, caption: { EmptyView() }, content: content)
    }
}

typealias SettingsCapsLabel = PDSCapsHeader
typealias SettingsLedgerHelp = PDSHelpText

struct SettingsLedgerControlRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        PDSRow { Text(title).font(PDS.Typography.body) } trailing: { control() }
    }
}

struct SettingsPaneHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: PDS.Space.xs) {
            Text(title)
                .font(PDS.Typography.paneTitle)
                .kerning(SettingsType.paneTitleKerning)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(PDS.Typography.paneSubtitle).foregroundStyle(PDS.Ink.inkSecondary)
        }
    }
}

typealias SettingsLedgerSwitch = PDSToggleRow

struct SettingsLedgerSwitchControl: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
        .accessibilityIdentifier("switch.\(title)")
            .toggleStyle(.switch)
            .controlSize(.regular)
    }
}

struct SettingsTableHeading: View {
    @Environment(\.isEnabled) private var enabled
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(PopoverLedgerType.column)
            .tracking(0.6)
            .foregroundStyle(enabled ? PDS.Ink.inkSecondary : PDS.Ink.disabledText)
            .lineLimit(1)
    }
}
