import HeadroomCore
import SwiftUI

struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Weekly Left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(envelope.weeklyProviders) { provider in
                WidgetProviderWeeklyLine(provider: provider, compact: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
    }
}
