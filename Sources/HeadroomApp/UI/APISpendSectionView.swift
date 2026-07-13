import SwiftUI
import HeadroomCore

struct APISpendSectionView: View {
    @Environment(\.colorScheme) private var scheme
    var store: UsageStore
    let now: Date
    let onOpenSettings: () -> Void

    var body: some View {
        let ids = store.apiSpendProviderOrder
        if !ids.isEmpty {
            // One raised panel with the header inside and hairline-separated rows — mirrors
            // the settings "API Spend" panel so the two surfaces share one language.
            VStack(alignment: .leading, spacing: 10) {
                Text("API Spend")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                VStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        if index > 0 {
                            Divider().overlay(Color.primary.opacity(0.08))
                                .padding(.vertical, 7)
                        }
                        spendRow(store.apiSpendSnapshot(for: id))
                            .padding(.vertical, 7)
                    }
                }
            }
            // Padding matches the provider cards above, so sibling tiles share one
            // padding and radius.
            .padding(13)
            .raisedTile(cornerRadius: 10)
        }
    }

    @ViewBuilder private func spendRow(_ snapshot: APISpendSnapshot) -> some View {
        HStack(alignment: .center, spacing: 6) {
            ProviderLogoView(providerID: snapshot.providerID, size: 19)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snapshot.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    Text("· \(store.apiSpendPeriod.displayLabel(now: now))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                // The live "Updated N min ago" sub-line is dropped — the popover header
                // already carries one consolidated stamp. Non-live states keep their
                // status line because it carries information the header does not (U2).
                if snapshot.freshness != .live {
                    statusLine(snapshot)
                }
            }
            Spacer(minLength: 8)
            amountView(snapshot)
        }
    }

    @ViewBuilder private func statusLine(_ snapshot: APISpendSnapshot) -> some View {
        switch snapshot.freshness {
        case .pending:
            Text("Waiting for cost data")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .live:
            // Live rows render no sub-line (gated out in spendRow) — the popover header
            // carries the single consolidated "Updated" stamp.
            EmptyView()
        case .stale(let reason):
            HStack(spacing: 6) {
                Text(reason.isPermanent ? "Needs setup" : "Stale")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(reason.isPermanent ? ProviderStyle.severityColor(for: .low, scheme: scheme) : .secondary)
                Text(reason.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private func amountView(_ snapshot: APISpendSnapshot) -> some View {
        if let amount = APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency) {
            Text(amount)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(snapshot.freshness == .live ? .primary : .secondary)
                .privacySensitive()
        } else {
            Button("Add key", action: onOpenSettings)
                .buttonStyle(HoverButtonStyle(horizontalPadding: 7, verticalPadding: 3))
                .font(.caption2)
        }
    }
}
