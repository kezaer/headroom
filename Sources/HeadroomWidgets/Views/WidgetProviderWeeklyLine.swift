import HeadroomCore
import SwiftUI

struct WidgetProviderWeeklyLine: View {
    let provider: WidgetProviderSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: WidgetProviderStyle.symbol(for: provider.id))
                .foregroundStyle(WidgetProviderStyle.accent(for: provider.id))
                .accessibilityHidden(true)
            Text(provider.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let weekly = provider.weeklyWindow {
                Text(weekly.percentRemaining / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.title3.bold())
            } else {
                Text("—")
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
