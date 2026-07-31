import HeadroomCore
import SwiftUI

/// One prominent weekly line per provider — brand mark + name + percent + bar for the
/// provider's overall weekly window. Dims when that window is missing rather than dropping
/// the row. Kept in step with the iOS small widget's `providerWeeklyLine`.
struct WidgetProviderWeeklyLine: View {
    let provider: WidgetProviderSummary

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let window = provider.primarySubscriptionWindow
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                WidgetProviderIcon(providerID: provider.id, size: 16)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(percent(window))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(window == nil ? WidgetProviderStyle.secondaryText(scheme: scheme) : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 42, alignment: .trailing)
            }
            WidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil
            )
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }
}
