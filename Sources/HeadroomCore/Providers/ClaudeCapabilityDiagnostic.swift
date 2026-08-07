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
public enum ClaudeCapabilityDiagnostic {
    public static func lines(
        account: ClaudeCapabilityDiagnosticAccount,
        versionBand: ClaudeCLIVersionBand,
        outcome: ClaudeCapabilityDiagnosticOutcome,
        events: [CLIExecutableDiagnosticEvent],
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
        return lines
    }
}
