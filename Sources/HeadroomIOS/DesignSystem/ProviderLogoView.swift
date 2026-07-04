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
        .background(HeadroomTheme.providerAccent(for: providerID).opacity(scheme == .dark ? 0.18 : 0.13), in: Circle())
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
