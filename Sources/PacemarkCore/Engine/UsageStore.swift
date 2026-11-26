import Foundation
import Observation

public enum AccountRemovalState: Sendable, Equatable {
    case removing
    case setupActive
    case failed
}

public enum AccountRemovalResult: Sendable, Equatable {
    case removed
    case setupActive
    case failed
    case notAllowed
}

@MainActor
@Observable
public final class UsageStore {
    public internal(set) var snapshots: [AccountKey: UsageSnapshot]
    public internal(set) var accountsByProvider: [ProviderID: [ProviderAccount]] {
        didSet {
            if didLoadMenuBarSelection {
                let previous = Set(oldValue.values.joined().map(\.key))
                menuBarMeterSelection.appendNewAccounts(menuBarTrackedAccounts.filter { !previous.contains($0) })
            }
        }
    }
    public private(set) var apiSpendSnapshots: [ProviderID: APISpendSnapshot]
    public private(set) var antigravitySourcePreference: AntigravitySourcePreference
    internal var menuBarBadgeOverrides: [AccountKey: String]
    public internal(set) var borrowedHomeScanSummary: BorrowedHomeScanSummary?
    public internal(set) var tracksCLIDefaultAlongsideT3: Bool
    public private(set) var usagePercentageMode: UsagePercentageMode
    public let accountTitleInk: AccountTitleInk = .neutral
    /// The normal app uses Ledger. An explicit override is available to fixture launches.
    public let accountLayout: AccountLayout
    public private(set) var popoverExpandedAccounts: Set<AccountKey>
    public var popoverSummarySlot1: PopoverSummarySlot {
        didSet { preferences.popoverSummarySlot1 = popoverSummarySlot1 }
    }
    public var popoverSummarySlot2: PopoverSummarySlot {
        didSet { preferences.popoverSummarySlot2 = popoverSummarySlot2 }
    }
    public private(set) var expandAccountsHorizontally: Bool
    public private(set) var useEmailAsAccountName: Bool
    public private(set) var meterStyle: MeterStyle
    @ObservationIgnored private var didLoadMenuBarSelection = false
    public var showMenuBarLabels: Bool {
        didSet { preferences.defaults.set(showMenuBarLabels, forKey: "menuBarMeters.showLabels") }
    }

    public internal(set) var menuBarMeterSelection = MenuBarMeterSelection() {
        didSet {
            if menuBarMeterSelection != oldValue { preferences.menuBarMeterSelection = menuBarMeterSelection }
        }
    }
    /// Antigravity’s Claude and GPT pool visibility across display and reminder surfaces.
    public private(set) var showsAntigravityOtherModels: Bool
    /// KTD14: notification preferences, mirrored so the Notifications pane edits through
    /// the store the way `meterStyle` does.
    public private(set) var useItUpRemindersEnabled: Bool
    public private(set) var bankedResetNotificationsEnabled: Bool
    public private(set) var reminderRules: [ReminderRule]
    public private(set) var reminderScope: Set<ReminderScope>
    public private(set) var enabledSurfaces: Set<UsageSurface>
    public private(set) var providerCapabilities: [ProviderID: ProviderCapabilityStatus]
    public internal(set) var accountRemovalStates: [AccountKey: AccountRemovalState] = [:]
    public let displayNames: [ProviderID: String]
    public let apiSpendDisplayNames: [ProviderID: String]

    /// The popover's "Refreshing…" signal (UI-02). KTD2 (2026-09-19 polling plan): true
    /// only while a user-initiated request — Refresh, Check Now, a setup check — still has
    /// unmerged work. Timer-driven lane passes never set it, so the Refresh button does not
    /// disappear for half of every interval at the account envelope.
    public private(set) var isRefreshing = false
    /// Scheduler-wide clear time for run retention; visible work has its own hold clock.
    public private(set) var refreshingClearedAt: Date?
    public private(set) var visibleRefreshWork = VisibleRefreshWork()
    @ObservationIgnored private var visibleRefreshOperationDepth = 0
    /// A 0.5s visible hold plus 0.2s bookkeeping grace, distinct from ghost-wipe timing.
    private static let refreshRunRetentionDuration: TimeInterval = 0.7
    /// W4: the user-requested work behind `isRefreshing`, account by account. Nil once that
    /// work drains, even while a spend fetch keeps `isRefreshing` up.
    public private(set) var refreshProgress: RefreshProgress?
    /// Loading-language KTD1: retained through the entire spend tail and end hold.
    public private(set) var userRefreshRun: UserRefreshRun?
    public private(set) var fullRefreshInFlight = false
    @ObservationIgnored private var fullRefreshOperationDepth = 0
    @ObservationIgnored private var fullRefreshTask: Task<Void, Never>?
    /// When the in-flight full refresh started; nil while none runs.
    public private(set) var fullRefreshStartedAt: Date?
    public private(set) var lastFullRefreshCompletedAt: Date?
    public private(set) var lastProbeEndTimes: [AccountKey: Date] = [:]
    public private(set) var apiSpendInFlightProviders: Set<ProviderID> = []
    @ObservationIgnored private var spendFetchDepths: [ProviderID: Int] = [:]
    @ObservationIgnored private var refreshRunRetentionTask: Task<Void, Never>?

    public var accountActionCheckingKeys: Set<AccountKey> {
        guard !fullRefreshInFlight, let run = userRefreshRun,
              !run.entries.values.contains(where: { $0.origin == .fullRefresh && $0.outcome == nil })
        else { return [] }
        return Set(run.entries.compactMap { key, entry in
            entry.origin == .accountAction && entry.outcome == nil ? key : nil
        })
    }
    /// Accounts whose probe is running right now, timer passes included (round-3 S2).
    public private(set) var probingAccounts: Set<AccountKey> = []
    @ObservationIgnored private var userWorkPending = false
    @ObservationIgnored private var apiSpendUserRefreshDepth = 0
    @ObservationIgnored private var apiSpendInFlight = false
    /// KTD12: per-provider chosen vs effective interval for Settings, refreshed whenever a
    /// lane goes idle so the General pane observes it like any other store value.
    public private(set) var pollCadences: [ProviderID: PollCadence] = [:]
    let scheduler = AccountProbeScheduler()

    var providers: [any UsageProvider]
    private let apiSpendProviders: [any APISpendProvider]
    let preferences: Preferences
    private let capturesAllAccounts: Bool
    public private(set) var isReplayingDemoCapture = false
    let borrowedHomes: BorrowedHomeEnvironment?
    let accountRegistry: AccountRegistry?
    let accountStorage: any AccountStorageManaging
    let continuityCache: (any UsageContinuityCaching)?
    /// Default-login plan KTD4: which account each row is bound to, and the accounts that
    /// left. Nil in demos, harnesses and most tests, which leaves every row as it was.
    let defaultLoginRecordStore: (any DefaultLoginRecordStoring)?
    /// The decoded records; nil when there is no store or its envelope is unreadable.
    @ObservationIgnored var defaultLoginState: DefaultLoginRecordsState?
    /// Default-login plan U5: the remembered accounts with a row, per provider, in stored
    /// order and hidden ones included, minus any a slot reads (KTD12). Observed, unlike
    /// the records, and reassigned only when it changes, so the steady per-reading
    /// commit does not invalidate views that read it.
    var rememberedAccountRows: [ProviderID: [RememberedAccountSummary]] = [:]
    /// Default-login plan U7 (KTD10): each visible remembered row's last reading, aged by
    /// `UsageContinuityPolicy.rememberedSnapshot` at launch, on each engine wake, when the
    /// popover opens and when the rows change, so no view body ages it. Keyed by the
    /// row's local id, which never collides with an engine key.
    var rememberedDisplaySnapshots: [AccountKey: UsageSnapshot] = [:]
    /// Default-login plan U10 (KTD11): per provider, the built-in key hidden by the
    /// one-row merge to the extra that shows it. Recomputed in the same turn as any gate
    /// change (`refreshDisplayMerge`) and reassigned only when it changes, so no view body
    /// rebuilds it. Empty for a setup with no merge.
    var displayMergeMaps: [ProviderID: [AccountKey: AccountKey]] = [:]
    @ObservationIgnored var launchContinuity: [AccountKey: UsageSnapshot] = [:]
    /// KTD14 (2026-09-19 sign-in plan): diagnostics-only record of observed Claude
    /// sign-outs. Optional so the render harness, demo stores, and tests that don't
    /// care compose without it.
    let signOutRecord: SignOutRecord?
    let sessionReliabilityRecord: SessionReliabilityRecord?
    /// Per-account banked-reset announcements. Optional so tests and the demo
    /// store compose without it; the shipping store always has one (KTD6).
    let bankedResetAcknowledgements: BankedResetAcknowledgements?
    /// KTD1: use-it-up reminders and the banked-reset notice. Optional so tests, the demo
    /// store, and the render harness compose without it.
    let notificationCoordinator: NotificationCoordinator?
    public let warmUp: WarmUpAutomation
    let now: @Sendable () -> Date
    /// Builds the concrete provider for a newly added account. Lives in the composition
    /// root (R13) and is injected so the store never names concrete provider types.
    let providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)?
    private(set) var engine: PollingEngine?
    private var isStarting = false
    @ObservationIgnored var removingAccounts: Set<AccountKey> = []
    /// KTD7 (OpenCode plan): accounts whose no-plan row sent the user to the plans page. The
    /// next popover open re-checks each one once, so a plan bought there shows up without a
    /// click and without raising any cadence.
    @ObservationIgnored var popoverOpenRechecks: Set<AccountKey> = []
    @ObservationIgnored private var capabilityGenerations: [ProviderID: UInt64] = [:]
    /// Per-key attach/detach epoch. A fetch result is only merged when the attachment
    /// it started against is still current; a stop-track/remove bumps the epoch so a
    /// late pre-detach result can't overwrite a reattached row's fresh pending state
    /// or repopulate the continuity cache the detach cleared (code-review finding).
    @ObservationIgnored var attachmentGenerations: [AccountKey: UInt64] = [:]
    @ObservationIgnored var setupCoordinator: SetupSessionCoordinator?
    private let composedProviderOrder: [ProviderID]
    let composedAccountCapacities: [ProviderID: Int]
    public private(set) var tracksT3Claude: Bool
    public internal(set) var observedCLIVersions: [AccountKey: String] = [:]

    /// Popover order, including disabled providers and stopped CLI sources with zero rows.
    public var accountSettingsProviderOrder: [ProviderID] {
        (composedProviderOrder + registeredProviderOrder).uniqued()
    }

    public var enabledFirstSettingsOrder: [ProviderID] {
        let order = accountSettingsProviderOrder
        let enabled = Set(order.filter { id in
            UsageSurface.subscription(for: id).map(enabledSurfaces.contains) == true
        })
        return order.filter(enabled.contains) + order.filter { !enabled.contains($0) }
    }

    public var accountSettingsProviderIDs: Set<ProviderID> { Set(accountSettingsProviderOrder) }

    public func builtInAccountSource(
        for providerID: ProviderID, hasT3Claude: Bool, hasT3Antigravity: Bool
    ) -> AccountSourceKind {
        let sharesClaude = providerID == .claude && tracksT3Claude && hasT3Claude
        let sharesAntigravity = providerID == .antigravity && hasT3Antigravity
            && antigravitySourcePreference == .autoPreferT3
        return sharesClaude || sharesAntigravity ? .t3Code : .existingCLI
    }

    public func setTracksT3Claude(_ enabled: Bool) {
        guard tracksT3Claude != enabled else { return }
        preferences.tracksT3Claude = enabled
        tracksT3Claude = enabled
    }

    public init(
        providers: [any UsageProvider],
        apiSpendProviders: [any APISpendProvider] = [],
        preferences: Preferences = Preferences(),
        accounts: [ProviderAccount]? = nil,
        accountRegistry: AccountRegistry? = nil,
        accountStorage: any AccountStorageManaging = DefaultAccountStorage(),
        borrowedHomes: BorrowedHomeEnvironment? = nil,
        providerFactory: (@MainActor (ProviderAccount) -> any UsageProvider)? = nil,
        continuityCache: (any UsageContinuityCaching)? = nil,
        defaultLoginRecords: (any DefaultLoginRecordStoring)? = nil,
        signOutRecord: SignOutRecord? = nil,
        sessionReliabilityRecord: SessionReliabilityRecord? = nil,
        bankedResetAcknowledgements: BankedResetAcknowledgements? = nil,
        notificationCoordinator: NotificationCoordinator? = nil,
        warmUp: WarmUpAutomation? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        capturesAllAccounts: Bool = false,
        previewAccountLayout: AccountLayout? = nil
    ) {
        self.capturesAllAccounts = capturesAllAccounts
        self.providers = providers
        self.apiSpendProviders = apiSpendProviders
        let labelMode = preferences.defaults.string(forKey: "menuBarMeters.labels.v1")
            ?? preferences.defaults.string(forKey: "t3.menuBar.accountLabels")
        let showsLabels = preferences.defaults.object(forKey: "menuBarMeters.showLabels") as? Bool ?? (labelMode != "off")
        showMenuBarLabels = showsLabels
        preferences.defaults.set(showsLabels, forKey: "menuBarMeters.showLabels")
        self.preferences = preferences
        self.accountRegistry = accountRegistry
        self.accountStorage = accountStorage
        self.borrowedHomes = borrowedHomes
        self.providerFactory = providerFactory
        self.continuityCache = continuityCache
        self.defaultLoginRecordStore = defaultLoginRecords
        self.signOutRecord = signOutRecord
        self.sessionReliabilityRecord = sessionReliabilityRecord
        self.bankedResetAcknowledgements = bankedResetAcknowledgements
        self.notificationCoordinator = notificationCoordinator
        self.warmUp = warmUp ?? WarmUpAutomation()
        self.now = now
        var configuredProviders = providers
        if let accountRegistry, let providerFactory {
            let live = Set(providers.map(\.id))
            for id in accountRegistry.stoppedCLISources.subtracting(live).sorted(by: { $0.raw < $1.raw }) {
                configuredProviders.append(providerFactory(.builtIn(for: id)))
            }
        }
        self.composedAccountCapacities = Dictionary(
            configuredProviders.map { ($0.id, $0.accountCapacity) }, uniquingKeysWith: { first, _ in first }
        )
        self.tracksT3Claude = preferences.tracksT3Claude
        self.displayNames = Dictionary(configuredProviders.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        self.apiSpendDisplayNames = Dictionary(
            apiSpendProviders.map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        // Uniquing, never trapping: a duplicated persisted account entry must degrade
        // to one row, not a launch crash loop (code-review finding).
        let cachedSnapshots = continuityCache?.load() ?? [:]
        let restorationDate = now()
        self.snapshots = Dictionary(
            providers.map { provider in
                let snapshot = Self.restoredSnapshot(
                    cachedSnapshots[provider.accountKey],
                    for: provider.id,
                    after: restorationDate
                )
                return (provider.accountKey, snapshot)
            },
            uniquingKeysWith: { first, _ in first }
        )
        self.providerCapabilities = Dictionary(
            providers.filter(\.reportsProviderCapability).map {
                ($0.id, ProviderCapabilityStatus(state: .unknown, observedAt: restorationDate))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let accountIndex = Self.accountsIndex(providers: providers, accounts: accounts, registry: accountRegistry)
        self.accountsByProvider = accountIndex
        self.apiSpendSnapshots = Dictionary(uniqueKeysWithValues: apiSpendProviders.map {
            ($0.id, .pending(providerID: $0.id, displayName: $0.displayName, periodLabel: preferences.apiSpendPeriod.label))
        })
        self.antigravitySourcePreference = preferences.antigravitySourcePreference
        self.tracksCLIDefaultAlongsideT3 = accountRegistry?.tracksCLIDefaultAlongsideT3 ?? false
        var badges = preferences.menuBarAccountBadges
        for row in accountIndex[.codex] ?? [] where row.borrowedHome != nil {
            badges[row.key] = accountRegistry?.borrowedMenuBarBadge(for: row.id)
        }
        self.menuBarBadgeOverrides = badges
        self.usagePercentageMode = preferences.usagePercentageMode
        self.accountLayout = previewAccountLayout ?? preferences.effectiveAccountLayout
        self.popoverExpandedAccounts = preferences.popoverExpandedAccounts
        self.popoverSummarySlot1 = preferences.popoverSummarySlot1
        self.popoverSummarySlot2 = preferences.popoverSummarySlot2 == preferences.popoverSummarySlot1 ? .off : preferences.popoverSummarySlot2
        self.expandAccountsHorizontally = preferences.expandAccountsHorizontally
        self.useEmailAsAccountName = preferences.useEmailAsAccountName
        self.meterStyle = preferences.meterStyle
        self.composedProviderOrder = configuredProviders.map(\.id).uniqued()
        self.showsAntigravityOtherModels = preferences.showsAntigravityOtherModels
        self.useItUpRemindersEnabled = preferences.useItUpRemindersEnabled
        self.bankedResetNotificationsEnabled = preferences.bankedResetNotificationsEnabled
        self.reminderRules = preferences.reminderRules
        self.reminderScope = preferences.reminderScope
        self.enabledSurfaces = Set(UsageSurface.allCases.filter { preferences.isSurfaceEnabled($0) })
        scheduler.host = self
        for provider in providers { scheduler.register(provider) }
        prepareDefaultLogin(cached: cachedSnapshots)
        if !popoverExpandedAccounts.isEmpty {
            var tracked = Set(accountsByProvider.values.flatMap { $0.map(\.key) })
            if let accountRegistry {
                for id in composedProviderOrder {
                    tracked.formUnion(accountRegistry.accounts(for: id, capacity: .max).map(\.key))
                    // T3 discovery can suppress the CLI row without removing it from tracking.
                    if !accountRegistry.isBuiltInHidden(for: id) {
                        tracked.insert(AccountKey(providerID: id, accountID: .primary))
                    }
                }
            }
            let remembered = (defaultLoginState?.remembered ?? []).filter { !$0.isHidden }.map(\.key)
            tracked.formUnion(remembered)
            setPopoverExpandedAccounts(popoverExpandedAccounts.intersection(tracked))
        }
        for id in registeredProviderOrder { refreshDisplayMerge(for: id) }
        let migratedSelection = preferences.migrateLegacyMenuBarSelection(
            projections: menuBarProjections, tracked: menuBarTrackedAccounts, enabled: Set(providerOrder))
        var selection = migratedSelection
        if selection.explicitLabels != true {
            let known = accountIndex.values.flatMap { $0 } + menuBarProjections.flatMap { $0.rows.map(\.account) }
            let names = Dictionary(grouping: known, by: \.key)
            func migrated(_ item: MenuBarMeterSelection.Item) -> MenuBarMeterSelection.Item {
                guard let label = item.label, names[item.account]?.contains(where: {
                    [desktopAccountName(for: $0), $0.label].map(MenuBarMeterSelection.Item.trimmedLabel).contains(label)
                }) == true else { return item }
                var cleared = item
                cleared.label = ""
                return cleared
            }
            selection.items = selection.items.map(migrated)
            selection.hidden = selection.hidden.map(migrated)
            selection.explicitLabels = true
        }
        selection.appendNewAccounts(menuBarTrackedAccounts.filter { providerOrder.contains($0.providerID) })
        menuBarMeterSelection = selection
        if selection != migratedSelection { preferences.menuBarMeterSelection = selection }
        didLoadMenuBarSelection = true
    }

    static func restoredSnapshot(
        _ cached: UsageSnapshot?,
        for providerID: ProviderID,
        after restorationDate: Date
    ) -> UsageSnapshot {
        UsageContinuityPolicy.restoredSnapshot(
            cached,
            for: providerID,
            at: restorationDate
        )
    }

    /// Account metadata for every provider instance. Explicit `accounts` (render
    /// harness/tests) wins, then the registry, then a synthesized built-in per provider
    /// so plain single-account construction keeps working with no extra wiring.
    private static func accountsIndex(
        providers: [any UsageProvider],
        accounts: [ProviderAccount]?,
        registry: AccountRegistry?
    ) -> [ProviderID: [ProviderAccount]] {
        var index: [ProviderID: [ProviderAccount]] = [:]
        for id in providers.map(\.id).uniqued() {
            let known: [ProviderAccount]
            if let accounts {
                known = accounts.filter { $0.providerID == id }
            } else if let registry {
                known = registry.accounts(for: id)
            } else {
                known = []
            }
            let instanceIDs = providers
                .filter { $0.id == id }
                .map(\.accountID)
                .uniqued()
            let instanceIDSet = Set(instanceIDs)
            let orderedKnown = known.filter { instanceIDSet.contains($0.id) }
            let knownIDs = Set(orderedKnown.map(\.id))
            let orderedIDs = orderedKnown.map(\.id) + instanceIDs.filter { !knownIDs.contains($0) }
            index[id] = orderedIDs.map { accountID in
                known.first(where: { $0.id == accountID })
                    ?? ProviderAccount(id: accountID, providerID: id, label: "Main", isBuiltIn: accountID == .primary)
            }
        }
        return index
    }

    public var providerOrder: [ProviderID] {
        registeredProviderOrder.filter { id in
            guard let surface = UsageSurface.subscription(for: id) else { return false }
            return enabledSurfaces.contains(surface)
        }
    }

    /// Every composed subscription provider, including surfaces currently switched off.
    /// Settings/account management use this registry order; display surfaces use
    /// `providerOrder`, which additionally applies the user's surface toggles.
    public var registeredProviderOrder: [ProviderID] {
        let live = providers.map(\.id).uniqued()
        let liveSet = Set(live)
        return composedProviderOrder.filter(liveSet.contains)
            + live.filter { !composedProviderOrder.contains($0) }
    }

    public var apiSpendProviderOrder: [ProviderID] {
        registeredAPISpendProviderOrder.filter { id in
            guard let surface = UsageSurface.api(for: id) else { return false }
            guard enabledSurfaces.contains(surface) else { return false }
            // A live nil amount is an explicit "not applicable" result (currently
            // Cursor with on-demand disabled), so no empty spend row is rendered.
            if let snapshot = apiSpendSnapshots[id],
               snapshot.freshness == .live, snapshot.amount == nil {
                return false
            }
            return true
        }
    }

    public var registeredAPISpendProviderOrder: [ProviderID] {
        apiSpendProviders.map(\.id).uniqued()
    }

    /// Begin polling: an immediate refresh, then the interval loop. Idempotent — a
    /// second call (e.g. the popover re-appearing) does not restart the loop or
    /// reset the cadence.
    public func start() async {
        guard engine == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        await refreshAll()
        // KTD6: the loop sleeps until the earliest due account in an idle lane (each
        // account phased toward its own reset, R2M3 carried per account) and a tick only
        // dispatches; the lanes drain in their own tasks and re-arm the sleep at pass end.
        let engine = PollingEngine(
            nextWake: { [weak self] in
                self?.scheduler.wakeDelay()
                    ?? LaneSchedule.chosenInterval(minutes: Preferences.defaultIntervalMinutes)
            },
            now: now,
            tick: { [weak self] in
                self?.engineDidWake()
                self?.evaluateWarmUp()
                self?.scheduler.dispatchDue()
            }
        )
        engine.start()
        self.engine = engine
    }

    /// Immediate off-cadence refresh — the Refresh button and other explicit user actions
    /// (KTD9). Popover open deliberately does *not* land here: it goes through
    /// `refreshOnPopoverOpen()`, which gates on capture age (R2M2).
    public func refreshNow(origin: UserRefreshOrigin = .fullRefresh) {
        Task { await refreshAll(origin: origin) }
    }

    /// R2M2: freshen on popover open, but only when the timer was about to fire anyway.
    /// The popover is the app's highest-frequency moment and a Claude poll is a full CLI
    /// session, so this wakes the queue only once the oldest live capture has already aged
    /// past a full poll interval; the lane's pass-end rephase then puts the next tick a full
    /// interval after the fresh data. At most one extra poll per interval; the cadence
    /// itself is never raised (AGENTS.md's cost warning).
    public func refreshOnPopoverOpen() {
        // KTD10: a remembered row shows its age as of this open, before any guard below.
        ageRememberedSnapshots()
        // Read before the re-checks: they are user-origin requests that raise `isRefreshing`
        // themselves, and must never cost the other accounts this open's wake.
        let userRefreshInFlight = isRefreshing
        runPopoverOpenRechecks()
        // A user refresh already in flight is freshening the data by itself.
        guard !userRefreshInFlight else { return }
        guard Self.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: oldestLiveCapture,
            now: now(),
            intervalMinutes: preferences.pollIntervalMinutes
        ) else { return }
        // KTD6: wake the queue for whatever is due instead of forcing every account; the
        // lane's pass-end rephase moves the next tick a full interval past the fresh data.
        scheduler.dispatchDue()
    }

    /// KTD7 (OpenCode plan): after **See Go Plans**, arm one re-check of that account for the
    /// next popover open. Arming again before that open is still one re-check.
    public func armRecheckOnNextPopoverOpen(_ key: AccountKey) {
        popoverOpenRechecks.insert(key)
    }

    /// Spends every armed re-check, whatever happens to it: one open, one probe per account.
    /// It is a front-of-queue request like Check Now, so the duty-cycle gate does not hold it
    /// and the account's own row shows the work. An account that has since left the no-plan
    /// state, been removed or switched off has nothing to re-check.
    private func runPopoverOpenRechecks() {
        guard !popoverOpenRechecks.isEmpty else { return }
        let armed = popoverOpenRechecks
        popoverOpenRechecks.removeAll()
        for key in armed.sorted(by: { $0.description < $1.description })
        where snapshots[key]?.planStatus != nil && schedulerIsEligible(key) {
            refreshAccountNow(key)
        }
    }

    /// Oldest capture time among snapshots that are actually live. Permanently stale rows
    /// are excluded on purpose: their retained `capturedAt` only gets older, so counting
    /// them would make every popover open trigger a refresh forever.
    var oldestLiveCapture: Date? {
        snapshots.values
            .filter { $0.freshness == .live }
            .compactMap(\.capturedAt)
            .min()
    }

    nonisolated static func shouldRefreshOnPopoverOpen(
        oldestLiveCapture: Date?,
        now: Date,
        intervalMinutes: Int
    ) -> Bool {
        // Nothing live means nothing to freshen — a never-signed-in or failing account has
        // its own recovery affordance in the card, and probing it on every open would burn a
        // CLI session per open.
        guard let oldestLiveCapture else { return false }
        let interval = Double(PollingEngine.clampedIntervalMinutes(intervalMinutes)) * 60
        return now.timeIntervalSince(oldestLiveCapture) >= interval
    }

    /// Refresh only API spend providers. Settings uses this for spend-only controls so
    /// a checkbox click doesn't spawn the expensive Claude subscription CLI probe.
    public func refreshAPISpendNow() {
        Task { await refreshAPISpendOnly() }
    }

    /// Restart the loop so a changed poll interval takes effect now (R14).
    public func reschedulePolling() {
        refreshPollCadences()
        engine?.reschedule()
    }

    public func setUsagePercentageMode(_ mode: UsagePercentageMode) {
        // Settings loads its binding from the store, which echoes back through `onChange`.
        guard usagePercentageMode != mode else { return }
        preferences.usagePercentageMode = mode
        usagePercentageMode = mode
    }

    public func togglePopoverAccountExpansion(_ key: AccountKey) {
        setPopoverExpandedAccounts(popoverExpandedAccounts.symmetricDifference([key]))
    }

    func removePopoverAccountExpansion(_ key: AccountKey) {
        setPopoverExpandedAccounts(popoverExpandedAccounts.subtracting([key]))
    }

    private func setPopoverExpandedAccounts(_ keys: Set<AccountKey>) {
        guard keys != popoverExpandedAccounts else { return }
        preferences.popoverExpandedAccounts = keys
        popoverExpandedAccounts = keys
    }

    public func setUseEmailAsAccountName(_ enabled: Bool) {
        guard useEmailAsAccountName != enabled else { return }
        preferences.useEmailAsAccountName = enabled
        useEmailAsAccountName = enabled
    }

    public func setExpandAccountsHorizontally(_ enabled: Bool) {
        guard expandAccountsHorizontally != enabled else { return }
        preferences.expandAccountsHorizontally = enabled
        expandAccountsHorizontally = enabled
    }

    public func desktopAccountName(for account: ProviderAccount) -> String {
        DesktopAccountIdentity(
            // `snapshot(for:)`, so a remembered row names itself by its last reading's email.
            title: account.label, email: snapshot(for: account.key).accountEmail,
            showsPersistentEmail: false, usesEmailAsName: useEmailAsAccountName
        ).title
    }

    public func setMeterStyle(_ style: MeterStyle) {
        guard meterStyle != style else { return }
        preferences.meterStyle = style
        meterStyle = style
    }


    public func setShowsAntigravityOtherModels(_ enabled: Bool) {
        guard showsAntigravityOtherModels != enabled else { return }
        preferences.showsAntigravityOtherModels = enabled
        showsAntigravityOtherModels = enabled
    }

    public func setUseItUpRemindersEnabled(_ enabled: Bool) {
        guard useItUpRemindersEnabled != enabled else { return }
        preferences.useItUpRemindersEnabled = enabled
        useItUpRemindersEnabled = enabled
    }

    public func setBankedResetNotificationsEnabled(_ enabled: Bool) {
        guard bankedResetNotificationsEnabled != enabled else { return }
        preferences.bankedResetNotificationsEnabled = enabled
        bankedResetNotificationsEnabled = enabled
    }

    /// Persists the list in the given order, clamped. R6: sorting belongs to a committed
    /// edit (`commitReminderRule`), never to typing.
    public func setReminderRules(_ rules: [ReminderRule]) {
        let clamped = rules.map { $0.clamped() }
        guard reminderRules != clamped else { return }
        preferences.reminderRules = clamped
        reminderRules = clamped
    }

    /// R4/R6: a committed row edit clamps, replaces the row with the same ID, and resorts.
    /// An ID no longer in the list (removed mid-edit) changes nothing.
    public func commitReminderRule(_ rule: ReminderRule) {
        guard let index = reminderRules.firstIndex(where: { $0.id == rule.id }) else { return }
        var rules = reminderRules
        rules[index] = rule.clamped()
        setReminderRules(ReminderRules.sorted(rules))
    }

    /// R5: appends a rule seeded from the shortest one and returns it.
    @discardableResult
    public func addReminderRule() -> ReminderRule {
        let seeded = ReminderRules.seed(from: reminderRules)
        setReminderRules(reminderRules + [seeded])
        return seeded
    }

    public func removeReminderRule(id: ReminderRule.ID) {
        setReminderRules(reminderRules.filter { $0.id != id })
    }

    public func setReminderScope(_ scope: Set<ReminderScope>) {
        guard reminderScope != scope else { return }
        preferences.reminderScope = scope
        reminderScope = scope
    }

    /// R8: whether "Reset to defaults" should show.
    public var reminderSettingsAreDefault: Bool {
        ReminderRules.isDefault(rules: reminderRules, scope: reminderScope)
    }

    /// R8: restores both the rules and the Applies-to choices.
    public func resetReminderSettingsToDefaults() {
        setReminderRules(ReminderRules.defaults)
        setReminderScope(ReminderScope.defaults)
    }

    /// W4: how the footer receipt names an account — the provider alone while it has one
    /// account (labels are hidden then), "Claude Work" once it has several.
    public func refreshReceiptTitle(for key: AccountKey) -> String {
        // KTD8: titled the way the popover titles its rows, remembered rows included.
        let accounts = displayAccounts(for: key.providerID).map(\.account)
        // U10: a merged built-in's probe lands under the row that shows it.
        let shown = displayMergeMaps[key.providerID]?[key] ?? key
        return RefreshReceiptPresentation.title(
            providerName: displayNames[key.providerID] ?? key.providerID.raw,
            accountTitle: accounts.first(where: { $0.key == shown }).map { desktopAccountName(for: $0) },
            providerAccountCount: accounts.count)
    }


    public func isSurfaceEnabled(_ surface: UsageSurface) -> Bool {
        enabledSurfaces.contains(surface)
    }

    public func setSurfaceEnabled(_ enabled: Bool, for surface: UsageSurface) {
        preferences.setSurfaceEnabled(enabled, for: surface)
        if enabled {
            enabledSurfaces.insert(surface)
            let newlyVisible = menuBarTrackedAccounts.filter { UsageSurface.subscription(for: $0.providerID) == surface }
            menuBarMeterSelection.appendNewAccounts(newlyVisible)
            // KTD11: a re-enabled provider's accounts are due now once, with no attempt
            // history, so the toggle can neither burst-stretch the lane nor read as overdue.
            let keys = providers.map(\.accountKey).filter { UsageSurface.subscription(for: $0.providerID) == surface }
            scheduler.markDueNow(keys)
        } else {
            enabledSurfaces.remove(surface)
            // KTD11: queued user requests for these accounts can no longer be served.
            let keys = providers.map(\.accountKey).filter { UsageSurface.subscription(for: $0.providerID) == surface }
            scheduler.withdraw(keys)
        }
    }

    public var apiSpendPeriod: APISpendPeriod {
        preferences.apiSpendPeriod
    }

    public func setAPISpendPeriod(_ period: APISpendPeriod) {
        preferences.apiSpendPeriod = period
    }

    public func refreshAll(origin: UserRefreshOrigin = .fullRefresh) async {
        guard origin == .fullRefresh else {
            await performRefreshAll(origin: origin)
            return
        }
        if let fullRefreshTask {
            await fullRefreshTask.value
            return
        }
        fullRefreshStartedAt = now()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performRefreshAll(origin: .fullRefresh)
            // Cleared inside the task, so every waiter resumes to a settled store.
            self.fullRefreshTask = nil
            self.fullRefreshStartedAt = nil
            self.lastFullRefreshCompletedAt = self.now()
        }
        fullRefreshTask = task
        await task.value
    }

    private func performRefreshAll(origin: UserRefreshOrigin) async {
        if borrowedHomes != nil { rescanBorrowedHomes() }
        if origin != .setupCheck { visibleRefreshOperationDepth += 1 }
        defer {
            if origin != .setupCheck {
                visibleRefreshOperationDepth -= 1
                recomputeVisibleRefreshWork()
            }
        }
        if origin == .fullRefresh {
            fullRefreshOperationDepth += 1
            fullRefreshInFlight = true
        }
        // Raised before the subscription work so the flag does not blink off between the
        // last merge and the spend fetch.
        apiSpendUserRefreshDepth += 1
        recomputeRefreshing()
        scheduler.markAllDue(origin: origin)
        scheduler.dispatchDue()
        await scheduler.waitUntilUserWorkDrains()
        await scheduler.waitUntilLanesIdle()
        await refreshAPISpend()
        if origin == .fullRefresh {
            fullRefreshOperationDepth -= 1
            fullRefreshInFlight = fullRefreshOperationDepth > 0
        }
        apiSpendUserRefreshDepth -= 1
        recomputeRefreshing()
        refreshPollCadences()
    }

    /// Refresh a single account — Check Now, Check Again, Try Again, Make Main, and the
    /// setup coordinator's checks (R4, KTD7). A front-of-queue request, so watching one
    /// sign-in never fans out into a full fleet poll.
    public func refreshAccountNow(_ key: AccountKey, origin: UserRefreshOrigin = .accountAction) {
        scheduler.requestPriority(key, origin: origin)
    }

    func refreshAccount(_ key: AccountKey, origin: UserRefreshOrigin = .accountAction) async {
        scheduler.requestPriority(key, origin: origin)
        await scheduler.waitForCompletion(of: key)
    }

    /// R18: provider capability recovery re-checks every attached account, bypassing
    /// capability-failure backoff without waking any other provider.
    public func refreshProviderNow(_ providerID: ProviderID) {
        for account in accounts(for: providerID) { refreshAccountNow(account.key) }
    }

    /// Timer tick, popover open, or a Settings surface change: probe whatever is due, one
    /// per CLI lane, without marking anything due that is not (KTD6, KTD11).
    public func dispatchDueNow() {
        scheduler.dispatchDue()
    }

    public func dispatchDueNow(for providerID: ProviderID) {
        scheduler.dispatchDue(for: providerID)
    }

    /// KTD12: what Settings shows for a provider — the chosen interval, the interval its
    /// accounts actually experience, and how many accounts share the lane.
    public func pollCadence(for providerID: ProviderID) -> PollCadence {
        let chosen = schedulerChosenInterval
        return PollCadence(
            chosenInterval: chosen,
            effectiveInterval: scheduler.effectiveInterval(forProvider: providerID, chosen: chosen),
            accountCount: scheduler.accountCount(for: providerID)
        )
    }

    /// KTD2: spend controls keep working while a CLI lane drains; only a spend fetch
    /// already in flight coalesces the click.
    public func refreshAPISpendOnly() async {
        if apiSpendInFlight { return }
        apiSpendInFlight = true
        visibleRefreshOperationDepth += 1
        apiSpendUserRefreshDepth += 1
        recomputeRefreshing()
        defer {
            apiSpendInFlight = false
            visibleRefreshOperationDepth -= 1
            apiSpendUserRefreshDepth -= 1
            recomputeRefreshing()
        }
        await refreshAPISpend()
    }

    func refreshPollCadences() {
        var next: [ProviderID: PollCadence] = [:]
        for providerID in registeredProviderOrder {
            next[providerID] = pollCadence(for: providerID)
        }
        if pollCadences != next { pollCadences = next }
    }

    private func recomputeRefreshing() {
        recomputeVisibleRefreshWork()
        let next = userWorkPending || apiSpendUserRefreshDepth > 0
        guard isRefreshing != next else { return }
        isRefreshing = next
        refreshingClearedAt = next ? nil : now()
        if !next, userRefreshRun != nil {
            let clearedAt = refreshingClearedAt!
            userRefreshRun?.refreshingClearedAt = clearedAt
            let runID = userRefreshRun?.id
            refreshRunRetentionTask?.cancel()
            refreshRunRetentionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.refreshRunRetentionDuration))
                guard !Task.isCancelled, let self, self.userRefreshRun?.id == runID else { return }
                self.clearExpiredUserRefreshRun(at: self.now())
            }
        }
    }

    private func recomputeVisibleRefreshWork() {
        let pending = userRefreshRun?.entries.values.contains {
            $0.origin != .setupCheck && $0.outcome == nil
        } ?? false
        let next = pending || visibleRefreshOperationDepth > 0
        guard visibleRefreshWork.isInFlight != next else { return }
        visibleRefreshWork = VisibleRefreshWork(isInFlight: next, clearedAt: next ? nil : now())
    }

    /// A clock seam for testing the 0.5s hold plus 0.2s retention without a real wait.
    func clearExpiredUserRefreshRun(at date: Date) {
        guard !isRefreshing, let clearedAt = userRefreshRun?.refreshingClearedAt,
              date.timeIntervalSince(clearedAt) >= Self.refreshRunRetentionDuration else { return }
        userRefreshRun = nil
    }

    private func refreshAPISpend() async {
        let spendPeriod = preferences.apiSpendPeriod
        let spendResults = await withTaskGroup(of: (ProviderID, APISpendSnapshot).self) { group in
            for provider in apiSpendProviders {
                guard let surface = UsageSurface.api(for: provider.id),
                      enabledSurfaces.contains(surface)
                else { continue }
                spendFetchDepths[provider.id, default: 0] += 1
                apiSpendInFlightProviders.insert(provider.id)
                group.addTask { (provider.id, await provider.fetchSpend(period: spendPeriod)) }
            }
            var acc: [(ProviderID, APISpendSnapshot)] = []
            for await pair in group {
                spendFetchDepths[pair.0, default: 1] -= 1
                if spendFetchDepths[pair.0] == 0 {
                    spendFetchDepths.removeValue(forKey: pair.0)
                    apiSpendInFlightProviders.remove(pair.0)
                }
                acc.append(pair)
            }
            return acc
        }
        for (id, fresh) in spendResults { mergeSpend(id: id, fresh: fresh) }
    }

    /// Continuity (KTD7): a failure with no fresh windows keeps the prior windows
    /// shown dimmed rather than blanking the card; it never touches another account.
    private func mergeResult(
        key: AccountKey,
        result: UsageProviderFetchResult,
        notifiesSetup: Bool,
        attachmentGeneration: UInt64?
    ) -> Bool {
        // KTD2 (default-login plan): a reading taken while the login was changing belongs
        // to neither account for certain. Refused here, before `merge`, so it never
        // reaches the snapshot, the continuity cache or a setup session.
        if result.discard != nil { return false }
        if let version = result.cliVersion, observedCLIVersions[key] != version,
           acceptsResult(for: key, attachmentGeneration: attachmentGeneration) {
            observedCLIVersions[key] = version
        }
        if isReplayingDemoCapture {
            guard acceptsResult(for: key, attachmentGeneration: attachmentGeneration) else { return false }
            if snapshots[key] != result.snapshot { snapshots[key] = result.snapshot }
            refreshDisplayMerge(for: key.providerID)
            if notifiesSetup { setupCoordinator?.receive(result.snapshot, for: key) }
            return true
        }
        let isCapabilityFailure = result.capability.map { $0 != .available } == true
        if isCapabilityFailure {
            // A provider-wide discovery failure says nothing about this account. Keep a
            // pending row neutral and preserve any prior usage or login/trust setup state.
            return acceptsResult(for: key, attachmentGeneration: attachmentGeneration)
        }
        return merge(key: key, fresh: result.snapshot, notifiesSetup: notifiesSetup,
                     attachmentGeneration: attachmentGeneration)
    }

    private func acceptsResult(for key: AccountKey, attachmentGeneration: UInt64?) -> Bool {
        accounts(for: key.providerID).contains(where: { $0.key == key })
            && !removingAccounts.contains(key)
            && attachmentGeneration == attachmentGenerations[key, default: 0]
    }

    @discardableResult
    private func merge(
        key: AccountKey,
        fresh: UsageSnapshot,
        notifiesSetup: Bool = true,
        attachmentGeneration: UInt64?
    ) -> Bool {
        // The account may have been removed — or its built-in row stop-tracked and
        // resumed, reusing the key — while its fetch was in flight. A late result from
        // a detached instance must not resurrect or overwrite the row.
        guard acceptsResult(for: key, attachmentGeneration: attachmentGeneration) else { return false }
        let prior = defaultLoginPrior(for: key, fresh: fresh)
        sessionReliabilityRecord?.note(
            fresh, for: key, expectedInterval: schedulerChosenInterval,
            trackedAccounts: providers.map(\.accountKey)
        )
        let next = UsageContinuityPolicy.mergedSnapshot(
            fresh,
            with: prior,
            at: now()
        )
        recordSignOutEdge(next, for: key)
        // Skip the assignment when nothing changed so an unchanging state (e.g. a
        // provider that stays logged-out) doesn't invalidate observers every cycle.
        if snapshots[key] != next { snapshots[key] = next }
        refreshDisplayMerge(for: key.providerID)
        // KTD11: a merged built-in's reading is E's account, so E alone reminds and
        // acknowledges banked resets; the pair fires one reminder, not two.
        if next.freshness == .live, !isMergedAway(key) {
            bankedResetAcknowledgements?.lower(for: key, currentCount: next.bankedResets)
            evaluateNotifications(next, for: key)
        }
        updateContinuityCache(next, for: key)
        if notifiesSetup { setupCoordinator?.receive(next, for: key) }
        if next.freshness == .live { evaluateWarmUp() }
        return true
    }

    /// KTD2: only a fresh live merge reaches here, so a launch restore, a failed poll's
    /// retained windows, and a capability failure never notify. The completion re-checks
    /// this attachment, so a post that races a removal or reset writes no ledger (KTD6).
    private func evaluateNotifications(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard let notificationCoordinator else { return }
        // KTD8: the label appears once the provider shows several rows, remembered included.
        let visible = displayAccounts(for: key.providerID).map(\.account)
        let context = NotificationEvaluationContext(
            providerName: key.providerID.displayName,
            accountLabel: visible.count > 1 ? visible.first { $0.key == key }?.label : nil,
            useItUp: UseItUpSettings(
                isEnabled: useItUpRemindersEnabled,
                rules: reminderRules,
                scope: reminderScope,
                showCodexSparkCounters: false
            ),
            bankedResetsEnabled: bankedResetNotificationsEnabled
        )
        let generation = attachmentGenerations[key, default: 0]
        notificationCoordinator.receive(visibleAntigravitySnapshot(snapshot), for: key, context: context, now: now()) { [weak self] in
            self?.acceptsResult(for: key, attachmentGeneration: generation) ?? false
        }
    }

    /// KTD14 (2026-09-19 sign-in plan): merge is the one place the prior row and the
    /// merged one are both settled and capability failures have already short-circuited,
    /// so it is where the signed-in → signed-out edge is observed. A transient capture or
    /// an unrecognized surface says nothing about the login, so both leave the flag and
    /// the list alone — only a live reading re-arms the account.
    private func recordSignOutEdge(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard let signOutRecord, key.providerID == .claude else { return }
        switch snapshot.freshness {
        case .live:
            signOutRecord.noteSignedIn(key)
        case .stale(.providerSetup(.claudeLoginRequired)):
            signOutRecord.noteSignedOut(key)
        default:
            break
        }
    }

    private func updateContinuityCache(_ snapshot: UsageSnapshot, for key: AccountKey) {
        let saves: Bool
        if case .stale(let reason) = snapshot.freshness, reason.isPermanent {
            saves = false
        } else {
            saves = !snapshot.windows.isEmpty
        }
        if saves {
            continuityCache?.save(snapshot, for: key)
        } else {
            continuityCache?.remove(for: key)
        }
        defaultLoginDidUpdateContinuity(for: key, removed: !saves)
    }

    private func beginCapabilityRefresh(
        for providers: [any UsageProvider]
    ) -> [ProviderID: UInt64] {
        var cycle: [ProviderID: UInt64] = [:]
        for providerID in providers.filter(\.reportsProviderCapability).map(\.id).uniqued() {
            capabilityGenerations[providerID, default: 0] &+= 1
            let generation = capabilityGenerations[providerID] ?? 0
            cycle[providerID] = generation
            // Keep the last actionable verdict visible during later polls. Only the
            // first discovery has no prior result to preserve.
            if providerCapabilities[providerID]?.state == .unknown
                || providerCapabilities[providerID] == nil {
                providerCapabilities[providerID] = ProviderCapabilityStatus(
                    state: .discovering,
                    observedAt: now()
                )
            }
        }
        return cycle
    }

    private func applyCapability(
        _ state: ProviderCapabilityState,
        for providerID: ProviderID,
        generation: UInt64?
    ) {
        guard let generation, capabilityGenerations[providerID] == generation else { return }
        providerCapabilities[providerID] = ProviderCapabilityStatus(state: state, observedAt: now())
        switch state {
        case .inconclusive, .confirmedAbsent:
            setupCoordinator?.receiveCapabilityFailure(state, for: providerID)
        case .unknown, .discovering, .available:
            break
        }
    }

    func seedCapturedDemo(
        results: [AccountKey: UsageProviderFetchResult], spend: [APISpendSnapshot], at date: Date
    ) {
        isReplayingDemoCapture = true
        for (key, result) in results {
            snapshots[key] = result.snapshot
            observedCLIVersions[key] = result.cliVersion
            if let capability = result.capability {
                providerCapabilities[key.providerID] = ProviderCapabilityStatus(state: capability, observedAt: date)
            }
        }
        for snapshot in spend { apiSpendSnapshots[snapshot.providerID] = snapshot }
        for provider in registeredProviderOrder { refreshDisplayMerge(for: provider) }
    }

    private func mergeSpend(id: ProviderID, fresh: APISpendSnapshot) {
        let next: APISpendSnapshot
        if case .stale(let reason) = fresh.freshness,
           fresh.amount == nil,
           let prior = apiSpendSnapshots[id], prior.amount != nil {
            next = prior.markedStale(reason)
        } else {
            next = fresh
        }
        if apiSpendSnapshots[id] != next { apiSpendSnapshots[id] = next }
    }

    /// Claims a first-show reveal for a current, live account. A missing record,
    /// a stale or pending row, and an account mid-removal all return false and
    /// write nothing (KTD6, KTD7).
    public func claimBankedResetReveal(for key: AccountKey, currentCount: Int?) -> Bool {
        guard acceptsResult(for: key, attachmentGeneration: attachmentGenerations[key, default: 0]) else {
            return false
        }
        guard snapshot(for: key).freshness == .live, !isMergedAway(key) else { return false }
        return bankedResetAcknowledgements?.claimReveal(for: key, currentCount: currentCount) ?? false
    }

    /// An engine row's snapshot, or a visible remembered row's aged last reading (U7).
    public func snapshot(for key: AccountKey) -> UsageSnapshot {
        snapshots[key] ?? rememberedDisplaySnapshots[key] ?? .pending(for: key.providerID)
    }

    /// Primary-account snapshot — the single-account view compact surfaces use.
    public func snapshot(for id: ProviderID) -> UsageSnapshot {
        snapshot(for: primaryKey(for: id))
    }

    public func appDisplaySnapshot(for key: AccountKey) -> UsageSnapshot {
        let snapshot = visibleAntigravitySnapshot(snapshot(for: key))
        let visible = snapshot.providerID == .codex
            ? snapshot.replacingWindows(snapshot.windows.filter { !$0.kind.isCodexSparkCounter })
            : snapshot
        return fiveHourFirst(visible)
    }

    func visibleAntigravitySnapshot(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        AntigravityOtherModels.visibleSnapshot(snapshot, showsOtherModels: showsAntigravityOtherModels)
    }

    public func appDisplaySnapshot(for id: ProviderID) -> UsageSnapshot {
        appDisplaySnapshot(for: primaryKey(for: id))
    }

    private func primaryKey(for id: ProviderID) -> AccountKey {
        displayPrimaryKey(for: id) ?? AccountKey(providerID: id, accountID: .primary)
    }

    /// Popover display order: 5-hour leads, weekly second, model rows keep their
    /// provider-given order after. The rule
    /// lives on `UsageSnapshot.fiveHourFirst()` so the Settings specimen renders the same order.
    private func fiveHourFirst(_ snapshot: UsageSnapshot) -> UsageSnapshot {
        snapshot.fiveHourFirst()
    }

    public func apiSpendSnapshot(for id: ProviderID) -> APISpendSnapshot {
        apiSpendSnapshots[id] ?? .pending(
            providerID: id,
            displayName: apiSpendDisplayNames[id] ?? id.raw,
            periodLabel: preferences.apiSpendPeriod.label
        )
    }


    public func setAntigravitySourcePreference(_ preference: AntigravitySourcePreference) {
        guard preference != antigravitySourcePreference else { return }
        observedCLIVersions[AccountKey(providerID: .antigravity, accountID: .primary)] = nil
        preferences.antigravitySourcePreference = preference
        antigravitySourcePreference = preference
        guard let key = displayPrimaryKey(for: .antigravity) else { return }
        invalidateUsageForAccountReset(key)
        // Selecting a source does not clear that home's sticky sign-out.
        scheduler.requestPriority(key, origin: .sourceSelection)
        scheduler.dispatchDue(for: .antigravity)
    }


}

extension Array where Element: Hashable {
    /// Order-preserving de-dupe for provider and account identity lists.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Scheduler host (KTD1)

extension UsageStore: AccountProbeSchedulerHost {
    var schedulerNow: Date { now() }

    var schedulerChosenInterval: TimeInterval {
        LaneSchedule.chosenInterval(minutes: preferences.pollIntervalMinutes)
    }

    func schedulerProvider(for key: AccountKey) -> (any UsageProvider)? {
        providers.first(where: { $0.accountKey == key })
    }

    func schedulerIsEligible(_ key: AccountKey) -> Bool {
        guard accounts(for: key.providerID).contains(where: { $0.key == key }),
              !removingAccounts.contains(key),
              let surface = UsageSurface.subscription(for: key.providerID)
        else { return false }
        return capturesAllAccounts || enabledSurfaces.contains(surface)
    }

    /// Engine side, following the merge map (KTD8): never a remembered row.
    func schedulerIsPrimary(_ key: AccountKey) -> Bool {
        displayProjection(for: key.providerID).isEnginePrimary(key)
    }

    func schedulerFreshness(for key: AccountKey) -> Freshness? {
        snapshots[key]?.freshness
    }

    /// R2M3 per account: the earliest live reset deadline on this account's own windows
    /// later than `reference` (its last attempt). `.unavailable` rows are excluded — their
    /// retained deadline is no longer evidence of anything on screen.
    func schedulerResetDeadline(for key: AccountKey, after reference: Date) -> Date? {
        snapshots[key]?.windows
            .filter { !$0.freshness.isUnavailable }
            .compactMap(\.resetSchedule.deadline)
            .filter { $0 > reference }
            .min()
    }

    func schedulerAttachmentGeneration(for key: AccountKey) -> UInt64 {
        attachmentGenerations[key] ?? 0
    }

    func schedulerBeginCapabilityRefresh(for providers: [any UsageProvider]) -> [ProviderID: UInt64] {
        beginCapabilityRefresh(for: providers)
    }

    func schedulerApplyCapability(_ state: ProviderCapabilityState, for providerID: ProviderID, generation: UInt64?) {
        applyCapability(state, for: providerID, generation: generation)
    }

    func schedulerMerge(key: AccountKey, result: UsageProviderFetchResult, attachmentGeneration: UInt64) -> Bool {
        let notifiesSetup = result.capability == nil || result.capability == .available
        let accepted = mergeResult(
            key: key, result: result, notifiesSetup: notifiesSetup, attachmentGeneration: attachmentGeneration
        )
        return accepted
    }

    func schedulerLaneDidGoIdle(_ lane: ProviderPollingLane) {
        refreshPollCadences()
        // KTD6: the next sleep is computed from the pass's new due times.
        engine?.rephase()
    }

    func schedulerStartsNewUserRun(origin: UserRefreshOrigin) -> Bool {
        guard let run = userRefreshRun else { return true }
        guard let clearedAt = run.refreshingClearedAt else { return false }
        return origin != .setupCheck || now().timeIntervalSince(clearedAt) >= Self.refreshRunRetentionDuration
    }

    func schedulerUserRunDidChange(_ run: UserRefreshRun) {
        refreshRunRetentionTask?.cancel()
        userRefreshRun = run
        recomputeVisibleRefreshWork()
    }

    func schedulerUserWorkDidChange(hasPending: Bool) {
        userWorkPending = hasPending
        if !hasPending { refreshProgress = nil }
        recomputeRefreshing()
    }

    func schedulerProbeDidStart(_ key: AccountKey) {
        if !probingAccounts.contains(key) { probingAccounts.insert(key) }
    }

    func schedulerProbeDidEnd(_ key: AccountKey) {
        lastProbeEndTimes[key] = now()
        if probingAccounts.contains(key) { probingAccounts.remove(key) }
    }

    func schedulerUserProgressDidChange(total: Int, completed: Int, landed: AccountKey?) {
        refreshProgress = RefreshProgress(
            total: total,
            completed: completed,
            lastLanded: landed ?? refreshProgress?.lastLanded
        )
    }
}
