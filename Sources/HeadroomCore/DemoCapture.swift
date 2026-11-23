import Foundation

/// A local, display-only demo fixture. Array position supplies replay order. No live
/// account keys, identities, credential types, or CLI homes enter the encoded model.
public struct DemoCapture: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public enum Source: String, Codable, Sendable {
        case t3Code, existingCLI, externalCLI, separateLogin
    }

    public struct Account: Codable, Equatable, Sendable {
        public let provider: ProviderID
        public let label: String
        let source: Source
        let isBuiltIn: Bool
        let isRemembered: Bool
        let mergesBuiltIn: Bool
        let badge: String?
        let acknowledgedBankedResets: Int?
        let cliVersion: String?
        public let plan: String?
        let email: String?
        let credits: Int?
        let planStatus: UsageSnapshot.PlanStatus?
        let readingOffset: TimeInterval?
        let lastReadOffset: TimeInterval?
        let status: Status
        let windows: [Window]

        public var windowCount: Int { windows.count }

        init(
            account: ProviderAccount, source: Source, snapshot: UsageSnapshot, at date: Date,
            badge: String?, cliVersion: String?, acknowledgedBankedResets: Int?,
            isRemembered: Bool = false, lastReadAt: Date? = nil, mergesBuiltIn: Bool = false
        ) {
            provider = account.providerID
            label = account.label
            self.source = source
            isBuiltIn = account.isBuiltIn && !isRemembered
            self.isRemembered = isRemembered
            self.mergesBuiltIn = mergesBuiltIn
            self.badge = badge
            self.cliVersion = cliVersion
            self.acknowledgedBankedResets = acknowledgedBankedResets
            plan = snapshot.planLabel
            email = snapshot.accountEmail
            credits = snapshot.bankedResets
            planStatus = snapshot.planStatus
            readingOffset = snapshot.capturedAt?.timeIntervalSince(date)
            lastReadOffset = lastReadAt?.timeIntervalSince(date)
            status = Status(snapshot.freshness)
            windows = snapshot.windows.map { Window($0, at: date) }
        }

        func snapshot(rebasedTo date: Date, identity: AccountIdentity? = nil) -> UsageSnapshot {
            UsageSnapshot(
                providerID: provider, windows: windows.map { $0.rebased(to: date) },
                planLabel: plan, accountEmail: email, bankedResets: credits,
                capturedAt: readingOffset.map(date.addingTimeInterval), freshness: status.freshness,
                identity: identity.map(AccountIdentityOutcome.known), planStatus: planStatus
            )
        }
    }

    public var isSupportedVersion: Bool { version == Self.currentVersion }

    let version: Int
    let capturedAt: Date
    let settings: DemoCaptureSettings
    public let accounts: [Account]
    let providerOrder: [ProviderID]
    let capabilities: [Capability]
    let spend: [Spend]
    public let hasT3Claude: Bool
    public let hasT3Antigravity: Bool

    @MainActor
    public init(
        store: UsageStore, preferences: Preferences, at date: Date,
        hasT3Claude: Bool, hasT3Antigravity: Bool
    ) {
        version = Self.currentVersion
        capturedAt = date
        settings = DemoCaptureSettings(preferences, at: date)
        providerOrder = store.registeredProviderOrder + store.accountSettingsProviderIDs
            .subtracting(store.registeredProviderOrder).sorted { $0.raw < $1.raw }
        self.hasT3Claude = hasT3Claude
        self.hasT3Antigravity = hasT3Antigravity
        capabilities = providerOrder.compactMap { id in
            store.providerCapabilities[id].map { Capability(provider: id, state: $0.state) }
        }
        spend = store.registeredAPISpendProviderOrder.map { Spend(store.apiSpendSnapshot(for: $0), at: date) }
        accounts = providerOrder.flatMap { provider in
            let tracked = store.accounts(for: provider).map { account in
                Account(
                    account: account,
                    source: Self.source(for: account, store: store, hasT3Claude: hasT3Claude,
                                        hasT3Antigravity: hasT3Antigravity),
                    snapshot: store.snapshot(for: account.key), at: date,
                    badge: store.menuBarBadge(for: account.key),
                    cliVersion: store.observedCLIVersions[account.key],
                    acknowledgedBankedResets: store.bankedResetAcknowledgements?.acknowledgedCount(for: account.key),
                    mergesBuiltIn: store.displayMergeMaps[provider]?.values.contains(account.key) == true
                )
            }
            let remembered = store.displayAccounts(for: provider).compactMap { row -> Account? in
                guard row.isRemembered else { return nil }
                let lastReadAt = store.rememberedAccountRows[provider]?.first { $0.key == row.key }?.lastReadAt
                return Account(account: row.account, source: .existingCLI,
                               snapshot: store.snapshot(for: row.key), at: date, badge: nil,
                               cliVersion: nil, acknowledgedBankedResets: nil,
                               isRemembered: true, lastReadAt: lastReadAt)
            }
            return tracked + remembered
        }
    }

    @MainActor
    private static func source(
        for account: ProviderAccount, store: UsageStore, hasT3Claude: Bool, hasT3Antigravity: Bool
    ) -> Source {
        switch account.origin {
        case .borrowed(let home): return home.source.isT3 ? .t3Code : .externalCLI
        case .headroomOwned: return .separateLogin
        case .cliDefault:
            let sharesClaude = account.providerID == .claude && store.tracksT3Claude && hasT3Claude
            let sharesAntigravity = account.providerID == .antigravity && hasT3Antigravity
                && store.antigravitySourcePreference == .autoPreferT3
            return sharesClaude || sharesAntigravity ? .t3Code : .existingCLI
        }
    }

    struct Window: Codable, Equatable, Sendable {
        let kind: String
        let billingDuration: TimeInterval?
        let usedFraction: Double
        let resetOffset: TimeInterval?
        let unresolvedReset: String?
        let observedOffset: TimeInterval?
        let staleOffset: TimeInterval?
        let unavailableOffset: TimeInterval?
        let isLimited: Bool

        init(_ window: UsageWindow, at date: Date) {
            kind = window.kind.persistentID
            if case .billingPeriod(_, let duration) = window.kind { billingDuration = duration }
            else { billingDuration = nil }
            usedFraction = window.utilization / 100
            resetOffset = window.resetSchedule.deadline?.timeIntervalSince(date)
            unresolvedReset = window.resetSchedule.unresolvedReason?.rawValue
            observedOffset = window.observedAt?.timeIntervalSince(date)
            staleOffset = window.freshness.observedAt?.timeIntervalSince(date)
            if case .unavailable(let since) = window.freshness {
                unavailableOffset = since.timeIntervalSince(date)
            } else {
                unavailableOffset = nil
            }
            isLimited = window.isLimited
        }

        func rebased(to date: Date) -> UsageWindow {
            var windowKind = WindowKind(persistentID: kind) ?? .other(kind)
            if case .billingPeriod(let label, _) = windowKind, let billingDuration {
                windowKind = .billingPeriod(label: label, duration: billingDuration)
            }
            return UsageWindow(
                kind: windowKind, utilization: usedFraction * 100,
                resetSchedule: resetOffset.map { .scheduled(date.addingTimeInterval($0)) }
                    ?? .unresolved(unresolvedReset.flatMap(ResetUnresolvedReason.init(rawValue:)) ?? .absent),
                freshness: unavailableOffset.map { .unavailable(since: date.addingTimeInterval($0)) }
                    ?? staleOffset.map { .stale(observedAt: date.addingTimeInterval($0)) } ?? .live,
                observedAt: observedOffset.map(date.addingTimeInterval), isLimited: isLimited
            )
        }
    }

    enum Status: Codable, Equatable, Sendable {
        case pending, live
        case transient(String), needsReauth(String), scopeDenied(String), decode(String), signedOut(String)
        case setup(ProviderSetupOutcome)

        init(_ freshness: Freshness) {
            // FailureReason messages are already normalized for display. Raw errors and
            // provider response bodies are never inputs to this encoder.
            switch freshness {
            case .pending: self = .pending
            case .live: self = .live
            case .stale(.transient(let message)): self = .transient(message)
            case .stale(.needsReauth(let message)): self = .needsReauth(message)
            case .stale(.scopeDenied(let message)): self = .scopeDenied(message)
            case .stale(.decode(let message)): self = .decode(message)
            case .stale(.notLoggedIn(let message)): self = .signedOut(message)
            case .stale(.providerSetup(let outcome)): self = .setup(outcome)
            }
        }

        var freshness: Freshness {
            switch self {
            case .pending: .pending
            case .live: .live
            case .transient(let message): .stale(.transient(message))
            case .needsReauth(let message): .stale(.needsReauth(message))
            case .scopeDenied(let message): .stale(.scopeDenied(message))
            case .decode(let message): .stale(.decode(message))
            case .signedOut(let message): .stale(.notLoggedIn(message))
            case .setup(let outcome): .stale(.providerSetup(outcome))
            }
        }
    }

    struct Capability: Codable, Equatable, Sendable {
        enum Kind: String, Codable { case unknown, discovering, available, inconclusive, confirmedAbsent }

        let provider: ProviderID
        let kind: Kind
        let issue: String?

        init(provider: ProviderID, state: ProviderCapabilityState) {
            self.provider = provider
            if case .inconclusive(let issue) = state { self.issue = issue.rawValue }
            else { issue = nil }
            switch state {
            case .unknown: kind = .unknown
            case .discovering: kind = .discovering
            case .available: kind = .available
            case .inconclusive: kind = .inconclusive
            case .confirmedAbsent: kind = .confirmedAbsent
            }
        }

        var state: ProviderCapabilityState {
            switch kind {
            case .unknown: .unknown
            case .discovering: .discovering
            case .available: .available
            case .inconclusive: issue.flatMap(CLIExecutableDiscoveryIssue.init(rawValue:)).map {
                .inconclusive($0)
            } ?? .unknown
            case .confirmedAbsent: .confirmedAbsent
            }
        }
    }

    struct Spend: Codable, Equatable, Sendable {
        let provider: ProviderID
        let name: String
        let amount: Double?
        let currency: String?
        let period: String
        let kind: APISpendKind
        let readingOffset: TimeInterval?
        let status: Status

        init(_ snapshot: APISpendSnapshot, at date: Date) {
            provider = snapshot.providerID
            name = snapshot.displayName
            amount = snapshot.amount
            currency = snapshot.currency
            period = snapshot.periodLabel
            kind = snapshot.kind
            readingOffset = snapshot.capturedAt?.timeIntervalSince(date)
            status = Status(snapshot.freshness)
        }

        func snapshot(rebasedTo date: Date) -> APISpendSnapshot {
            APISpendSnapshot(providerID: provider, displayName: name, amount: amount,
                             currency: currency, periodLabel: period, kind: kind,
                             capturedAt: readingOffset.map(date.addingTimeInterval), freshness: status.freshness)
        }
    }
}
