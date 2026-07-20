import Foundation

/// Deterministic sample data for producing clean, repeatable product screenshots
/// (the marketing site at headroom.zantos.co). Activated by the `--demo` launch
/// argument. These numbers are the single source of truth for the mock, so the
/// menu-bar popover, the macOS widgets, and the iPhone all show the same moment.
///
/// This exists because the real providers read live local state: Claude/Codex usage
/// can't be posed on demand, and API spend needs admin keys the screenshot machine
/// may not have. Demo mode swaps the providers for fixed snapshots; every surface
/// still renders the real UI.
public enum DemoFixture {
    /// True when the app (macOS or iOS) was launched with `--demo`.
    public static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    // MARK: Subscription usage

    public static var claudeSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(kind: .weekly, utilization: 62, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
                UsageWindow(kind: .fiveHour, utilization: 28, resetsAt: soon(hours: 3, minutes: 15, seconds: 30), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .other("Weekly (Fable)"), utilization: 46, resetsAt: soon(days: 4, minutes: 30), resetLabel: "Resets Jul 9"),
            ],
            planLabel: "Max",
            // ~2 min ago so the popover/scene reads "Updated 2 min ago" (matches the
            // widget assets in the marketing scene and the design artboard).
            capturedAt: Date().addingTimeInterval(-135),
            freshness: .live
        )
    }

    public static var codexSnapshot: UsageSnapshot {
        UsageSnapshot(
            providerID: .codex,
            windows: [
                UsageWindow(kind: .weekly, utilization: 36, resetsAt: soon(days: 6, hours: 4, minutes: 30), resetLabel: "Resets in 6d 4h"),
            ],
            planLabel: "Prolite",
            capturedAt: Date().addingTimeInterval(-135),  // ~2 min ago (see claudeSnapshot)
            freshness: .live
        )
    }

    // MARK: API spend (macOS only)

    public static var anthropicSpend: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .claude,
            displayName: "Anthropic API",
            amount: 142.67,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(),
            freshness: .live
        )
    }

    public static var openAISpend: APISpendSnapshot {
        APISpendSnapshot(
            providerID: .codex,
            displayName: "OpenAI API",
            amount: 58.90,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(),
            freshness: .live
        )
    }

    // MARK: Manual renewal dates ("Plan renews Jul 28" / "Renews Jul 15")

    public static func renewalDate(for id: ProviderID) -> Date? {
        switch id {
        case .claude: return day(month: 7, day: 28)
        case .codex: return day(month: 7, day: 15)
        default: return nil
        }
    }

    // MARK: Helpers

    /// A future `resetsAt` for demo windows. The popover renders these live via
    /// `Countdown.resetText`, which *truncates* the remaining time — so callers add a
    /// small `minutes:`/`seconds:` buffer to keep the displayed value on the intended
    /// minute/hour despite the ~1s capture delay (KTD5: the popover derives reset text
    /// from `resetsAt`, not `resetLabel`).
    private static func soon(days: Int = 0, hours: Int = 0, minutes: Int = 0, seconds: Int = 0) -> Date {
        Date().addingTimeInterval(TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds))
    }

    private static func day(month: Int, day: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year], from: Date())
        comps.month = month
        comps.day = day
        comps.hour = 10
        return Calendar.current.date(from: comps) ?? Date()
    }
}

/// A `UsageProvider` that returns a fixed snapshot — screenshot demo mode only.
public struct DemoUsageProvider: UsageProvider {
    public let id: ProviderID
    public let accountID: AccountID
    public let displayName: String
    private let snapshot: UsageSnapshot

    public init(id: ProviderID, displayName: String, snapshot: UsageSnapshot, accountID: AccountID = .primary) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
        self.snapshot = snapshot
    }

    public func fetchSnapshot() async -> UsageSnapshot { snapshot }
}

/// An `APISpendProvider` that returns a fixed spend snapshot — screenshot demo mode only.
public struct DemoSpendProvider: APISpendProvider {
    public let id: ProviderID
    public let displayName: String
    private let snapshot: APISpendSnapshot

    public init(id: ProviderID, displayName: String, snapshot: APISpendSnapshot) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot
    }

    public func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot { snapshot }
}
