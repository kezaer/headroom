import Foundation

/// UserDefaults-compatible storage for the existing Preferences and AccountRegistry
/// wrappers. Reads and writes stay in this launch, including Foundation's typed accessors.
public final class DemoMemoryDefaults: UserDefaults {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    public override func dictionaryRepresentation() -> [String: Any] { lock.withLock { values } }
    public override func persistentDomain(forName name: String) -> [String: Any]? { dictionaryRepresentation() }
    public override func setPersistentDomain(_ domain: [String: Any], forName name: String) { lock.withLock { values = domain } }
    public override func removePersistentDomain(forName name: String) { lock.withLock { values.removeAll() } }
    public override func dictionary(forKey key: String) -> [String: Any]? { object(forKey: key) as? [String: Any] }
    public override func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    public override func object(forKey key: String) -> Any? { lock.withLock { values[key] } }
    public override func set(_ value: Any?, forKey key: String) { lock.withLock { values[key] = value } }
    public override func removeObject(forKey key: String) { set(nil, forKey: key) }
    public override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    public override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    public override func stringArray(forKey key: String) -> [String]? { object(forKey: key) as? [String] }
    public override func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
    public override func integer(forKey key: String) -> Int { object(forKey: key) as? Int ?? 0 }
    public override func double(forKey key: String) -> Double { object(forKey: key) as? Double ?? 0 }
    public override func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
    public override func set(_ value: Int, forKey key: String) { set(value as Any, forKey: key) }
    public override func set(_ value: Double, forKey key: String) { set(value as Any, forKey: key) }
}

extension DemoCapture {
    private struct ReplayAccount {
        let fixture: Account
        let row: ProviderAccount

        init(fixture: Account, index: Int) {
            self.fixture = fixture
            switch (fixture.provider, fixture.source, fixture.isBuiltIn) {
            case (.codex, .t3Code, false), (.codex, .externalCLI, false):
                let ordinal = String(format: "%04d", index)
                let path = CanonicalHomePath(trustedCanonical: "/demo-capture/account-\(ordinal)")!
                let source: BorrowedHomeSource = fixture.source == .t3Code
                    ? .t3Instance(instanceID: ordinal, displayName: nil) : .manual
                row = ProviderAccount(borrowing: BorrowedHome(path: path, source: source),
                                      providerID: fixture.provider, label: fixture.label)
            default:
                row = ProviderAccount(id: fixture.isBuiltIn ? .primary : AccountID("captured-\(index)"),
                                      providerID: fixture.provider, label: fixture.label, isBuiltIn: fixture.isBuiltIn)
            }
        }
    }

    @MainActor
    public func makeReplayStore(
        defaults: DemoMemoryDefaults, accountStorage: DemoAccountStorage = DemoAccountStorage(),
        at date: Date = Date(), newAccountProvider: (@MainActor (ProviderAccount) -> any UsageProvider)? = nil
    ) -> UsageStore {
        let preferences = Preferences(defaults: defaults)
        settings.apply(to: preferences, rebasedTo: date)
        let registry = AccountRegistry(defaults: defaults)
        let fixtures = accounts.enumerated().map { ReplayAccount(fixture: $0.element, index: $0.offset) }
        let tracked = fixtures.filter { !$0.fixture.isRemembered }
        seedRegistry(registry, defaults: defaults, accounts: tracked)

        let acknowledged = BankedResetAcknowledgements(defaults: defaults)
        let results = Dictionary(tracked.map { entry in
            let provider = entry.row.providerID
            let isMerged = entry.fixture.mergesBuiltIn || (entry.row.isBuiltIn && tracked.contains {
                $0.row.providerID == provider && $0.fixture.mergesBuiltIn
            })
            let identity = isMerged ? AccountIdentity(
                providerID: provider, strength: .strong, digest: "captured-demo-\(provider.raw)",
                digestVersion: AccountIdentity.currentDigestVersion
            ) : nil
            if let count = entry.fixture.acknowledgedBankedResets {
                acknowledged.restore(count: count, for: entry.row.key)
            }
            return (entry.row.key, UsageProviderFetchResult(
                snapshot: entry.fixture.snapshot(rebasedTo: date, identity: identity),
                capability: capabilities.first { $0.provider == provider }?.state,
                cliVersion: entry.fixture.cliVersion
            ))
        }, uniquingKeysWith: { first, _ in first })
        let spend = self.spend.map { $0.snapshot(rebasedTo: date) }
        let factory: @MainActor (ProviderAccount) -> any UsageProvider = { account in
            if let reading = results[account.key] {
                return DemoUsageProvider(id: account.providerID, displayName: account.providerID.displayName,
                                         snapshot: reading.snapshot, accountID: account.id,
                                         capability: reading.capability, cliVersion: reading.cliVersion)
            }
            if let newAccountProvider { return newAccountProvider(account) }
            return DemoUsageProvider(id: account.providerID, displayName: account.providerID.displayName,
                                     snapshot: .pending(for: account.providerID), accountID: account.id)
        }
        let store = UsageStore(
            providers: tracked.map { factory($0.row) },
            apiSpendProviders: spend.map {
                DemoSpendProvider(id: $0.providerID, displayName: $0.displayName, snapshot: $0)
            },
            preferences: preferences, accounts: tracked.map(\.row), accountRegistry: registry,
            accountStorage: accountStorage, borrowedHomes: .demoCapture, providerFactory: factory,
            defaultLoginRecords: rememberedRecords(fixtures: fixtures, results: results, date: date),
            bankedResetAcknowledgements: acknowledged
        )
        var meters = store.menuBarMeterSelection
        let labels = Dictionary(tracked.compactMap { entry in
            entry.fixture.meterLabel.map { (entry.row.key, $0) }
        }, uniquingKeysWith: { first, _ in first })
        for i in meters.items.indices {
            if let label = labels[meters.items[i].account] { meters.items[i].label = label }
        }
        for i in meters.hidden.indices {
            if let label = labels[meters.hidden[i].account] { meters.hidden[i].label = label }
        }
        store.menuBarMeterSelection = meters
        store.seedCapturedDemo(results: results, spend: spend, at: date)
        return store
    }

    private func seedRegistry(
        _ registry: AccountRegistry, defaults: DemoMemoryDefaults, accounts: [ReplayAccount]
    ) {
        registry.seed(accounts.map(\.row).filter { $0.borrowedHome == nil })
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarAccountBadges = Dictionary(accounts.compactMap { entry in
            guard entry.row.borrowedHome == nil, let badge = entry.fixture.badge else { return nil }
            return (entry.row.key, badge)
        }, uniquingKeysWith: { first, _ in first })

        // Suppress each absent built-in before seeding the fictional T3 discovery roster.
        for provider in providerOrder where !accounts.contains(where: { $0.row.providerID == provider && $0.row.isBuiltIn }) {
            registry.stopTrackingCLISource(for: provider)
        }
        var homes: [T3CodexHome] = []
        var decisions = BorrowedHomeDecisions()
        decisions.tracksCLIDefaultAlongsideT3 = accounts.contains { $0.row.providerID == .codex && $0.row.isBuiltIn }
        for (index, entry) in accounts.enumerated() {
            guard let home = entry.row.borrowedHome else { continue }
            switch home.source {
            case .t3Instance(let instanceID, _):
                homes.append(T3CodexHome(instanceID: instanceID, displayName: nil, path: home.path, binaryPath: nil))
            case .manual:
                decisions.manualHomes.append(.init(path: home.path, addedAt: Date(timeIntervalSince1970: Double(index))))
            }
            decisions.labels[entry.row.id] = entry.fixture.label
            decisions.menuBarBadges[entry.row.id] = entry.fixture.badge
        }
        T3DiscoveryCache(defaults: defaults).record(.found(homes))
        defaults.set(try? JSONEncoder().encode(decisions), forKey: BorrowedHomeDecisions.storageKey)
        for provider in providerOrder {
            if let primary = accounts.first(where: { $0.row.providerID == provider }) {
                registry.promote(primary.row.key)
            }
        }
    }

    private func rememberedRecords(
        fixtures: [ReplayAccount], results: [AccountKey: UsageProviderFetchResult], date: Date
    ) -> DemoDefaultLoginRecordStore {
        var state = DefaultLoginRecordsState()
        for entry in fixtures {
            let key = entry.row.key
            if entry.fixture.isRemembered {
                state.remembered.append(RememberedAccount(
                    id: key.accountID, providerID: key.providerID, label: entry.fixture.label,
                    email: entry.fixture.email,
                    snapshot: StoredSnapshot(key: key, snapshot: entry.fixture.snapshot(rebasedTo: date)),
                    lastReadAt: entry.fixture.lastReadOffset.map(date.addingTimeInterval)
                ))
            } else if let snapshot = results[key]?.snapshot, let identity = snapshot.identity?.identity {
                var slot = SlotRecord(key: key)
                slot.binding = identity
                slot.mirroredLabel = entry.fixture.label
                slot.lastAcceptedCapturedAt = snapshot.capturedAt
                slot.continuityRemoved = true
                state.slots.append(slot)
            }
        }
        return DemoDefaultLoginRecordStore(seed: DefaultLoginRecordsCodec.encode(state))
    }
}

private extension BorrowedHomeEnvironment {
    static let demoCapture = Self(scanT3: { .unreadable }, canonicalize: { url in
        // The text is used as an in-memory demo folder. Never resolve symlinks or open it.
        guard let path = CanonicalHomePath(trustedCanonical: url.path) else { return .failure(.notADirectory) }
        return .success(path)
    })
}
