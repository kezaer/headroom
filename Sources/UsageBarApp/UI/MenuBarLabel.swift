import SwiftUI
import UsageBarCore

/// The always-visible menu bar content (R5): the compact gauge icon, with the tightest
/// live window's remaining percent optionally shown beside it.
struct MenuBarLabel: View {
    let summary: MenuBarSummary
    let showsPercentage: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            if showsPercentage, !summary.isNeutral {
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
