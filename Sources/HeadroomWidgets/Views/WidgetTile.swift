import SwiftUI

/// KTD/Jakub elevation: a hairline ring + soft ambient shadow (light) or a faint
/// light-glow (dark) — surfaces defined by shadow, never a hard border. The shared tile
/// look for the large widget's provider cards, mirrored 1:1 on the iOS companion.
struct WidgetTileBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(WidgetProviderStyle.tileSurface(scheme: scheme))
                    .shadow(color: ambient, radius: scheme == .dark ? 10 : 8, x: 0, y: scheme == .dark ? 8 : 4)
                    .shadow(color: ambientTight, radius: 2, x: 0, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(WidgetProviderStyle.tileRing(scheme: scheme), lineWidth: 1)
            }
    }

    private var ambient: Color { scheme == .dark ? .black.opacity(0.38) : .black.opacity(0.05) }
    private var ambientTight: Color { scheme == .dark ? .black.opacity(0.20) : .black.opacity(0.06) }
}

extension View {
    func widgetTile(cornerRadius: CGFloat = 14) -> some View {
        modifier(WidgetTileBackground(cornerRadius: cornerRadius))
    }
}
