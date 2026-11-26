import Foundation

/// The remaining quota and its pace against a known reset interval.
public struct MenuBarPace: Sendable, Equatable {
    public enum Tier: Sendable, Equatable {
        case onPace, ahead, wayAhead

        public var severity: UsageSeverity {
            switch self {
            case .onPace: .healthy
            case .ahead: .low
            case .wayAhead: .critical
            }
        }
    }

    public let remaining: Double
    public let expectedRemaining: Double?

    /// Unknown reset evidence leaves the tier unset so the meter can use its normal severity.
    public let tier: Tier?

    public init?(usedFraction: Double, duration: TimeInterval?, reset: Date?, now: Date) {
        guard usedFraction.isFinite else { return nil }
        let used = min(1, max(0, usedFraction))
        remaining = 1 - used
        let elapsed: Double?
        if let duration, duration.isFinite, duration > 0,
           let timeToReset = reset?.timeIntervalSince(now), timeToReset.isFinite {
            elapsed = min(1, max(0, (duration - timeToReset) / duration))
        } else {
            elapsed = nil
        }

        expectedRemaining = elapsed.map { 1 - $0 }
        if used == 1 {
            tier = .wayAhead
        } else if let elapsed {
            tier = Self.tier(used: used, elapsed: elapsed)
        } else {
            tier = nil
        }
    }

    private static func tier(used: Double, elapsed: Double) -> Tier {
        // Before 10% of the window elapses, a small amount of usage can skew the projection.
        if elapsed < 0.10 {
            if used > elapsed + 0.35 { return .wayAhead }
            if used > elapsed + 0.15 { return .ahead }
            return .onPace
        }
        let projectedUsedAtReset = used / elapsed
        if projectedUsedAtReset > 1.30 { return .wayAhead }
        if projectedUsedAtReset > 1.00 { return .ahead }
        return .onPace
    }

    public init?(window: UsageWindow, now: Date) {
        self.init(usedFraction: window.utilization / 100, duration: Self.duration(for: window.kind),
                  reset: window.resetSchedule.deadline, now: now)
    }

    public static func duration(for kind: WindowKind) -> TimeInterval? {
        switch kind {
        case .fiveHour: 18_000
        case .weekly: 604_800
        case .billingPeriod(_, let duration): duration
        case .other(let label):
            if WindowKind.weeklyModelName(in: label) != nil {
                duration(for: .weekly)
            } else {
                // Codex model counters and Antigravity pools carry their period as a suffix.
                WindowKind.modelAndPeriod(in: label).flatMap { duration(for: $0.period) }
            }
        }
    }
}
