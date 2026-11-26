#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct LedgerSpendTable: View {
    let snapshots: [APISpendSnapshot]
    let period: String
    let onOpenSettings: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        PDSCard("API spend", mark: { Image(systemName: "creditcard").foregroundStyle(.secondary) }, accessory: {
            PDSCapsHeader(period)
        }) {
            ForEach(snapshots, id: \.providerID) { snapshot in
                row(snapshot)
            }
        }

    }

    private func row(_ snapshot: APISpendSnapshot) -> some View {
        let status = APISpendPresentation.rowStatus(freshness: snapshot.freshness, providerID: snapshot.providerID,
                                                     displayName: snapshot.displayName, kind: snapshot.kind)
        let amount = APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency)
        return HStack(spacing: PDS.Space.xs) {
            ProviderLogoView(providerID: snapshot.providerID, size: 14)
            Text(snapshot.displayName)
                .font(PopoverLedgerType.name).lineLimit(1)
            if let badge = status.shortBadge { LedgerChip(text: badge) }
            Spacer(minLength: 0)
            if let label = status.callToAction, status.showsCTA(hasAmount: amount != nil) {
                Button(label, action: onOpenSettings)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
                    .lineLimit(1)
            }
            if let amount {
                Text(snapshot.kind == .balance ? "\(amount) left" : amount)
                    .font(PopoverLedgerType.value)
                    .foregroundStyle(snapshot.freshness == .live ? Color.primary : ProviderStyle.tertiaryText(scheme: scheme))
                    .fixedSize()
            }
        }
        .frame(height: LedgerMetrics.accountContentHeight)
        .pdsHoverTip([snapshot.displayName, amount, status.message].compactMap { $0 }.joined(separator: "\n"))
    }

    static func slot(sourceCount: Int) -> PopoverColumnSlot {
        PopoverColumnSlot(id: PopoverColumnSlot.spendID, providerID: nil,
                          fragmentHeader: Double(LedgerMetrics.sectionHeaderHeight),
                          fixedHeight: Double(LedgerMetrics.paddedRowHeight) * Double(sourceCount)
                            + Double(max(0, sourceCount - 1)) * Double(PDS.Metrics.dividerSlot))
    }
}
