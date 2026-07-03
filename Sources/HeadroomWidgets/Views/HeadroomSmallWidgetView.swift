import HeadroomCore
import SwiftUI

struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Left")
                .font(.headline)
            ForEach(envelope.weeklyProviders) { provider in
                WidgetProviderWeeklyLine(provider: provider)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
