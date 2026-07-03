import HeadroomCore
import SwiftUI

struct WidgetUsageMeter: View {
    let window: WidgetWindowSummary?
    let fallbackLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window?.label ?? fallbackLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if let window {
                    Text(window.percentRemaining / 100, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.bold())
                } else {
                    Text("—")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: (window?.percentRemaining ?? 0) / 100)
                .tint(WidgetProviderStyle.severityColor(for: window?.severity ?? .healthy))
        }
    }
}
