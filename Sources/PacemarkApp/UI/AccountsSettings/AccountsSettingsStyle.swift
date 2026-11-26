#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

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
            .foregroundStyle(PDS.Ink.ink)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

struct AccountsColumns<Identity: View, Source: View, Plan: View, LastRead: View, Actions: View>: View {
    @ViewBuilder let identity: () -> Identity
    @ViewBuilder let source: () -> Source
    @ViewBuilder let plan: () -> Plan
    @ViewBuilder let lastRead: () -> LastRead
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: PDS.Space.s) {
            identity().frame(maxWidth: .infinity, alignment: .leading)
            cell(width: 76, alignment: .leading, content: source)
            cell(width: 106, alignment: .leading, content: plan)
            cell(width: 82, alignment: .trailing, content: lastRead)
            cell(width: PDS.Metrics.sectionHeader, alignment: .center, content: actions)
        }
    }

    private func cell<Content: View>(width: CGFloat, alignment: Alignment, content: () -> Content) -> some View {
        // The stack holds the column open when the builder supplies no view.
        ZStack(content: content).frame(width: width, alignment: alignment)
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
