import SwiftUI
import WidgetKit

struct HeadroomIOSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HeadroomIOSWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
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
        .containerBackground(.background, for: .widget)
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

    private func small(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Left")
                .font(.headline)
            ForEach(envelope.weeklyProviders) { provider in
                providerWeeklyLine(provider)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func medium(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Headroom")
                .font(.headline)
            ForEach(envelope.providers) { provider in
                providerSummary(provider)
            }
        }
        .padding()
    }

    private func large(_ envelope: WidgetSnapshotEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Headroom")
                    .font(.headline)
                Spacer()
                Text(Countdown.updatedLabel(capturedAt: envelope.generatedAt, now: entry.date) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(envelope.providers) { provider in
                providerSummary(provider, showsDetails: true)
            }
        }
        .padding()
    }

    private func providerWeeklyLine(_ provider: WidgetProviderSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(for: provider.id))
                .foregroundStyle(accent(for: provider.id))
            Text(provider.displayName)
                .font(.caption)
            Spacer()
            Text(percent(provider.weeklyWindow))
                .font(.headline.monospacedDigit())
        }
    }

    private func providerSummary(_ provider: WidgetProviderSummary, showsDetails: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(provider.displayName, systemImage: symbol(for: provider.id))
                    .foregroundStyle(accent(for: provider.id))
                    .font(.caption.weight(.semibold))
                Spacer()
                if provider.freshness.needsAttention {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(provider.windows) { window in
                HStack {
                    Text(window.label)
                    Spacer()
                    Text("\(Int(window.percentRemaining.rounded()))%")
                        .monospacedDigit()
                }
                .font(.caption)
            }
            if showsDetails, let reset = provider.windows.first?.resetLabel {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percent(_ window: WidgetWindowSummary?) -> String {
        guard let window else { return "--" }
        return "\(Int(window.percentRemaining.rounded()))%"
    }

    private func symbol(for id: String) -> String {
        id == "claude" ? "sparkles" : "terminal"
    }

    private func accent(for id: String) -> Color {
        id == "claude" ? .orange : .green
    }
}
