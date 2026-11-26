import Foundation

/// A notification request, free of UserNotifications types so Core can build and test
/// it (KTD1). Payloads carry display names only (KTD12).
public struct NotificationContent: Sendable, Equatable {
    /// KTD12: deterministic, so a repost replaces its banner instead of stacking.
    public let identifier: String
    /// KTD12: `<provider>.<account>`, so Notification Center groups per account.
    public let threadIdentifier: String
    public let title: String
    public let body: String

    public init(identifier: String, threadIdentifier: String, title: String, body: String) {
        self.identifier = identifier
        self.threadIdentifier = threadIdentifier
        self.title = title
        self.body = body
    }

    public static func threadIdentifier(for account: AccountKey) -> String {
        "\(account.providerID.raw).\(account.accountID.raw)"
    }

    /// R13: "{N}% of {limit} is still unused" / "Resets in {time left}, {clock}."
    /// `accountLabel` is nil unless the provider shows more than one account; the caller
    /// decides, because only the store knows the visible account count.
    public static func useItUp(
        _ proposal: UseItUpProposal,
        providerName: String,
        accountLabel: String?,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> NotificationContent {
        let limit = UseItUpEvaluator.limitName(for: proposal.kind, providerName: providerName)
        let subject = accountLabel.map { "\(limit) (\($0))" } ?? limit
        let clock = ResetClockFormatter.phrase(
            for: proposal.deadline,
            now: now,
            timeZone: timeZone,
            locale: locale,
            calendar: calendar
        )
        let account = proposal.account
        let epochMinutes = Int(proposal.deadline.timeIntervalSince1970 / 60)
        return NotificationContent(
            identifier: "use-it-up.\(account.providerID.raw).\(account.accountID.raw).\(proposal.windowID).\(epochMinutes)",
            threadIdentifier: threadIdentifier(for: account),
            title: "\(proposal.percentLeft)% of \(subject) is still unused",
            body: "Resets in \(Countdown.string(to: proposal.deadline, now: now)), \(clock)."
        )
    }

    /// A sample of the first rule at its lead time, using the tightest reading the rule can cover.
    public static func reminderPreview(
        rule: ReminderRule, scope: Set<ReminderScope>, candidates: [PopoverSummaryRecipe.Candidate], now: Date
    ) -> NotificationContent? {
        let eligible = candidates.filter { candidate in
            let kind = candidate.window.kind
            guard let family = UseItUpEvaluator.scope(for: kind, providerID: candidate.key.providerID),
                  scope.contains(family) else { return false }
            return UseItUpEvaluator.length(of: kind).map { $0 > rule.leadInterval } ?? true
        }
        guard let reading = PopoverSummaryRecipe.tightest(candidates: eligible, now: now) else { return nil }
        let candidate = reading.candidate
        let kind = candidate.window.kind
        let deadline = now.addingTimeInterval(rule.leadInterval)
        let percent = max(rule.threshold, Int(candidate.window.percentRemaining.rounded()))
        let entry = UseItUpLedgerEntry(
            account: candidate.key, windowID: kind.persistentID, deadline: deadline, firedKeys: [rule.firingKey]
        )
        let proposal = UseItUpProposal(
            account: candidate.key, kind: kind, deadline: deadline, percentLeft: percent, dueRules: [rule], ledgerEntry: entry
        )
        return useItUp(proposal, providerName: candidate.key.providerID.displayName, accountLabel: candidate.title, now: now)
    }

    /// R16: "Codex banked a reset" / "{Account} now has N banked resets." With one Codex
    /// account (`accountLabel` nil) the body reads "You now have N banked resets."
    public static func bankedReset(_ proposal: BankedResetProposal, accountLabel: String?) -> NotificationContent {
        let noun = proposal.count == 1 ? "banked reset" : "banked resets"
        let body = accountLabel.map { "\($0) now has \(proposal.count) \(noun)." }
            ?? "You now have \(proposal.count) \(noun)."
        return NotificationContent(
            identifier: "codex-banked.\(proposal.account.accountID.raw).\(proposal.count)",
            threadIdentifier: threadIdentifier(for: proposal.account),
            title: "Codex banked a reset",
            body: body
        )
    }
}
