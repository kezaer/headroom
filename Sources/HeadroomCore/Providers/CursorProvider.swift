import Foundation

public enum CursorPanelResult: Sendable, Equatable {
    case panel(String)
    case loginRequired
    case cliNotFound
    case unknownUI
    case transientCapture
}

public protocol CursorUsageSource: Sendable {
    func capturePanel() async -> CursorPanelResult
}

public enum CursorOnDemandUsage: Sendable, Equatable {
    case fixed(usedDollars: Double, limitDollars: Double)
    case unlimited(usedDollars: Double)
    case disabled(usedDollars: Double)
    case unavailable(usedDollars: Double?)

    public var usedDollars: Double? {
        switch self {
        case .fixed(let used, _), .unlimited(let used), .disabled(let used): used
        case .unavailable(let used): used
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .fixed, .unlimited: true
        case .disabled, .unavailable: false
        }
    }
}

public struct ParsedCursorUsage: Sendable, Equatable {
    public let planName: String
    public let includedPercentUsed: Double
    public let resetLabel: String
    public let resetsAt: Date
    public let onDemand: CursorOnDemandUsage
}

/// Parses only the stable labels rendered by the official Cursor Agent `/usage`
/// panel. Repeated TUI paints are harmless because the last complete match wins.
public enum CursorUsageParser {
    public static func parse(
        _ text: String,
        now: Date = Date(),
        calendar suppliedCalendar: Calendar? = nil
    ) -> ParsedCursorUsage? {
        let calendar = suppliedCalendar ?? utcCalendar
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let header = lines.reversed().compactMap(parseHeader).first,
              let included = lines.reversed().compactMap(parseIncluded).first,
              let resetsAt = resetDate(header.resetText, now: now, calendar: calendar)
        else { return nil }

        let onDemand = lines.reversed().compactMap(parseOnDemand).first ?? .unavailable(usedDollars: nil)
        return ParsedCursorUsage(
            planName: header.plan,
            includedPercentUsed: included,
            resetLabel: "Resets \(header.resetText)",
            resetsAt: resetsAt,
            onDemand: onDemand
        )
    }

    private static func parseHeader(_ line: String) -> (plan: String, resetText: String)? {
        guard let match = line.firstMatch(
            of: /Usage\s*[•·]\s*(.+?)\s+Resets\s+([A-Za-z]{3}\s+\d{1,2})/.ignoresCase()
        ) else { return nil }
        let plan = String(match.1).trimmingCharacters(in: .whitespaces)
        let reset = String(match.2)
        guard !plan.isEmpty else { return nil }
        return (plan, reset)
    }

    private static func parseIncluded(_ line: String) -> Double? {
        guard let match = line.firstMatch(
            of: /^Included\s+(\d+(?:\.\d+)?)%\s+used\b/.ignoresCase()
        ) else { return nil }
        return Double(match.1).flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
    }

    private static func parseOnDemand(_ line: String) -> CursorOnDemandUsage? {
        guard let match = line.firstMatch(of: /^On-Demand:?\s+(.+)$/.ignoresCase()) else { return nil }
        let value = String(match.1).trimmingCharacters(in: .whitespaces)
        if value.localizedCaseInsensitiveContains("Disabled") {
            return .disabled(usedDollars: 0)
        }
        if value.localizedCaseInsensitiveContains("Unavailable") {
            return .unavailable(usedDollars: nil)
        }
        if let fixed = value.firstMatch(of: /^\$([\d,]+(?:\.\d+)?)\s*\/\s*\$([\d,]+(?:\.\d+)?)/),
           let used = dollars(fixed.1), let limit = dollars(fixed.2), limit > 0 {
            return .fixed(usedDollars: used, limitDollars: limit)
        }
        if let amount = value.firstMatch(of: /^\$([\d,]+(?:\.\d+)?)/).flatMap({ dollars($0.1) }) {
            return .unlimited(usedDollars: amount)
        }
        return nil
    }

    private static func dollars(_ value: some StringProtocol) -> Double? {
        Double(String(value).replacingOccurrences(of: ",", with: ""))
    }

    private static func resetDate(_ resetText: String, now: Date, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d yyyy"
        let year = calendar.component(.year, from: now)
        guard var candidate = formatter.date(from: "\(resetText) \(year)") else { return nil }
        if candidate < calendar.startOfDay(for: now),
           let nextYear = calendar.date(byAdding: .year, value: 1, to: candidate) {
            candidate = nextYear
        }
        // The official panel exposes only a calendar day, not a reset time. Use the
        // end of that displayed UTC day for continuity expiry so a transient capture
        // failure on the reset day cannot hide a still-valid last-known meter at 00:00.
        guard let followingDay = calendar.date(byAdding: .day, value: 1, to: candidate) else {
            return candidate
        }
        return followingDay.addingTimeInterval(-1)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

public actor CursorUsageCaptureCache: CursorUsageSource {
    private let source: any CursorUsageSource
    private let cacheLifetime: TimeInterval
    private var cached: (capturedAt: Date, result: CursorPanelResult)?
    private var inFlight: Task<CursorPanelResult, Never>?

    public init(source: any CursorUsageSource, cacheLifetime: TimeInterval = 5) {
        self.source = source
        self.cacheLifetime = cacheLifetime
    }

    public func capturePanel() async -> CursorPanelResult {
        if let cached, Date().timeIntervalSince(cached.capturedAt) < cacheLifetime { return cached.result }
        if let inFlight { return await inFlight.value }
        let task = Task { await source.capturePanel() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        cached = (Date(), result)
        return result
    }
}

public struct CursorProvider: UsageProvider {
    public let id = ProviderID.cursor
    public let displayName = "Cursor"
    public let pollingLane: ProviderPollingLane = .serial("cursor-cli")
    public let accountCapacity = 1

    private let source: any CursorUsageSource
    private let emailSource: (any CursorAccountEmailReading)?
    private let now: @Sendable () -> Date

    /// `emailSource` defaults to nil rather than to the production probe: reading the
    /// identity spawns a CLI, and a default initializer must never do that unasked
    /// (tests and diagnostics construct providers directly). `AppComposition` — the one
    /// place providers are wired — supplies `CursorStatusEmailProbe`.
    public init(
        source: any CursorUsageSource,
        emailSource: (any CursorAccountEmailReading)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.emailSource = emailSource
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        // Identity is an independent free status read, so start it alongside the panel
        // capture instead of after it. Its outcome never reaches `freshness`, and only
        // the `.panel` success path joins it — a failed capture must return as soon as
        // it resolves, not after a slow identity probe runs out its deadline. An
        // unstructured Task rather than `async let`: an async-let child is implicitly
        // awaited at scope exit even when unread, and the probe's blocking thread is
        // not cancellation-interruptible, so `async let` would stall the failure paths
        // it was meant to spare. The dropped task self-bounds at the probe deadline.
        let emailTask = Task { [emailSource] in await emailSource?.readAccountEmail() ?? nil }
        let panel = await source.capturePanel()

        switch panel {
        case .panel(let text):
            let email = await emailTask.value
            let capturedAt = now()
            guard let parsed = CursorUsageParser.parse(text, now: capturedAt) else {
                return stale(.providerSetup(.cursorTransientCapture))
            }
            return UsageSnapshot(
                providerID: id,
                windows: [UsageWindow(
                    kind: BillingPeriodWindowClassifier.kind(periodType: "monthly", durationSeconds: nil),
                    utilization: parsed.includedPercentUsed,
                    resetsAt: parsed.resetsAt,
                    resetLabel: parsed.resetLabel
                )],
                planLabel: parsed.planName,
                accountEmail: email,
                capturedAt: capturedAt,
                freshness: .live
            )
        case .loginRequired: return stale(.providerSetup(.cursorAuthAbsent))
        case .cliNotFound: return stale(.providerSetup(.cursorCLIMissing))
        case .unknownUI: return stale(.providerSetup(.cursorUnknownUI))
        case .transientCapture: return stale(.providerSetup(.cursorTransientCapture))
        }
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}

public struct CursorOnDemandSpendProvider: APISpendProvider {
    public let id = ProviderID.cursor
    public let displayName = "Cursor on-demand"

    private let source: any CursorUsageSource
    private let now: @Sendable () -> Date

    public init(source: any CursorUsageSource, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.now = now
    }

    public func fetchSpend(period _: APISpendPeriod) async -> APISpendSnapshot {
        switch await source.capturePanel() {
        case .panel(let text):
            let capturedAt = now()
            guard let parsed = CursorUsageParser.parse(text, now: capturedAt) else {
                return stale(.providerSetup(.cursorTransientCapture))
            }
            return APISpendSnapshot(
                providerID: id,
                displayName: displayName,
                amount: parsed.onDemand.isEnabled ? parsed.onDemand.usedDollars : nil,
                currency: parsed.onDemand.isEnabled ? "usd" : nil,
                periodLabel: parsed.resetLabel,
                capturedAt: capturedAt,
                freshness: .live
            )
        case .loginRequired: return stale(.providerSetup(.cursorAuthAbsent))
        case .cliNotFound: return stale(.providerSetup(.cursorCLIMissing))
        case .unknownUI: return stale(.providerSetup(.cursorUnknownUI))
        case .transientCapture: return stale(.providerSetup(.cursorTransientCapture))
        }
    }

    private func stale(_ reason: FailureReason) -> APISpendSnapshot {
        .stale(providerID: id, displayName: displayName, periodLabel: "Current billing period", reason: reason)
    }
}
