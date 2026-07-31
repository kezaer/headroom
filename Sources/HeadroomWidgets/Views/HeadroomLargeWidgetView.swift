import HeadroomCore
import SwiftUI

struct HeadroomLargeWidgetView: View {
    let envelope: WidgetSnapshotEnvelope
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let density = LargeWidgetDensity(envelope: envelope)
        // Equal flexible spacers (same minLength) own every vertical gap — top edge, between
        // sections, and bottom edge — so SwiftUI distributes leftover height uniformly and
        // the rhythm stays symmetric no matter how many rows this user's content produces.
        // Density (a HeadroomCore tier computed from the row count) sets the floors and
        // steps the meters down from prominent when content is heavy.
        return VStack(alignment: .leading, spacing: 0) {
            gap(density)
            ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                LargeProviderSection(provider: provider, now: now, density: density)
                gap(density)
                if index < envelope.providers.count - 1 {
                    Rectangle()
                        .fill(WidgetProviderStyle.hairline(scheme: scheme))
                        .frame(height: 1)
                    gap(density)
                }
            }
            if envelope.apiSpendProviders.isEmpty {
                if let updated {
                    Text(updated)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WidgetProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    gap(density)
                }
            } else {
                WidgetAPISpendStrip(summaries: envelope.apiSpendProviders, now: now, footerText: updated)
                gap(density)
            }
        }
        .padding(.horizontal, 8)
    }

    private var updated: String? {
        Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: now).map { "from Mac · \($0)" }
    }

    private func gap(_ density: LargeWidgetDensity) -> some View {
        Spacer(minLength: CGFloat(density.gapFloor))
    }
}

private struct LargeProviderSection: View {
    let provider: WidgetProviderSummary
    let now: Date
    let density: LargeWidgetDensity

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(density.headerSpacing)) {
            header
            VStack(alignment: .leading, spacing: CGFloat(density.meterSpacing)) {
                if provider.displaySubscriptionWindows.isEmpty {
                    WidgetUsageMeter(window: nil, fallbackLabel: "Weekly", now: now, showsResetInline: true, scale: density.scale)
                } else {
                    ForEach(provider.displaySubscriptionWindows) { window in
                        WidgetUsageMeter(window: window, fallbackLabel: window.label, now: now, showsResetInline: true, scale: density.scale)
                    }
                }
                ForEach(provider.extraWeeklyWindows) { extraWindow in
                    WidgetUsageMeter(window: extraWindow, fallbackLabel: "Weekly", now: now, showsResetInline: true, scale: density.scale)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            WidgetProviderIcon(providerID: provider.id, size: CGFloat(density.providerIconSize))
            Text(provider.displayName)
                .font(providerHeaderFont())
                .foregroundStyle(WidgetProviderStyle.textAccent(for: provider.id, scheme: scheme))
                .widgetAccentable()
                .lineLimit(1)
            Spacer(minLength: 4)
            if provider.freshness.needsAttention {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WidgetProviderStyle.severityColor(for: .low, scheme: scheme))
            }
        }
    }

    private func providerHeaderFont() -> Font {
        switch density.providerHeaderFontStep {
        case .hero: return .headline.weight(.semibold)
        case .standard, .dense, .ultraDense: return .subheadline.weight(.semibold)
        }
    }
}
