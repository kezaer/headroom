import SwiftUI
import HeadroomCore

struct AccountMenuBarBadgeField: View {
    let value: String
    let accountLabel: String
    let onCommit: (String?) -> Void
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        TextField("Badge", text: $draft)
            .font(SettingsType.help.monospaced())
            .multilineTextAlignment(.center)
            .frame(width: 36)
            .controlSize(.small)
            .focused($editing)
            .help("Menu bar badge. Clear it to use the account’s default.")
            .accessibilityLabel("Menu bar badge for \(accountLabel)")
            .onAppear { draft = value }
            .onChange(of: value) { _, value in if !editing { draft = value } }
            .onChange(of: editing) { _, editing in if !editing { commit() } }
            .onSubmit { editing = false }
            .onDisappear { if editing { commit() } }
    }

    private func commit() {
        let edited = MenuBarAccountBadge.sanitize(draft)
        if edited != value { onCommit(edited) }
        draft = edited ?? value
    }
}

extension View {
    /// R2C21: one control language in the Accounts action column. The `•••` menus get the
    /// same chrome as the `arrow.clockwise` and `trash` glyphs beside them — `.button` menu
    /// style routed through `HoverButtonStyle`, so one hover pill, one press, and one ~38pt
    /// target serve all three. `.borderlessButton` gave the menus no hover, no press, a bare
    /// 22pt target, and an AppKit `⌄` the glyph set has nowhere else.
    func accountActionsMenuChrome() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
            .foregroundStyle(.secondary)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

struct AccountsColumns<Identity: View, Source: View, Plan: View, Version: View, Badge: View, Actions: View>: View {
    let showsBadge: Bool
    @ViewBuilder let identity: () -> Identity
    @ViewBuilder let source: () -> Source
    @ViewBuilder let plan: () -> Plan
    @ViewBuilder let version: () -> Version
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 7) {
            identity().frame(maxWidth: .infinity, alignment: .leading)
            source().frame(width: 47, alignment: .leading)
            plan().frame(width: 102, alignment: .leading)
            version()
                .frame(width: 64, alignment: .leading)
                .padding(.trailing, showsBadge ? 0 : 43)
            if showsBadge {
                badge().frame(width: 36)
            }
            actions().frame(width: 26)
        }
        .padding(.horizontal, 10)
    }
}
extension View {
    func accountSettingsInset(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Color.primary.opacity(0.035), in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.13), lineWidth: 1).allowsHitTesting(false) }
    }
}
