import HeadroomCore
import SwiftUI

/// Small widget: one weekly meter per provider under a quiet column header.
///
/// The provider lines form one compact group centered in the space below the header.
/// Hierarchy has one clear step per level: 11pt header (defers), 13pt brand-accent names,
/// 16pt bold percent (the glance payload, same step as the large widget's prominent meters).
///
/// Only the provider's overall weekly window appears here — one line per provider.
/// Model-specific sub-limits (Claude's "Weekly (Fable)") are detail for the large widget
/// and the popover; at this size a third line reads as a phantom third provider.
struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let providers = envelope.widgetProviders
        VStack(alignment: .leading, spacing: 0) {
            Text(providers.contains(where: { $0.primarySubscriptionWindow?.isBillingPeriod == true }) ? "Usage left" : "Weekly left")
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(providers) { provider in
                    WidgetProviderWeeklyLine(provider: provider)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the meters have room to breathe.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}
