import Foundation

public enum MirrorRowTreatment: Equatable, Sendable {
    case normal
    case stale
    case needsAttention(String)
    case skeleton

    public var isDimmed: Bool {
        switch self {
        case .normal:
            false
        case .stale, .needsAttention, .skeleton:
            true
        }
    }

    public var pillText: String? {
        switch self {
        case .stale:
            "Stale"
        case .normal, .needsAttention, .skeleton:
            nil
        }
    }

    public var noticeText: String? {
        switch self {
        case .needsAttention(let message):
            message
        case .normal, .stale, .skeleton:
            nil
        }
    }
}

public enum MirrorPresentation {
    /// The projector has already filtered unsupported counters. The companion must render
    /// every remaining window so model-specific limits stay in parity with macOS.
    public static func windows(for provider: WidgetProviderSummary) -> [WidgetWindowSummary] {
        provider.windows
    }

    public static func treatment(for freshness: WidgetProviderFreshness) -> MirrorRowTreatment {
        switch freshness {
        case .live:
            .normal
        case .pending:
            .skeleton
        case .stale(_, let needsAttention):
            needsAttention ? .needsAttention("Sign in again on your Mac") : .stale
        }
    }

    public static func resetText(for window: WidgetWindowSummary, now: Date) -> String {
        if window.freshness.isUnavailable {
            return "Unavailable"
        }
        return Countdown.resetText(
            schedule: window.resetSchedule,
            utilization: window.utilization,
            isLive: window.freshness.isLive,
            now: now
        )
    }

    public static func windowStateText(for window: WidgetWindowSummary) -> String? {
        switch window.freshness {
        case .live:
            nil
        case .stale:
            "Last known"
        case .unavailable:
            "Unavailable"
        }
    }

    public static func updatedLabel(generatedAt: Date?, now: Date) -> String? {
        Countdown.updatedLabel(capturedAt: generatedAt, now: now)
    }

    public static func showsLowChip(severity: WidgetUsageSeverity, dimmed: Bool) -> Bool {
        severity == .critical && !dimmed
    }
}
