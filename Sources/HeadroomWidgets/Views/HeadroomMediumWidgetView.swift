import HeadroomCore
import SwiftUI

struct HeadroomMediumWidgetView: View {
    let envelope: WidgetSnapshotEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Headroom")
                .font(.headline)
            ForEach(envelope.providers) { provider in
                WidgetProviderRow(provider: provider, showsDetails: false, now: envelope.generatedAt)
            }
        }
        .padding()
    }
}
