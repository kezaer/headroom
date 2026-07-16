import SwiftUI

struct MirrorView: View {
    let envelope: WidgetSnapshotEnvelope
    let syncInfo: IOSCompanionSyncInfo?
    var diagnostics: IOSSyncDiagnostics? = nil
    let isDemoMode: Bool
    let canExitDemo: Bool
    let demoWidgetUnavailable: Bool
    let onExitDemo: () -> Void
    @Binding var appearance: AppearanceSetting
    var onRefresh: () async -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        // A per-minute `now` so "Updated N min ago" and the reset countdowns tick without a
        // data poll — same pattern the Mac popover uses.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            ScrollView {
                VStack(spacing: 12) {
                    if isDemoMode {
                        DemoModeBanner(
                            canExitDemo: canExitDemo,
                            widgetUnavailable: demoWidgetUnavailable,
                            onExitDemo: onExitDemo
                        )
                    }
                    LazyVGrid(columns: providerColumns, alignment: .center, spacing: 12) {
                        ForEach(Array(envelope.providers.enumerated()), id: \.element.id) { index, provider in
                            ProviderTileView(
                                provider: provider,
                                now: context.date,
                                entranceDelay: reduceMotion ? 0 : Double(index) * 0.055
                            )
                            .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    if !envelope.apiSpendProviders.isEmpty {
                        APISpendMirrorView(
                            summaries: envelope.apiSpendProviders,
                            now: context.date,
                            entranceDelay: reduceMotion ? 0 : Double(envelope.providers.count) * 0.055
                        )
                        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
                    }
                }
                .frame(maxWidth: horizontalSizeClass == .regular ? 980 : .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .background(HeadroomTheme.backgroundView(scheme).ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .refreshable { await onRefresh() }
            // Native large title + subtitle (iOS 26): "Usage" is the screen title and
            // collapses into the bar on scroll; the freshness stamp rides along as the
            // subtitle instead of a hand-built header.
            .navigationTitle("Usage")
            .navigationSubtitle(updatedText(now: context.date))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var providerColumns: [GridItem] {
        if horizontalSizeClass == .regular && envelope.providers.count > 1 {
            return [
                GridItem(.flexible(minimum: 280), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 280), spacing: 12, alignment: .top),
            ]
        }
        return [GridItem(.flexible())]
    }

    private func updatedText(now: Date) -> String {
        if isDemoMode { return "Sample data · No account connected" }
        if let updated = MirrorPresentation.updatedLabel(generatedAt: envelope.generatedAt, now: now) {
            return "Updated \(updated)"
        }
        return "Latest Mac snapshot"
    }
}

private struct DemoModeBanner: View {
    let canExitDemo: Bool
    let widgetUnavailable: Bool
    let onExitDemo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Demo Mode")
                    .font(.subheadline.weight(.semibold))
                Text(widgetUnavailable
                    ? "Sample data — widgets could not join Demo Mode"
                    : "Sample data — no accounts are connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if canExitDemo {
                Button("Exit", action: onExitDemo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(widgetUnavailable
            ? "Demo Mode. Sample data. Widgets could not join Demo Mode on this install."
            : "Demo Mode. Sample data. No accounts are connected.")
        .accessibilityIdentifier("headroom.demo.banner")
    }
}
