import SwiftUI
import WidgetKit

/// iPhone Continuity widget. Mirrors the macOS widget composition (small/medium/large in
/// `Sources/HeadroomWidgets/Views`) so both families read identically (R1/R3); only the
/// platform-specific WidgetKit chrome — `.containerBackground` and `.widgetURL` — and the
/// shared color values (via `HeadroomWidgetStyle`) live on this side.
struct HeadroomIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetContentMargins) private var contentMargins
    @Environment(\.showsWidgetContainerBackground) private var showsContainerBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: HeadroomIOSWidgetEntry

    var body: some View {
        ZStack {
            // The OS 26 Liquid Glass presentation composites a translucent sheen over the
            // `containerBackground` layer (bright at the widget's top edge, fading by
            // mid-tile — measured ~+28 RGB at top on both platforms), which made the top
            // provider card sit on a lighter surround than the bottom one. Content is not
            // veiled, so the background is drawn here in the content layer instead —
            // `contentMarginsDisabled` lets it bleed to the container edges, and the
            // system's own margins are re-applied around the actual content below. The
            // `containerBackground` copy remains for accented rendering and contexts that
            // strip backgrounds (StandBy / lock screen), where the system look should win.
            if showsContainerBackground && renderingMode == .fullColor {
                HeadroomWidgetContainerBackground()
            }
            stateContent
                .padding(expandedContentMargins)
        }
        .overlay(alignment: .topTrailing) {
            if isDemoMode {
                Text("DEMO")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .padding(contentMargins)
                    .accessibilityLabel("Demo data")
            }
        }
        .containerBackground(for: .widget) {
            HeadroomWidgetContainerBackground()
        }
        .widgetURL(URL(string: "headroom://usage"))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// WidgetKit's stock margins are deliberately generous. Reclaim four points on every
    /// edge so the provider cards occupy more of the iPhone widget without crowding the
    /// container boundary.
    private var expandedContentMargins: EdgeInsets {
        let reduction: CGFloat = 4
        return EdgeInsets(
            top: max(0, contentMargins.top - reduction),
            leading: max(0, contentMargins.leading - reduction),
            bottom: max(0, contentMargins.bottom - reduction),
            trailing: max(0, contentMargins.trailing - reduction)
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        switch entry.state {
        case .demo(let envelope):
            content(envelope)
        case .content(let envelope):
            content(envelope)
        case .disabled:
            IOSWidgetStatusView(title: "Sync Paused", message: "Enable iPhone sync on your Mac.")
        case .setupNeeded:
            IOSWidgetStatusView(title: "iCloud Needed", message: "Enable iCloud for Headroom.")
        case .waitingForMac:
            IOSWidgetStatusView(title: "Waiting for Mac", message: "Open Headroom on your Mac.")
        case .corrupt:
            IOSWidgetStatusView(title: "Unreadable Data", message: "Refresh Headroom on your Mac.")
        case .incompatibleSchema:
            IOSWidgetStatusView(title: "Update Needed", message: "Update Headroom on both devices.")
        }
    }

    private var isDemoMode: Bool {
        if case .demo = entry.state { true } else { false }
    }

    @ViewBuilder
    private func content(_ envelope: WidgetSnapshotEnvelope) -> some View {
        switch family {
        case .systemSmall:
            small(envelope)
        case .systemMedium:
            medium(envelope)
        default:
            large(envelope)
        }
    }

    // MARK: - Small

    // Mirrors `HeadroomSmallWidgetView`: a "Weekly left" header over one line per provider
    // (the overall weekly window). Quota-only and footer-free so the small family stays
    // glanceable. Model-specific sub-limits (Claude's "Weekly (Fable)") are detail for the
    // large family and the popover; at this size a third line reads as a phantom provider.
    private func small(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(envelope.providers.contains(where: { $0.primarySubscriptionWindow?.isBillingPeriod == true }) ? "Usage left" : "Weekly left")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.secondaryText(scheme: scheme))
            ForEach(envelope.providers) { provider in
                providerWeeklyLine(provider)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        // KTD1: system content margins carry the effective outer margin; keep only
        // a minimal residual so the meters have room to breathe.
        .padding(.horizontal, 2)
        .padding(.vertical, 5)
    }

    // One prominent weekly line per provider — brand mark + name + percent + bar for the
    // provider's overall weekly window (mirrors macOS `WidgetProviderWeeklyLine`). Dims
    // when that window is missing rather than dropping the row.
    private func providerWeeklyLine(_ provider: WidgetProviderSummary) -> some View {
        let window = provider.primarySubscriptionWindow
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                HeadroomWidgetProviderIcon(providerID: provider.id, size: 16)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(percent(window))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(window == nil ? HeadroomWidgetStyle.secondaryText(scheme: scheme) : .primary)
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .frame(width: 42, alignment: .trailing)
            }
            HeadroomWidgetUsageBar(
                percentRemaining: window?.percentRemaining ?? 0,
                severity: window?.severity ?? .healthy,
                dimmed: window == nil
            )
        }
    }

    // MARK: - Medium

    // Mirrors `HeadroomMediumWidgetView`: provider columns as the primary content, an
    // optional compact API-spend row under a hairline, and a freshness footer. No "Usage"
    // title or app-icon mark (R3).
    private func medium(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if envelope.apiSpendProviders.isEmpty {
                Spacer(minLength: 0)
                mediumProviderColumns(envelope.providers)
                Spacer(minLength: 0)
                mediumFooter(generatedAt: envelope.generatedAt, prefix: freshnessPrefix)
            } else {
                mediumProviderColumns(envelope.providers)
                Spacer(minLength: 6)
                // Same shared strip as the large widget; the footer drops its freshness
                // prefix here because the medium tile's width carries icons + amounts too.
                HeadroomWidgetAPISpendStrip(
                    summaries: envelope.apiSpendProviders,
                    now: entry.date,
                    footerText: Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date)
                )
            }
        }
        // KTD1: rely on WidgetKit's default content margins for the outer margin;
        // keep only a small residual so the two-column meters do not feel cramped.
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func mediumFooter(generatedAt: Date, prefix: String) -> some View {
        if let updated = Countdown.updatedLabel(capturedAt: generatedAt, now: entry.date) {
            Text("\(prefix)\(updated)")
                .font(.caption.weight(.medium))
                .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func mediumProviderColumns(_ providers: [WidgetProviderSummary]) -> some View {
        if providers.count <= 1 {
            ForEach(providers) { provider in
                providerColumn(provider, dense: false)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    providerColumn(provider, dense: providers.count > 2)
                    if index < providers.count - 1 {
                        Rectangle()
                            .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func providerColumn(_ provider: WidgetProviderSummary, dense: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                HeadroomWidgetProviderIcon(providerID: provider.id, size: 18)
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                    .widgetAccentable()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                Spacer(minLength: 0)
                if provider.freshness.needsAttention {
                    Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme))
                }
            }
            if provider.displaySubscriptionWindows.isEmpty {
                HeadroomWidgetUsageMeter(window: nil, fallbackLabel: "Weekly", compact: true, scale: dense ? .dense : nil)
            } else {
                ForEach(provider.displaySubscriptionWindows) { window in
                    HeadroomWidgetUsageMeter(window: window, fallbackLabel: window.label, compact: true, scale: dense ? .dense : nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Large

    // Mirrors `HeadroomLargeWidgetView`: provider cards, an optional API-spend section,
    // and a trailing freshness footer. No "Usage"
    // title or app-icon mark (R3).
    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        let density = LargeWidgetDensity(envelope: envelope)
        // Equal flexible spacers (same minLength) own every vertical gap — top edge, between
        // sections, and bottom edge — so SwiftUI distributes leftover height uniformly and
        // the rhythm stays symmetric no matter how many rows this user's content produces.
        // Density (a HeadroomCore tier computed from the row count) sets the floors and
        // steps the meters down from prominent when content is heavy.
        return VStack(alignment: .leading, spacing: 0) {
            gap(density)
            ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                largeProviderSection(provider, density: density)
                gap(density)
                if index < envelope.providers.count - 1 {
                    Rectangle()
                        .fill(HeadroomWidgetStyle.hairline(scheme: scheme))
                        .frame(height: 1)
                    gap(density)
                }
            }
            if envelope.apiSpendProviders.isEmpty {
                if let updated = largeFooterText(envelope) {
                    Text(updated)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HeadroomWidgetStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    gap(density)
                }
            } else {
                HeadroomWidgetAPISpendStrip(
                    summaries: envelope.apiSpendProviders,
                    now: entry.date,
                    footerText: largeFooterText(envelope)
                )
                gap(density)
            }
        }
        .padding(.horizontal, 2)
    }

    private func largeFooterText(_ envelope: WidgetSnapshotEnvelope) -> String? {
        Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date).map { "\(freshnessPrefix)\($0)" }
    }

    private func gap(_ density: LargeWidgetDensity) -> some View {
        Spacer(minLength: CGFloat(density.gapFloor))
    }

    private func largeProviderSection(_ provider: WidgetProviderSummary, density: LargeWidgetDensity) -> some View {
        // Header sits one notch closer to its first readout than the meters sit to each
        // other, so the provider name reads as a label for the block rather than a floating
        // title.
        VStack(alignment: .leading, spacing: CGFloat(density.headerSpacing)) {
            largeSectionHeader(provider, density: density)
            VStack(alignment: .leading, spacing: CGFloat(density.meterSpacing)) {
                if provider.displaySubscriptionWindows.isEmpty {
                    HeadroomWidgetUsageMeter(window: nil, fallbackLabel: "Weekly", now: entry.date, showsResetInline: true, scale: density.scale)
                } else {
                    ForEach(provider.displaySubscriptionWindows) { window in
                        HeadroomWidgetUsageMeter(window: window, fallbackLabel: window.label, now: entry.date, showsResetInline: true, scale: density.scale)
                    }
                }
                ForEach(provider.extraWeeklyWindows) { extraWindow in
                    HeadroomWidgetUsageMeter(window: extraWindow, fallbackLabel: "Weekly", now: entry.date, showsResetInline: true, scale: density.scale)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func largeSectionHeader(_ provider: WidgetProviderSummary, density: LargeWidgetDensity) -> some View {
        HStack(spacing: 6) {
            HeadroomWidgetProviderIcon(providerID: provider.id, size: CGFloat(density.providerIconSize))
            Text(provider.displayName)
                .font(providerHeaderFont(density))
                .foregroundStyle(HeadroomWidgetStyle.textAccent(for: provider.id, scheme: scheme))
                .widgetAccentable()
                .lineLimit(1)
            Spacer(minLength: 4)
            if provider.freshness.needsAttention {
                Label("Needs attention", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HeadroomWidgetStyle.severityColor(for: .low, scheme: scheme))
            }
        }
    }

    // MARK: - Helpers

    private func providerHeaderFont(_ density: LargeWidgetDensity) -> Font {
        switch density.providerHeaderFontStep {
        case .hero: return .headline.weight(.semibold)
        case .standard, .dense, .ultraDense: return .subheadline.weight(.semibold)
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private var freshnessPrefix: String {
        isDemoMode ? "sample · " : "from Mac · "
    }
}
