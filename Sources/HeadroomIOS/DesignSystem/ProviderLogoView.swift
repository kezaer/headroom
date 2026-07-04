import SwiftUI

struct ProviderLogoView: View {
    let providerID: String
    var size: CGFloat = 24

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(HeadroomTheme.providerTextAccent(for: providerID, scheme: scheme))
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.20)
        // Squircle to match the app-icon language (HeadroomAppIconView's 0.22 superellipse
        // ratio), applied to the padded badge (size * 1.4) — not a Circle.
        .background(
            HeadroomTheme.providerAccent(for: providerID).opacity(scheme == .dark ? 0.18 : 0.13),
            in: RoundedRectangle(cornerRadius: size * 1.4 * 0.22, style: .continuous)
        )
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        switch providerID {
        case ProviderID.claude.raw: "ClaudeBrandIcon"
        case ProviderID.codex.raw: "CodexBrandIcon"
        default: nil
        }
    }

    private var symbolName: String {
        switch providerID {
        case ProviderID.claude.raw: "sparkles"
        case ProviderID.codex.raw: "terminal"
        default: "circle.dashed"
        }
    }
}
