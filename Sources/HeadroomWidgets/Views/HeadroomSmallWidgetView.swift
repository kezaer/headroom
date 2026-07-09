import HeadroomCore
import SwiftUI

/// Small widget: one weekly meter per provider under a quiet column header.
///
/// Layout (Jul 2026 redesign): each meter line owns an equal *flexible* slot
/// (`maxHeight: .infinity`) so the content distributes across the widget's full height —
/// the old fixed-gap stack pooled a dead void under the last bar, which read top-heavy
/// and template-ish. Hierarchy got one clear step per level: 11pt header (defers), 13pt
/// brand-accent names, 16pt bold percent (the glance payload, same step as the large
/// widget's prominent meters).
///
/// Only the provider's overall weekly window appears here — one line per provider.
/// Model-specific sub-limits (Claude's "Weekly (Fable)") are detail for the large widget
/// and the popover; at this size a third line reads as a phantom third provider.
struct HeadroomSmallWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Weekly left")
                .font(.caption.weight(.medium))
                .foregroundStyle(WidgetProviderStyle.secondaryText(scheme: scheme))
            ForEach(envelope.providers) { provider in
                WidgetProviderWeeklyLine(provider: provider)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the meters have room to breathe.
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }
}
