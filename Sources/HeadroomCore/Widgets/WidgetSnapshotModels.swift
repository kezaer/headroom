import Foundation

/// A redaction-safe snapshot built for WidgetKit. It contains only display-ready usage
/// values, never provider credentials, request metadata, raw CLI output, or paths.
public struct WidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let status: WidgetExportStatus
    public let providers: [WidgetProviderSummary]
    public let apiSpendProviders: [WidgetAPISpendSummary]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        generatedAt: Date,
        status: WidgetExportStatus,
        providers: [WidgetProviderSummary],
        apiSpendProviders: [WidgetAPISpendSummary] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.status = status
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case status
        case providers
        case apiSpendProviders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        status = try container.decode(WidgetExportStatus.self, forKey: .status)
        providers = try container.decode([WidgetProviderSummary].self, forKey: .providers)
        apiSpendProviders = try container.decodeIfPresent([WidgetAPISpendSummary].self, forKey: .apiSpendProviders) ?? []
    }

    public static func disabled(generatedAt: Date) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(generatedAt: generatedAt, status: .disabled, providers: [], apiSpendProviders: [])
    }

    /// Weekly provider-by-provider values for the smallest widget. This never creates
    /// a cross-provider aggregate because Claude and Codex have independent limits.
    public var weeklyProviders: [WidgetProviderSummary] {
        providers.map { provider in
            var copy = provider
            copy.windows = provider.subscriptionWindows.filter { $0.kind == .weekly }
            return copy
        }
    }
}

public enum WidgetExportStatus: String, Codable, Sendable {
    case enabled
    case disabled
}

public struct WidgetProviderSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let planLabel: String?
    public let freshness: WidgetProviderFreshness
    public var windows: [WidgetWindowSummary]
    public let renewalDate: Date?

    public init(
        id: String,
        displayName: String,
        planLabel: String?,
        freshness: WidgetProviderFreshness,
        windows: [WidgetWindowSummary],
        renewalDate: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.planLabel = planLabel
        self.freshness = freshness
        self.windows = windows
        self.renewalDate = renewalDate
    }

    public var weeklyWindow: WidgetWindowSummary? {
        subscriptionWindows.first { $0.kind == .weekly }
    }

    public var subscriptionWindows: [WidgetWindowSummary] {
        windows.filter(\.kind.isSubscriptionWindow)
    }

    public var extraCounterWindows: [WidgetWindowSummary] {
        windows.filter { !$0.kind.isSubscriptionWindow }
    }

    public var weeklyDisplayWindows: [WidgetWindowSummary] {
        windows.filter { window in
            switch window.kind {
            case .weekly:
                return true
            case .fiveHour:
                return false
            case .other:
                return window.label.localizedCaseInsensitiveContains("weekly")
            }
        }
    }

    /// The model-specific weekly sub-limits shown as extra meters beside the primary
    /// weekly window — Claude's "Weekly (Fable)" (and Codex's spark weekly counter when
    /// enabled). Excludes the primary weekly and 5-hour windows; the projector has
    /// already decided which `.other` windows survive to the widget.
    public var extraWeeklyWindows: [WidgetWindowSummary] {
        windows.filter { window in
            guard case .other = window.kind else { return false }
            return window.label.localizedCaseInsensitiveContains("weekly")
        }
    }
}

public struct WidgetAPISpendSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let amount: Double?
    public let currency: String?
    public let periodLabel: String
    public let capturedAt: Date?
    public let freshness: WidgetProviderFreshness

    public init(
        id: String,
        displayName: String,
        amount: Double?,
        currency: String?,
        periodLabel: String,
        capturedAt: Date?,
        freshness: WidgetProviderFreshness
    ) {
        self.id = id
        self.displayName = displayName
        self.amount = amount
        self.currency = currency
        self.periodLabel = periodLabel
        self.capturedAt = capturedAt
        self.freshness = freshness
    }
}

public enum WidgetProviderFreshness: Codable, Equatable, Sendable {
    case pending
    case live
    case stale(message: String, needsAttention: Bool)

    public var needsAttention: Bool {
        switch self {
        case .pending, .live: false
        case .stale(_, let needsAttention): needsAttention
        }
    }
}

public struct WidgetWindowSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: WidgetWindowKind
    public let label: String
    public let percentRemaining: Double
    public let resetsAt: Date
    public let resetLabel: String?
    public let severity: WidgetUsageSeverity

    public init(
        kind: WidgetWindowKind,
        label: String,
        percentRemaining: Double,
        resetsAt: Date,
        resetLabel: String?,
        severity: WidgetUsageSeverity
    ) {
        self.id = kind.id
        self.kind = kind
        self.label = label
        self.percentRemaining = percentRemaining
        self.resetsAt = resetsAt
        self.resetLabel = resetLabel
        self.severity = severity
    }
}

public enum WidgetWindowKind: Codable, Equatable, Sendable {
    case fiveHour
    case weekly
    case other(String)

    public var isSubscriptionWindow: Bool {
        switch self {
        case .fiveHour, .weekly: true
        case .other: false
        }
    }

    public var id: String {
        switch self {
        case .fiveHour: "fiveHour"
        case .weekly: "weekly"
        case .other(let label): "other:\(label)"
        }
    }
}

public enum WidgetUsageSeverity: String, Codable, Sendable {
    case healthy
    case low
    case critical
}
