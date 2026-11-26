import Foundation

/// Auto ranks this account's limits by projected run-out. A missing named limit falls back to the
/// least remaining readable limit until the selected one returns.
public struct MenuBarWindowResolver: Sendable {
    public let ledger: LedgerRowRecipe
    public let selected: LedgerRowRecipe.Window?
    public let reportedLimit: LedgerRowRecipe.Window?
    public let isMissingLimit: Bool

    public init(
        snapshot: UsageSnapshot, choice: MenuBarMeterWindow, ledgerChoice: MenuBarWindowChoice,
        percentageMode: UsagePercentageMode, now: Date, showsCodexSparkCounters: Bool,
        showsAntigravityFiveHourWindows: Bool
    ) {
        ledger = LedgerRowRecipe(snapshot: snapshot, percentageMode: percentageMode, now: now,
                                 windowChoice: ledgerChoice, showsCodexSparkCounters: showsCodexSparkCounters,
                                 showsAntigravityFiveHourWindows: showsAntigravityFiveHourWindows)
        let leastLeft = ledger.windows.filter { $0.value.displayedPercentage != nil }
            .min { $0.value.window.percentRemaining < $1.value.window.percentRemaining }
        switch choice {
        case .auto:
            let key = AccountKey(providerID: snapshot.providerID, accountID: .primary)
            let candidates = PopoverSummaryRecipe.Candidate.readings(key: key, title: "", row: ledger)
            let kind = PopoverSummaryRecipe.tightest(candidates: candidates, now: now)?.candidate.window.kind
            selected = ledger.windows.first { $0.value.window.kind == kind } ?? leastLeft
            reportedLimit = nil
            isMissingLimit = false
        case .limit(let id):
            let reported = ledger.windows.first { $0.value.window.kind.persistentID == id }
            reportedLimit = reported
            isMissingLimit = reported?.value.displayedPercentage == nil
            selected = isMissingLimit ? leastLeft ?? reported : reported
        }
    }
}
