import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(envelope.providers) { provider in
                WidgetProviderRow(provider: provider, showsDetails: true, now: now)
            }
        }
        .padding()
    }
}
