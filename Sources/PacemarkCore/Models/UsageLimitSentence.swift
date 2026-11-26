import Foundation

public struct UsageLimitSentence: Sendable, Equatable {
    public let window: UsageWindow
    public let text: String

    public init?(
        snapshot: UsageSnapshot,
        now: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) {
        guard let subject = Self.subject(for: snapshot.providerID) else { return nil }
        let limited = snapshot.windows.compactMap { window -> (UsageWindow, Date)? in
            guard window.isLimited, window.freshness == .live,
                  let deadline = window.resetSchedule.deadline, deadline > now
            else { return nil }
            return (window, deadline)
        }
        // Ties keep the earlier window in source order (5-hour, weekly, monthly).
        guard let (window, deadline) = limited.reduce(nil, { best, next -> (UsageWindow, Date)? in
            guard let best else { return next }
            return next.1 > best.1 ? next : best
        }) else { return nil }

        // The shared absolute reset formatter the reminders use (AGENTS.md reset rule).
        let when = ResetClockFormatter.phrase(for: deadline, now: now, timeZone: timeZone, locale: locale)
        self.window = window
        self.text = "\(subject)’s \(Self.limitName(for: window.kind)) limit is reached until \(when)"
    }

    /// Only a provider that reports `isLimited` has a sentence. OpenCode names its plan, Go,
    /// since the card already says OpenCode.
    static func subject(for providerID: ProviderID) -> String? {
        switch providerID {
        case .opencode: "Go"
        default: nil
        }
    }

    static func limitName(for kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: "5-hour"
        case .weekly: "weekly"
        case .billingPeriod(let label, _): label.lowercased()
        case .other: kind.spokenName.lowercased()
        }
    }
}

public extension UsageSnapshot {
    /// KTD7/D2: the no-plan row the Standard card draws in place of its meters, or nil.
    /// A permanent failure (signed out, CLI missing…) wins over a retained plan status: its
    /// own recovery is what the user needs first. So does a format change: it retries, but
    /// only a Pacemark update can fix it, and its Contact Support row is the only way the user
    /// learns that. A plain transient failure keeps the row, since a failed poll says nothing
    /// about the plan.
    var planStatusRecovery: ProviderRecoveryPresentation? {
        switch freshness {
        case .pending: return nil
        case .stale(let reason) where reason.isPermanent || reason.outranksPlanStatus: return nil
        case .live, .stale: return planStatus?.recoveryPresentation(for: providerID)
        }
    }
}

extension FailureReason {
    /// A non-permanent failure whose own recovery row must replace a retained plan status.
    var outranksPlanStatus: Bool {
        providerSetupOutcome == .opencodeFormatChanged
    }
}
