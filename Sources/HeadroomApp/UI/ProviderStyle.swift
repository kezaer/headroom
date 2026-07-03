import SwiftUI
import HeadroomCore

/// Static per-provider visual identity (design review): a brand-ish accent color and
/// SF Symbol so Claude and Codex cards are distinguishable at a glance. Static only —
/// no pulsing/animated indicators (user's standing rule).
enum ProviderStyle {
    static func svgResourceName(for id: ProviderID) -> String? {
        switch id {
        case .claude: return "claude-color"
        case .codex: return "codex-color"
        default: return nil
        }
    }

    static func accent(for id: ProviderID) -> Color {
        switch id {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.26) // warm clay
        case .codex: return Color(red: 0.28, green: 0.34, blue: 1.00)  // Codex blue
        default: return .secondary
        }
    }

    /// Semantic fill for a usage bar by health band (UI-01). A static three-stop ramp —
    /// green → amber → red — chosen over the brand accent because Claude's warm clay is
    /// too close to amber to read as "warning". Brand identity stays in the logo + plan
    /// pill; the bar's job is to signal how much is left. No animation: a threshold, not
    /// a pulse, so it honors the standing no-pulsing rule.
    static func severityColor(for severity: UsageSeverity) -> Color {
        switch severity {
        case .healthy:  return Color(red: 0.20, green: 0.78, blue: 0.35) // system green
        case .low:      return Color(red: 1.00, green: 0.62, blue: 0.04) // amber
        case .critical: return Color(red: 1.00, green: 0.27, blue: 0.23) // red
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
