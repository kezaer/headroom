import SwiftUI
import UsageBarCore

/// Static per-provider visual identity (design review): a brand-ish accent color and
/// SF Symbol so Claude and Codex cards are distinguishable at a glance. Static only —
/// no pulsing/animated indicators (user's standing rule).
enum ProviderStyle {
    static func accent(for id: ProviderID) -> Color {
        switch id {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.26) // warm clay
        case .codex: return Color(red: 0.10, green: 0.65, blue: 0.53)  // teal
        default: return .secondary
        }
    }

    static func symbol(for id: ProviderID) -> String {
        switch id {
        case .claude: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        default: return "circle.dashed"
        }
    }
}
