import SwiftUI
import UsageBarCore

/// One provider's card (U7). Renders the four explicit states from the design review
/// off `snapshot.freshness`: `.pending` first-run skeleton, `.live`, transient stale
/// (dimmed + reason), and permanent needs-reauth/scope (actionable message). Shows the
/// renewal date or a tappable "not set" affordance.
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    let renewalDate: Date?
    let now: Date
    let onOpenSettings: () -> Void

    private var accent: Color { ProviderStyle.accent(for: providerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            renewalRow
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: ProviderStyle.symbol(for: providerID))
                .foregroundStyle(accent)
            Text(displayName).font(.headline)
            if let plan = snapshot.planLabel {
                Text(plan.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.18), in: Capsule())
            }
            Spacer()
            if let updated = Countdown.updatedLabel(capturedAt: snapshot.capturedAt, now: now) {
                Text(updated).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch snapshot.freshness {
        case .pending:
            pendingSkeleton
        case .live:
            bars(dimmed: false)
        case .stale(let reason):
            staleContent(reason)
        }
    }

    @ViewBuilder private func staleContent(_ reason: FailureReason) -> some View {
        if reason.isPermanent {
            actionable(reason.message)
            if !snapshot.windows.isEmpty { bars(dimmed: true) }
        } else {
            bars(dimmed: true)
            Text(reason.message).font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func bars(dimmed: Bool) -> some View {
        if snapshot.windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(window: window, accent: accent, now: now, dimmed: dimmed)
                }
            }
        }
    }

    private var pendingSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 6)
            }
            Text("Waiting for first update…")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func actionable(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private var renewalRow: some View {
        HStack {
            Text("Renews").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            if let renewalDate {
                Text(renewalDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Renewal date not set", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(accent)
            }
        }
    }
}
