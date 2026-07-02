import Foundation

/// Which limit window a `UsageWindow` describes. `.other` carries an unrecognized
/// window's label verbatim so a new server-side window never fails decoding (KTD6).
public enum WindowKind: Sendable, Equatable, Hashable {
    case fiveHour
    case weekly
    case other(String)

    /// Short human label used in the menu bar summary and accessibility text.
    public var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "weekly"
        case .other(let label): return label
        }
    }
}

/// One usage window: how much has been consumed and when it resets.
///
/// `resetsAt` is always the server-provided reset time — never a client-side guess
/// about window length (R3, KTD6). `utilization` is 0–100 percent consumed.
public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let utilization: Double
    public let resetsAt: Date

    public init(kind: WindowKind, utilization: Double, resetsAt: Date) {
        self.kind = kind
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    /// Percentage of the window still available (R1/R2). Clamped to 0…100 so an
    /// over-limit `utilization > 100` reads as 0 remaining rather than negative.
    public var percentRemaining: Double {
        min(100, max(0, 100 - utilization))
    }
}

/// Typed failure reason (KTD7). Failures are always one of these cases — never a
/// free-form string built from a caught `Error`, `URLRequest`, or `HTTPURLResponse`,
/// which is how tokens leak into logs/UI (R10). Each case carries a short,
/// already-redacted message safe to display.
public enum FailureReason: Sendable, Equatable, Error {
    /// Retry on the next cycle (network error, 429, expired-but-refreshable token).
    case transient(String)
    /// Permanent until the user re-authenticates in the source CLI.
    case needsReauth(String)
    /// The token cannot call the endpoint at all (missing `user:profile` scope, KTD1).
    case scopeDenied(String)
    /// Response body could not be parsed; treated as transient-style stale.
    case decode(String)
    /// No credential is present yet (Keychain item / auth.json absent).
    case notLoggedIn(String)

    /// User-facing message for the stale card (already redaction-safe).
    public var message: String {
        switch self {
        case .transient(let m), .needsReauth(let m), .scopeDenied(let m),
             .decode(let m), .notLoggedIn(let m):
            return m
        }
    }

    /// Whether the poller should keep retrying, or stop and wait for the user.
    public var isPermanent: Bool {
        switch self {
        case .transient: return false
        case .needsReauth, .scopeDenied, .notLoggedIn: return true
        case .decode: return false
        }
    }
}

/// Snapshot freshness. `.pending` is the genuine first-run state before any
/// successful fetch — distinct from `.stale`, so the UI never fabricates a
/// nonsensical "updated 0 min ago" on launch (design review P0).
public enum Freshness: Sendable, Equatable {
    case pending
    case live
    case stale(FailureReason)
}

/// A provider's usage at a point in time. `capturedAt` is nil while `.pending`.
public struct UsageSnapshot: Sendable, Equatable {
    public let providerID: ProviderID
    public let windows: [UsageWindow]
    /// Lenient plan label — any string passes through (KTD6); nil when absent.
    public let planLabel: String?
    public let capturedAt: Date?
    public let freshness: Freshness

    public init(
        providerID: ProviderID,
        windows: [UsageWindow],
        planLabel: String?,
        capturedAt: Date?,
        freshness: Freshness
    ) {
        self.providerID = providerID
        self.windows = windows
        self.planLabel = planLabel
        self.capturedAt = capturedAt
        self.freshness = freshness
    }

    /// The first-run snapshot for a provider: no data, no timestamp.
    public static func pending(for providerID: ProviderID) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
            capturedAt: nil,
            freshness: .pending
        )
    }

    /// A failed fetch with no fresh data. The store merges prior windows back in for
    /// continuity (KTD7), so this carries none of its own.
    public static func stale(for providerID: ProviderID, reason: FailureReason) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: [],
            planLabel: nil,
            capturedAt: nil,
            freshness: .stale(reason)
        )
    }

    /// Re-mark an existing snapshot as stale, preserving its last-known windows so
    /// the UI keeps showing prior data dimmed rather than blanking (KTD7). If there
    /// is no prior data yet, the result stays `.pending`-shaped but carries the reason.
    public func markedStale(_ reason: FailureReason) -> UsageSnapshot {
        UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: planLabel,
            capturedAt: capturedAt,
            freshness: .stale(reason)
        )
    }
}
