import Foundation

/// A redaction-safe snapshot built for WidgetKit. It contains only display-ready usage
/// values, never provider credentials, request metadata, raw CLI output, or paths.
public struct WidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let oldestSupportedSchemaVersion = 1

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

    public static func supports(schemaVersion: Int) -> Bool {
        (oldestSupportedSchemaVersion...Self.schemaVersion).contains(schemaVersion)
    }

    /// Weekly provider-by-provider values for the smallest widget. This never creates
    /// a cross-provider aggregate because Claude and Codex have independent limits.
    public var weeklyProviders: [WidgetProviderSummary] {
        providers.map { provider in
            var copy = provider
            copy.windows = provider.primarySubscriptionWindow.map { [$0] } ?? []
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

    /// The one period-level meter used by constrained widget families. Existing
    /// providers keep preferring weekly; period-only providers fall back honestly.
    public var primarySubscriptionWindow: WidgetWindowSummary? {
        weeklyWindow
            ?? subscriptionWindows.first(where: \.isBillingPeriod)
            ?? subscriptionWindows.first
    }

    public var subscriptionWindows: [WidgetWindowSummary] {
        windows.filter(\.isSubscriptionWindow)
    }

    public var displaySubscriptionWindows: [WidgetWindowSummary] {
        subscriptionWindows.enumerated().sorted { lhs, rhs in
            func rank(_ window: WidgetWindowSummary) -> Int {
                if window.kind == .weekly || window.isBillingPeriod { return 0 }
                if window.kind == .fiveHour { return 1 }
                return 2
            }
            return (rank(lhs.element), lhs.offset) < (rank(rhs.element), rhs.offset)
        }.map(\.element)
    }

    public var extraCounterWindows: [WidgetWindowSummary] {
        windows.filter { !$0.isSubscriptionWindow }
    }

    public var weeklyDisplayWindows: [WidgetWindowSummary] {
        windows.filter { window in
            switch window.kind {
            case .weekly:
                return true
            case .fiveHour:
                return false
            case .other:
                return window.isBillingPeriod
                    || window.label.localizedCaseInsensitiveContains("weekly")
            }
        }
    }

    /// Model-specific weekly sub-limits retained for compact large-widget context,
    /// including Claude's "Weekly (Fable)" and Codex's optional Spark weekly counter.
    /// Excludes the primary weekly and 5-hour windows; the projector has already decided
    /// which `.other` windows survive to the widget.
    public var extraWeeklyWindows: [WidgetWindowSummary] {
        windows.filter { window in
            guard case .other = window.kind, !window.isBillingPeriod else { return false }
            return window.label.localizedCaseInsensitiveContains("weekly")
        }
    }

    /// The most restrictive model-specific weekly limit, when it communicates a
    /// different whole-number value than the provider's primary weekly limit.
    /// Large widgets use this as compact header context instead of adding another meter.
    public var limitingExtraWeeklyWindow: WidgetWindowSummary? {
        guard let extraWindow = extraWeeklyWindows.lazy.filter({
            $0.displayPercentRemaining != nil
        }).min(by: {
            $0.percentRemaining < $1.percentRemaining
        }) else {
            return nil
        }
        guard let weeklyWindow else { return extraWindow }
        return extraWindow.roundedPercentRemaining < weeklyWindow.roundedPercentRemaining
            ? extraWindow
            : nil
    }
}

public struct WidgetAPISpendSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let amount: Double?
    public let currency: String?
    public let periodLabel: String
    /// Additive v2 field. Missing values from older writers mean period spend.
    public let kind: APISpendKind?
    public let capturedAt: Date?
    public let freshness: WidgetProviderFreshness

    public init(
        id: String,
        displayName: String,
        amount: Double?,
        currency: String?,
        periodLabel: String,
        kind: APISpendKind? = nil,
        capturedAt: Date?,
        freshness: WidgetProviderFreshness
    ) {
        self.id = id
        self.displayName = displayName
        self.amount = amount
        self.currency = currency
        self.periodLabel = periodLabel
        self.kind = kind
        self.capturedAt = capturedAt
        self.freshness = freshness
    }

    public var semanticKind: APISpendKind { kind ?? .periodSpend }
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
    public let freshness: WidgetWindowFreshness
    /// Additive v2 wire discriminator. Older readers ignore it and see an honest
    /// labeled `.other` window; current readers recover subscription semantics.
    public let billingPeriodDuration: TimeInterval?

    public init(
        kind: WidgetWindowKind,
        label: String,
        percentRemaining: Double,
        resetsAt: Date,
        resetLabel: String?,
        severity: WidgetUsageSeverity,
        freshness: WidgetWindowFreshness = .live,
        billingPeriodDuration: TimeInterval? = nil
    ) {
        self.id = kind.id
        self.kind = kind
        self.label = label
        self.percentRemaining = percentRemaining
        self.resetsAt = resetsAt
        self.resetLabel = resetLabel
        self.severity = severity
        self.freshness = freshness
        self.billingPeriodDuration = billingPeriodDuration
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case label
        case percentRemaining
        case resetsAt
        case resetLabel
        case severity
        case freshness
        case billingPeriodDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(WidgetWindowKind.self, forKey: .kind)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? kind.id
        label = try container.decode(String.self, forKey: .label)
        percentRemaining = try container.decode(Double.self, forKey: .percentRemaining)
        resetsAt = try container.decode(Date.self, forKey: .resetsAt)
        resetLabel = try container.decodeIfPresent(String.self, forKey: .resetLabel)
        severity = try container.decode(WidgetUsageSeverity.self, forKey: .severity)
        freshness = try container.decodeIfPresent(WidgetWindowFreshness.self, forKey: .freshness) ?? .live
        billingPeriodDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .billingPeriodDuration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encode(percentRemaining, forKey: .percentRemaining)
        try container.encode(resetsAt, forKey: .resetsAt)
        try container.encodeIfPresent(resetLabel, forKey: .resetLabel)
        try container.encode(severity, forKey: .severity)
        try container.encode(freshness, forKey: .freshness)
        try container.encodeIfPresent(billingPeriodDuration, forKey: .billingPeriodDuration)
    }

    public var roundedPercentRemaining: Int {
        Int(percentRemaining.rounded())
    }

    public var displayPercentRemaining: Double? {
        freshness.isUnavailable ? nil : percentRemaining
    }

    public var isBillingPeriod: Bool {
        guard let billingPeriodDuration else { return false }
        return billingPeriodDuration.isFinite && billingPeriodDuration > 0
    }

    public var isSubscriptionWindow: Bool {
        kind.isSubscriptionWindow || isBillingPeriod
    }

    /// Shortens model-specific labels for constrained widget headers. For example,
    /// "Weekly (Fable)" becomes "Fable" and Codex Spark weekly labels become "Spark".
    public var compactLabel: String {
        if label.localizedCaseInsensitiveContains("spark"),
           label.localizedCaseInsensitiveContains("weekly") {
            return "Spark"
        }
        let prefix = "Weekly ("
        guard label.hasPrefix(prefix), label.hasSuffix(")") else { return label }
        let contentStart = label.index(label.startIndex, offsetBy: prefix.count)
        let contentEnd = label.index(before: label.endIndex)
        guard contentStart < contentEnd else { return label }
        return String(label[contentStart..<contentEnd])
    }
}

public enum WidgetWindowFreshness: Codable, Equatable, Sendable {
    case live
    case stale(observedAt: Date)
    case unavailable(since: Date)

    public var isLive: Bool {
        if case .live = self { return true }
        return false
    }

    public var isStale: Bool {
        if case .stale = self { return true }
        return false
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
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
