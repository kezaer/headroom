import SwiftUI
import UsageBarCore

/// The always-visible menu bar content (R5): an icon plus the tightest live window's
/// remaining percent. Self-contained — the number carries a provider indicator via
/// the accessibility label and the accent-tinted glyph.
struct MenuBarLabel: View {
    let summary: MenuBarSummary

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            if !summary.isNeutral {
                Text(summary.text).font(.system(size: 12, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(tint)
        .accessibilityLabel(summary.detail.map { "\($0), \(summary.text) remaining" } ?? "AI usage")
    }

    private var tint: Color {
        guard let id = summary.providerID else { return .primary }
        return ProviderStyle.accent(for: id)
    }
}
