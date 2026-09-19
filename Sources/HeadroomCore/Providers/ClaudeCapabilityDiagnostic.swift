import Foundation

public enum ClaudeCLIVersionBand: String, Sendable, Equatable, CaseIterable {
    case printSupported
    case ptyFallback
    case unknown
}

public enum ClaudeCapabilityDiagnosticAccount: String, Sendable, Equatable, CaseIterable {
    case builtIn
    case extra
}

public enum ClaudeCapabilityDiagnosticOutcome: String, Sendable, Equatable, CaseIterable {
    case available
    case loginRequired
    case trustRequired
    case confirmedAbsent
    case discoveryInconclusive
    case captureFailed
    case unknownSurface
}

/// Redaction-safe Claude incident output. Its inputs are closed enums and timestamps,
/// so executable/config paths, identities, provider output, and caught errors cannot
/// cross this boundary accidentally.
///
/// R16/R17 (2026-09-19 sign-in plan) extend that boundary to the sign-out record: a
/// `SignOutEvent` carries only an account key Headroom itself minted and a detection
/// time, so it crosses here for the same reason the closed enums above do.
public enum ClaudeCapabilityDiagnostic {
    public static func lines(
        account: ClaudeCapabilityDiagnosticAccount,
        versionBand: ClaudeCLIVersionBand,
        outcome: ClaudeCapabilityDiagnosticOutcome,
        events: [CLIExecutableDiagnosticEvent],
        signOutEvents: [SignOutEvent] = [],
        now: Date = Date()
    ) -> [String] {
        var lines = [
            "account-category=\(account.rawValue)",
            "cli-version-band=\(versionBand.rawValue)",
            "capability-outcome=\(outcome.rawValue)",
        ]
        lines += events.suffix(8).map { event in
            let age = max(0, Int(now.timeIntervalSince(event.observedAt)))
            return "capability-event=\(event.category.rawValue) age-seconds=\(age)"
        }
        lines += signOutLines(signOutEvents)
        return lines
    }

    /// The count and the detection timestamps, grouped per account key. The count is
    /// always printed so an empty record reads as "none observed" rather than as a
    /// section that failed to run.
    private static func signOutLines(_ events: [SignOutEvent]) -> [String] {
        var lines = ["sign-out-events=\(events.count)"]
        var order: [AccountKey] = []
        var grouped: [AccountKey: [Date]] = [:]
        for event in events {
            if grouped[event.account] == nil { order.append(event.account) }
            grouped[event.account, default: []].append(event.detectedAt)
        }
        let formatter = ISO8601DateFormatter()
        for account in order {
            let detections = grouped[account] ?? []
            lines.append("sign-out-account=\(account.description) count=\(detections.count)")
            lines += detections.map { "sign-out-detected-at=\(formatter.string(from: $0))" }
        }
        return lines
    }
}
