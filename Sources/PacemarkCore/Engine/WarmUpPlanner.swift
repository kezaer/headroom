import Foundation

public enum WarmUpCapability: Sendable, Equatable {
    case supported
    case unavailable(reason: String)

    public static let billingPeriodProviders: [ProviderID] = [.grok, .cursor, .copilot]

    public static func forProvider(_ provider: ProviderID) -> Self {
        switch provider {
        case .claude, .codex, .antigravity: .supported
        case .grok, .cursor: .unavailable(reason: "Messages cannot advance billing periods.")
        case .copilot: .unavailable(reason: "Pacemark only reads Copilot usage.")
        case .opencode: .unavailable(reason: "Warm-up for isolated OpenCode homes is pending.")
        default: .unavailable(reason: "This provider has no warm-up sender.")
        }
    }
}

enum WarmUpCycleDeadline {
    case scheduled(Date)
    case afterSend(TimeInterval)

    func deadline(after sendCompletedAt: Date) -> Date {
        switch self {
        case .scheduled(let reset): reset
        case .afterSend(let duration): sendCompletedAt.addingTimeInterval(duration)
        }
    }
}

public enum WarmUpPlanner {
    public static let minimumSpacing: TimeInterval = 30 * 60
    public static let dailyLimit = 4
    public static let maximumReadingAge: TimeInterval = 15 * 60

    /// One decision per account, with the cycle deadline for each idle limit.
    static func idleDeadlines(
        for account: AccountKey,
        snapshot: UsageSnapshot,
        settings: WarmUpSettings,
        ledger: WarmUpLedger,
        now: Date,
        calendar: Calendar = .current,
        consentingAccounts: Set<AccountKey>? = nil,
        excludingAttemptID: UUID? = nil
    ) -> [String: WarmUpCycleDeadline] {
        let identity = snapshot.identity?.identity
        guard settings.isEnabled, WarmUpCapability.forProvider(account.providerID) == .supported,
              snapshot.providerID == account.providerID,
              snapshot.freshness == .live,
              let capturedAt = snapshot.capturedAt, isRecent(capturedAt, now: now),
              settings.activeHours.contains(now, calendar: calendar),
              ledger.canAttempt(account, identity: identity, now: now, calendar: calendar,
                                excludingAttemptID: excludingAttemptID)
        else { return [:] }

        let consentKeys = consentingAccounts ?? [account]
        var deadlines: [String: WarmUpCycleDeadline] = [:]
        for window in snapshot.windows {
            let windowID = window.kind.persistentID
            let observedAt = window.observedAt ?? capturedAt
            guard WarmUpSettings.windows(for: account.providerID).contains(window.kind), let duration = duration(for: window.kind),
                  consentKeys.contains(where: {
                      settings.enabled.contains(.init(account: $0, window: window.kind, identity: identity))
                  }),
                  window.freshness == .live, !window.isLimited, window.utilization == 0,
                  isRecent(observedAt, now: now),
                  ledger.canWarm(windowID, for: account, identity: identity, now: now, observedAt: observedAt)
            else { continue }
            let deadline: WarmUpCycleDeadline
            switch window.resetSchedule {
            case .scheduled(let reset):
                if reset > now {
                    let margin = min(0.03 * duration, 10 * 60)
                    guard reset.timeIntervalSince(now) >= duration - margin else { continue }
                    deadline = .scheduled(reset)
                } else {
                    guard !(reset > observedAt) else { continue }
                    deadline = .afterSend(duration)
                }
            case .unresolved(.absent), .unresolved(.elapsed):
                deadline = .afterSend(duration)
            case .unresolved:
                continue
            }
            if let existing = deadlines[windowID], existing.deadline(after: now) > deadline.deadline(after: now) {
                continue
            }
            deadlines[windowID] = deadline
        }
        return deadlines
    }

    public static func duration(for kind: WindowKind) -> TimeInterval? {
        if kind == AntigravityProvider.windowKind(.gemini, .fiveHour) { return 5 * 3_600 }
        if kind == AntigravityProvider.windowKind(.gemini, .weekly) { return 7 * 86_400 }
        switch kind {
        case .fiveHour: return 5 * 3_600
        case .weekly: return 7 * 86_400
        case .other, .billingPeriod: return nil
        }
    }

    private static func isRecent(_ date: Date, now: Date) -> Bool {
        !(date > now) && now.timeIntervalSince(date) <= maximumReadingAge
    }
}
