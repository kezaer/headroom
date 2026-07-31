import Foundation

/// Claude usage provider (U4). Reads the real 5-hour and weekly windows from Claude
/// Code's own `/usage` panel via `ClaudeUsageSource` — the compliant path, since the
/// official CLI makes the request and this only reads what it prints. Never throws:
/// a missing CLI or unreadable panel degrades to a typed stale state (KTD7).
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude
    public let accountID: AccountID
    public let displayName = "Claude"

    private let source: ClaudeUsageSource
    private let now: @Sendable () -> Date

    public init(
        source: ClaudeUsageSource = ClaudeUsageCLIProbe(),
        accountID: AccountID = .primary,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.accountID = accountID
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await source.capturePanel() {
        case .cliNotFound:
            return stale(.providerSetup(.claudeCLIMissing))
        case .loginRequired:
            return stale(.providerSetup(.claudeLoginRequired))
        case .workspaceTrustRequired:
            return stale(.providerSetup(.claudeTrustRequired))
        case .unknownUI:
            return stale(.providerSetup(.claudeUnknownUI))
        case .transientCapture:
            return stale(.providerSetup(.claudeTransientCapture))
        case .panel(let text, let planHint):
            let parsed = ClaudeUsageParser.parse(text)
            guard !parsed.isEmpty else {
                return stale(.providerSetup(.claudeTransientCapture))
            }
            let windows = parsed.map { window in
                UsageWindow(
                    kind: window.kind,
                    utilization: window.percentUsed,
                    resetsAt: ResetDate.parse(window.resetLabel, now: now()) ?? now(),
                    resetLabel: window.resetLabel
                )
            }
            return UsageSnapshot(
                providerID: id,
                windows: windows,
                // Panel-text tier first ("Max 20x" fidelity); the auth-status hint
                // covers the print-mode report, which omits the tier header.
                planLabel: ClaudeUsageParser.plan(in: text) ?? planHint,
                capturedAt: now(),
                freshness: .live
            )
        }
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}

/// Best-effort parse of Claude's reset text ("Resets 10:10am", "Resets Jul 2 at 10am")
/// into a `Date`, used only for the countdown fallback — the verbatim `resetLabel` is
/// what the UI actually shows, so a miss here is harmless.
enum ResetDate {
    static func parse(_ label: String?, now: Date) -> Date? {
        guard let label else { return nil }
        let text = label.replacingOccurrences(of: "Resets", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current

        // "10:10am" / "10am" -> next occurrence of that clock time.
        if let time = clockTime(text) {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.hour = time.hour; comps.minute = time.minute
            if let candidate = cal.date(from: comps) {
                return candidate > now ? candidate : cal.date(byAdding: .day, value: 1, to: candidate)
            }
        }
        // "Jul 2 at 10am" -> that month/day at that hour.
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        for format in ["MMM d 'at' ha", "MMM d 'at' h:mma", "MMMM d 'at' ha"] {
            df.dateFormat = format
            if let parsed = df.date(from: text) {
                var comps = cal.dateComponents([.month, .day, .hour, .minute], from: parsed)
                comps.year = cal.component(.year, from: now)
                if let candidate = cal.date(from: comps) { return candidate }
            }
        }
        return nil
    }

    private static func clockTime(_ text: String) -> (hour: Int, minute: Int)? {
        guard let m = text.firstMatch(of: /^(\d{1,2})(?::(\d{2}))?\s*(am|pm)/.ignoresCase()) else { return nil }
        var hour = Int(m.1) ?? 0
        let minute = m.2.flatMap { Int($0) } ?? 0
        let pm = m.3.lowercased() == "pm"
        if pm && hour < 12 { hour += 12 }
        if !pm && hour == 12 { hour = 0 }
        return (hour, minute)
    }
}
