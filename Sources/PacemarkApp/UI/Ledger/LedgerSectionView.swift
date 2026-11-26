#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct LedgerSectionView: View {
    let provider: ProviderID
    let name: String
    let entries: [ProviderAccountEntry]
    let fragment: Range<Int>?
    let capability: CapabilityRecoveryPresentation?
    let percentageMode: UsagePercentageMode
    let now: Date
    var usesEmailAsName = false
    var capabilityMessage: String?
    var actions: LedgerAccountActions?
    var retryProvider: () -> Void = {}
    var readings: [AccountKey: LedgerRowRecipe] = [:]
    var expanded: Set<AccountKey> = []
    var toggleExpansion: ((AccountKey) -> Void)?

    @State private var width = CGFloat(LedgerMetrics.columns.columnWidth)

    static func admitsPlans(requiredWidths: [CGFloat], available: CGFloat) -> Bool {
        !requiredWidths.isEmpty && requiredWidths.allSatisfy { $0 <= available }
    }

    var body: some View {
        let _ = BenchCounters.hit("LedgerSectionView")
        let rows = fragment.map { entries[$0] } ?? entries[...]
        let recipes = rows.map { entry in
            readings[entry.account.key] ?? Self.recipe(
                for: entry, percentageMode: percentageMode, now: now
            )
        }
        let accounts = zip(rows, recipes)
        let hasExpandedRows = accounts.contains { entry, recipe in
            recipe.canExpand && expanded.contains(entry.account.key)
        }
        let shownWindows = accounts.compactMap { entry, recipe -> LedgerRowRecipe.Window? in
            guard recipe.message == nil, !(recipe.canExpand && expanded.contains(entry.account.key)) else { return nil }
            return recipe.primary
        }
        let kinds = Set(shownWindows.map(\.value.window.kind.persistentID))
        let column = kinds.count == 1 ? shownWindows.first?.column : kinds.isEmpty && provider == .copilot ? "Month" : nil
        let paceHeading = hasExpandedRows ? "PACE" : "PACE · \((column ?? "LIMIT").uppercased())"
        let showsPrimaryLabel = hasExpandedRows || kinds.count > 1
        let minimumNames = accounts.compactMap { entry, recipe -> CGFloat? in
            guard let plan = PlanLabelPresentation.displayName(entry.snapshot.planLabel, provider: provider) else { return nil }
            let title = Self.identity(for: entry, usesEmailAsName: usesEmailAsName).title
            let prefix = String(title.prefix(8)) + (title.count > 8 ? "…" : "")
            let nameWidth = (prefix as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width
            let planWidth = (plan as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width
            let bankedWidth: CGFloat
            if !expanded.contains(entry.account.key), let count = recipe.primary?.bankedResets {
                let label = count < 100 ? count.formatted() : "99+"
                let textWidth = (label as NSString).size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)]).width
                bankedWidth = ceil(textWidth) + PDS.Metrics.rowMark + 3 * PDS.Space.xs + PDS.Space.s
            } else {
                bankedWidth = 0
            }
            return bankedWidth + ceil(nameWidth) + ceil(planWidth) + 2 * PDS.Space.xs + 2 * LedgerMetrics.nameGap + LedgerMetrics.disclosureWidth
        }
        let available = width - 2 * PDS.Space.m - LedgerMetrics.readingWidth - LedgerMetrics.rowGap
        let showsPlans = Self.admitsPlans(requiredWidths: minimumNames, available: available)
        PDSCard(name, count: entries.count, mark: { ProviderLogoView(providerID: provider, size: PDS.Metrics.providerMark) },
                accessory: { header(paceHeading: paceHeading) }) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                LedgerAccountRow(
                    entry: entry, identity: Self.identity(for: entry, usesEmailAsName: usesEmailAsName),
                    recipe: recipes[index], showsPlan: showsPlans, showsPrimaryLabel: showsPrimaryLabel,
                    percentageMode: percentageMode, now: now, actions: actions, capabilityMessage: capabilityMessage,
                    isExpanded: expanded.contains(entry.account.key), toggleExpansion: toggleExpansion
                )
                .id(entry.account.key)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private func header(paceHeading: String) -> some View {
        HStack(spacing: LedgerMetrics.rowGap) {
            if let capability, let account = entries.first?.account {
                let recovery = capability.recovery
                Text(capabilityMessage ?? recovery.status)
                    .font(PopoverLedgerType.sentence).foregroundStyle(PDS.Ink.inkSecondary)
                    .lineLimit(1).pdsHoverTip(recovery.status)
                recoveryButton(recovery.primaryLabel, action: recovery.primaryAction,
                               recovery: capability, account: account)
                    .fixedSize()
                if let action = recovery.secondaryAction, let label = recovery.secondaryLabel,
                   capability.state(for: action) == .enabled {
                    CardRowGlyphButton(label: label, systemImage: "ellipsis", accountLabel: nil) {
                        SetupSessions.performRecovery(action, for: account, onRetry: retryProvider)
                    }
                }
            } else {
                HStack(spacing: .zero) {
                    Text(paceHeading)
                        .lineLimit(1).allowsTightening(true).minimumScaleFactor(0.84)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(percentageMode == .used ? "USED" : "LEFT").fixedSize().padding(.leading, PDS.Space.m)
                }.font(PopoverLedgerType.column).tracking(PDS.Typography.tracking)
                    .foregroundStyle(PDS.Ink.inkSecondary)
                    .frame(width: LedgerMetrics.paceWidth + LedgerMetrics.rowGap + LedgerMetrics.percentageWidth, alignment: .trailing)
                tableHeading("RESETS", width: LedgerMetrics.resetWidth)
            }
        }
    }

    private func tableHeading(_ title: String, width: CGFloat, alignment: Alignment = .trailing) -> some View {
        Text(title).font(PopoverLedgerType.column).tracking(0.6)
            .foregroundStyle(PDS.Ink.inkSecondary)
            .lineLimit(1).truncationMode(.tail)
            .frame(width: width, alignment: alignment)
    }

    private func recoveryButton(
        _ label: String, action: SetupRecoveryAction,
        recovery: CapabilityRecoveryPresentation, account: ProviderAccount
    ) -> some View {
        let state = recovery.state(for: action)
        return Button(label) { SetupSessions.performRecovery(action, for: account, onRetry: retryProvider) }
            .buttonStyle(SetupChipButtonStyle(size: .small))
            .disabled(state != .enabled)
            .pdsHoverTip(state == .enabled ? recovery.recovery.status : "Close setup, then retry")
    }

    static func identity(for entry: ProviderAccountEntry, usesEmailAsName: Bool) -> DesktopAccountIdentity {
        DesktopAccountIdentity(title: entry.account.label, email: entry.snapshot.accountEmail,
                               showsPersistentEmail: false, usesEmailAsName: usesEmailAsName)
    }

    nonisolated static func recipe(
        for entry: ProviderAccountEntry, percentageMode: UsagePercentageMode, now: Date,
        windowChoice: MenuBarWindowChoice = .weekly
    ) -> LedgerRowRecipe {
        LedgerRowRecipe(
            snapshot: entry.snapshot, percentageMode: percentageMode, now: now, windowChoice: windowChoice,
            isRemembered: entry.isRemembered, lastReadAt: entry.lastReadAt
        )
    }

    static func slots(
        provider: ProviderID, entries: [ProviderAccountEntry], readings: [AccountKey: LedgerRowRecipe],
        expanded: Set<AccountKey>
    ) -> [PopoverColumnSlot] {
        entries.map { entry in
            let key = entry.account.key
            let recipe = readings[key]
            let details = expanded.contains(key) && recipe?.canExpand == true ? recipe?.windows.count ?? 0 : 0
            return PopoverColumnSlot(id: "ledger:\(key.description)", providerID: provider,
                                     fragmentHeader: Double(LedgerMetrics.sectionHeaderHeight),
                                     fixedHeight: Double(LedgerMetrics.paddedRowHeight + CGFloat(details) * LedgerMetrics.detailRowHeight))
        }
    }
}
