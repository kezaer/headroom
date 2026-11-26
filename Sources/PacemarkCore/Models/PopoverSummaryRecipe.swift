import Foundation

public enum PopoverSummarySlot: String, CaseIterable, Identifiable, Sendable {
    case off, tightest, nextReset, apiSpend

    public var id: Self { self }

    public var label: String {
        switch self {
        case .off: "Off"
        case .tightest: "Tightest account"
        case .nextReset: "Next reset"
        case .apiSpend: "API spend"
        }
    }

    public func otherSlot(afterSelecting selection: Self, opposite: Self) -> Self {
        selection != .off && selection == opposite ? self : opposite
    }

    public static let firstKey = "t3.popover.summarySlot1"
    public static let secondKey = "t3.popover.summarySlot2"
}

public struct PopoverSummaryRecipe {
    public struct Candidate: Sendable {
        public let key: AccountKey
        public let title: String
        public let window: UsageWindow

        public init(key: AccountKey, title: String, window: UsageWindow) {
            self.key = key
            self.title = title
            self.window = window
        }

        public static func readings(key: AccountKey, title: String, row: LedgerRowRecipe) -> [Self] {
            guard row.message == nil, !row.isDimmed else { return [] }
            return row.windows.compactMap { cell in
                guard cell.value.displayedPercentage != nil else { return nil }
                let window = cell.value.window
                let reading = cell.resetDeadline == nil && window.resetSchedule.deadline != nil
                    ? window.withResetSchedule(.unresolved(.elapsed)) : window
                return Self(key: key, title: title, window: reading)
            }
        }
    }

    public struct Reading: Sendable {
        public let candidate: Candidate
        public let pace: MenuBarPace
        public let projection: PaceProjection?
        public let countdown: String?

        public var tightestCaption: String {
            let limit = candidate.window.displayLabel ?? LedgerRowRecipe.column(for: candidate.window.kind)
            let detail = projection?.emptyLine ?? countdown.map { "resets in \($0)" }
            return [limit, detail].compactMap { $0 }.joined(separator: " · ")
        }

        public var nextResetCaption: String {
            let limit = candidate.window.displayLabel ?? LedgerRowRecipe.column(for: candidate.window.kind)
            guard let left = UsageMeterReading(window: candidate.window).roundedPercentage(for: .remaining) else { return limit }
            return "\(limit) · \(left)% left"
        }
    }

    public enum Tile {
        case tightest(Reading)
        case nextReset(Reading)
        case apiSpend([APISpendSnapshot])

        public var slot: PopoverSummarySlot {
            switch self {
            case .tightest: .tightest
            case .nextReset: .nextReset
            case .apiSpend: .apiSpend
            }
        }
    }

    public let tiles: [Tile]

    public init(slots: [PopoverSummarySlot], candidates: [Candidate], spend: [APISpendSnapshot], now: Date) {
        let readings = Self.readings(candidates, now: now)
        let tightest = slots.contains(.tightest) ? Self.tightest(readings) : nil
        let nextReset = readings.filter { $0.countdown != nil }.min {
            guard let first = $0.candidate.window.resetSchedule.deadline,
                  let second = $1.candidate.window.resetSchedule.deadline else { return false }
            return first < second
        }

        tiles = slots.compactMap { slot in
            switch slot {
            case .off: nil
            case .tightest: tightest.map(Tile.tightest)
            case .nextReset: nextReset.map(Tile.nextReset)
            case .apiSpend: spend.isEmpty ? nil : .apiSpend(spend)
            }
        }
    }

    public static func tightest(candidates: [Candidate], now: Date) -> Reading? {
        tightest(readings(candidates, now: now))
    }

    private static func tightest(_ readings: [Reading]) -> Reading? {
        readings.min {
            let first = $0.projection?.timeToEmpty ?? .infinity
            let second = $1.projection?.timeToEmpty ?? .infinity
            return first < second || (!(second < first) && $0.pace.remaining < $1.pace.remaining)
        }
    }

    private static func readings(_ candidates: [Candidate], now: Date) -> [Reading] {
        candidates.compactMap { candidate in
            let window = candidate.window
            guard window.freshness.isLive, let pace = MenuBarPace(window: window, now: now) else { return nil }
            let deadline = window.resetSchedule.deadline
            guard deadline.map({ $0 > now }) ?? true else { return nil }
            return Reading(candidate: candidate, pace: pace,
                           projection: PaceProjection(window: window, pace: pace, now: now),
                           countdown: deadline.map { Countdown.string(to: $0, now: now) })
        }
    }
}
