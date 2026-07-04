import SwiftUI

struct HeadroomTileModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(HeadroomTheme.surface(scheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.055), lineWidth: 1)
                    .blendMode(scheme == .dark ? .screen : .normal)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(scheme == .dark ? 0.09 : 0.36))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: scheme == .dark ? .black.opacity(0.22) : .black.opacity(0.07),
                radius: scheme == .dark ? 10 : 18,
                x: 0,
                y: scheme == .dark ? 8 : 14
            )
            .shadow(
                color: scheme == .dark ? .white.opacity(0.025) : .black.opacity(0.035),
                radius: scheme == .dark ? 2 : 5,
                x: 0,
                y: 1
            )
    }
}

extension View {
    func headroomTile(cornerRadius: CGFloat = HeadroomTheme.tileRadius) -> some View {
        modifier(HeadroomTileModifier(cornerRadius: cornerRadius))
    }
}
