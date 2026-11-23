import Foundation

/// Persisted catalog of configured subscription accounts (multi-account, Jul 2026).
/// UserDefaults-backed like `Preferences` — account metadata is non-secret (labels and
/// IDs only; credentials stay in each CLI's own config home, KTD4).
///
/// Invariants the registry maintains:
/// - Every provider has its built-in `.primary` account — unless the user stopped
///   tracking it while extras exist (persisted tombstone, Aug 2026). The user's
///   persisted primary choice is listed first when it is visible. A provider
///   never ends up with zero rows: the tombstone only takes effect alongside at least
///   one extra, and removing the last extra clears it.
/// - At most `capacity` accounts per provider — the caller's provider capacity, defaulting
///   to `testedEnvelope` (2026-09-19 polling plan, KTD10). A hidden built-in keeps its slot
///   so resuming can never overflow the cap.
/// - Built-in accounts can be renamed and stop-tracked but never deleted — their config
///   home is the user's own CLI login, which Headroom must never touch.
public struct AccountRegistry: @unchecked Sendable { // UserDefaults is thread-safe
    /// R15: the account count every surface, fixture, and test is proven at. A bound the
    /// product does not advertise as a limit; raise it only with the envelope demo and the
    /// suites re-run at the new value. Cursor passes 1 because it has no config-home isolation.
    public static let testedEnvelope = 20

    private let defaults: UserDefaults
    private static let storageKey = "providerAccounts.v1"
    private static let stoppedCLISourcesKey = "stoppedCLISources.v1"
    private static let hiddenBuiltInsKey = "hiddenBuiltInAccounts.v1"
    private static let primaryAccountsKey = "primaryAccounts.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Accounts for one provider, with the selected primary first and the remaining
    /// rows in canonical built-in/creation order. The built-in account is synthesized
    /// when nothing is stored yet, so first launch after upgrade needs no migration.
    public func accounts(
        for providerID: ProviderID,
        capacity: Int = AccountRegistry.testedEnvelope
    ) -> [ProviderAccount] {
        applyingPrimarySelection(to: storedOrderAccounts(for: providerID, capacity: capacity), for: providerID)
    }

    /// The same visible rows in stored registry order (built-in first, then extras in
    /// creation order), before the primary selection moves one to the front. KTD9 (iPhone
    /// parity plan): phone titles disambiguate by this order, so Make Main never moves a
    /// " · N" suffix.
    public func storedOrderAccounts(
        for providerID: ProviderID,
        capacity: Int = AccountRegistry.testedEnvelope
    ) -> [ProviderAccount] {
        let stored = load().filter { $0.providerID == providerID }
        // Treat persisted metadata as untrusted input: older builds, manual defaults
        // edits, or a torn write must not create duplicate rows or multiple built-ins.
        // Rebuild the provider slice in its canonical order while preserving the
        // stored creation order of valid extras.
        let persistedBuiltIn = stored.first { $0.isBuiltIn || $0.id == .primary }
        let builtIn = persistedBuiltIn.map {
            ProviderAccount(id: .primary, providerID: providerID, label: $0.label, isBuiltIn: true)
        } ?? .builtIn(for: providerID)
        var seen: Set<AccountID> = [.primary]
        let owned = stored.compactMap { account -> ProviderAccount? in
            guard !account.isBuiltIn, account.id != .primary,
                  seen.insert(account.id).inserted
            else { return nil }
            return account
        }
        let roster = providerID == .codex ? borrowedRoster() : nil
        let extras = owned + (roster?.visible.filter { seen.insert($0.id).inserted } ?? [])
        // The tombstone hides the built-in row only while an extra exists — a torn
        // write or manual defaults edit can never leave a provider with zero rows.
        if stoppedCLISources.contains(providerID) {
            return Array(extras.prefix(max(0, capacity - 1)))
        }
        let hidden = hiddenBuiltIns()
        if hidden.contains(providerID) {
            if extras.isEmpty {
                // Orphaned tombstone (e.g. a crash between removeAccount's catalog
                // and tombstone writes): self-heal by clearing it now, so a future
                // addAccount can't silently re-hide a built-in the user never
                // stopped tracking. Persisting the subtraction happens only in this
                // torn state — the ordinary read path stays write-free.
                saveHiddenBuiltIns(hidden.subtracting([providerID]))
            } else {
                return Array(extras.prefix(max(0, capacity - 1)))
            }
        }
        if roster?.suppressesCLIDefault == true, capacity > 1 {
            // Reserve a slot for the CLI default and guarantee one T3 row even when
            // an existing installation has already filled its owned account slots.
            let prefix = Array(extras.prefix(capacity - 1))
            if !prefix.contains(where: { $0.borrowedHome?.source.isT3 == true }),
               let firstT3 = extras.first(where: { $0.borrowedHome?.source.isT3 == true }) {
                return Array(prefix.dropLast()) + [firstT3]
            }
            return prefix
        }
        return Array(([builtIn] + extras).prefix(max(0, capacity)))
    }

    public func canAddAccount(for providerID: ProviderID, capacity: Int = AccountRegistry.testedEnvelope) -> Bool {
        countIncludingHidden(accounts(for: providerID, capacity: capacity)) < capacity
    }

    /// Create and persist a new account with a fresh ID and a default label
    /// ("Account 2", "Account 3", …). Nil once the provider is at the cap.
    @discardableResult
    public func addAccount(
        for providerID: ProviderID,
        capacity: Int = AccountRegistry.testedEnvelope,
        label: String? = nil
    ) -> ProviderAccount? {
        let visible = accounts(for: providerID, capacity: capacity)
        guard countIncludingHidden(visible) < capacity else { return nil }
        let account = ProviderAccount(
            id: AccountID(UUID().uuidString.lowercased()),
            providerID: providerID,
            label: normalizedLabel(label) ?? defaultLabel(existing: visible)
        )
        save(allWithSeeds(for: providerID) + [account])
        return account
    }

    // MARK: - Built-in tracking (stop/resume)

    /// True while the provider's built-in row is tombstoned (hidden from `accounts(for:)`).
    public func isBuiltInHidden(for providerID: ProviderID) -> Bool {
        stoppedCLISources.contains(providerID) || hiddenBuiltIns().contains(providerID)
    }

    var stoppedCLISources: Set<ProviderID> {
        loadJSON(Set<ProviderID>.self, key: Self.stoppedCLISourcesKey) ?? []
    }

    /// An explicit source choice can leave the provider without any tracked login.
    @discardableResult
    func stopTrackingCLISource(for providerID: ProviderID) -> Bool {
        guard accounts(for: providerID).contains(where: \.isBuiltIn) else { return false }
        saveJSON(stoppedCLISources.union([providerID]), key: Self.stoppedCLISourcesKey)
        return true
    }

    /// Stop-tracking needs a surviving row: refused while the built-in is the only account.
    public func canStopTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        let rows = accounts(for: providerID)
        return rows.contains(where: \.isBuiltIn) && rows.contains { !$0.isBuiltIn }
    }

    /// Hide the built-in account from the tracked list without touching its registry
    /// record, label, or (crucially) anything on disk — the CLI login stays untouched.
    @discardableResult
    public func stopTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        guard canStopTrackingBuiltIn(for: providerID) else { return false }
        saveHiddenBuiltIns(hiddenBuiltIns().union([providerID]))
        return true
    }

    /// Clear the tombstone; the built-in resurfaces with its persisted label while
    /// the provider's retained primary selection continues to determine row order.
    @discardableResult
    public func resumeTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        guard isBuiltInHidden(for: providerID) else { return false }
        saveHiddenBuiltIns(hiddenBuiltIns().subtracting([providerID]))
        saveJSON(stoppedCLISources.subtracting([providerID]), key: Self.stoppedCLISourcesKey)
        return true
    }

    public func renameAccount(_ key: AccountKey, to label: String) {
        guard let normalized = normalizedLabel(label) else { return }
        if key.providerID == .codex, borrowedRoster().visible.contains(where: { $0.key == key }) {
            var decisions = borrowedDecisions()
            decisions.labels[key.accountID] = normalized
            saveBorrowedDecisions(decisions)
            return
        }
        var all = allWithSeeds(for: key.providerID)
        guard let index = all.firstIndex(where: { $0.key == key }) else { return }
        all[index].label = normalized
        save(all)
    }

    /// Persist the visible account that compact surfaces should follow. The pointer
    /// is deliberately retained when its row is later hidden or removed; reads fall
    /// back without writing and restore the choice if that same row resurfaces.
    @discardableResult
    public func promote(_ key: AccountKey) -> Bool {
        guard accounts(for: key.providerID).contains(where: { $0.key == key }) else { return false }
        var primary = primaryAccounts()
        primary[key.providerID] = key.accountID
        saveJSON(primary, key: Self.primaryAccountsKey)
        return true
    }

    /// Replace the stored catalog wholesale. Fixture/test seeding only — production
    /// mutations go through `addAccount`/`renameAccount`/`removeAccount`, which keep
    /// the invariants.
    public func seed(_ accounts: [ProviderAccount]) {
        save(accounts)
    }

    /// Remove a non-built-in account's registry entry. The caller owns removing its
    /// on-disk config home (`AccountStorage`) and any in-memory provider/snapshot.
    public func removeAccount(_ key: AccountKey, keepingCLISourceStopped: Bool = false) {
        if key.providerID == .codex,
           let home = borrowedRoster().visible.first(where: { $0.key == key })?.borrowedHome {
            var decisions = borrowedDecisions()
            if home.source.isT3 {
                if keepingCLISourceStopped, !accounts(for: key.providerID).contains(where: \.isBuiltIn) {
                    saveJSON(stoppedCLISources.union([key.providerID]), key: Self.stoppedCLISourcesKey)
                }
                decisions.hidden.insert(key.accountID)
            } else {
                decisions.manualHomes.removeAll { $0.path == home.path }
                decisions.labels.removeValue(forKey: key.accountID)
                decisions.menuBarBadges.removeValue(forKey: key.accountID)
            }
            saveBorrowedDecisions(decisions)
            _ = accounts(for: key.providerID) // Heal a tombstone if this was the last extra.
            return
        }
        let all = load()
        guard let target = all.first(where: { $0.key == key }), !target.isBuiltIn else { return }
        save(all.filter { $0.key != key })
        // Removing the last extra makes a tombstoned built-in the only possible row
        // again. Clear the tombstone so it resurfaces now — and so a future extra
        // doesn't silently re-hide it.
        if !accounts(for: key.providerID).contains(where: { !$0.isBuiltIn }) {
            saveHiddenBuiltIns(hiddenBuiltIns().subtracting([key.providerID]))
        }
    }

    // MARK: - Storage

    private func load() -> [ProviderAccount] {
        (loadJSON([PersistedAccount].self, key: Self.storageKey) ?? []).map(\.account)
    }

    private func save(_ accounts: [ProviderAccount]) {
        saveJSON(accounts.compactMap(PersistedAccount.init), key: Self.storageKey)
    }

    private func hiddenBuiltIns() -> Set<ProviderID> {
        loadJSON(Set<ProviderID>.self, key: Self.hiddenBuiltInsKey) ?? []
    }

    private func saveHiddenBuiltIns(_ ids: Set<ProviderID>) {
        saveJSON(ids, key: Self.hiddenBuiltInsKey)
    }

    private func primaryAccounts() -> [ProviderID: AccountID] {
        loadJSON([ProviderID: AccountID].self, key: Self.primaryAccountsKey) ?? [:]
    }

    private func applyingPrimarySelection(
        to accounts: [ProviderAccount],
        for providerID: ProviderID
    ) -> [ProviderAccount] {
        guard let selectedID = primaryAccounts()[providerID],
              let selectedIndex = accounts.firstIndex(where: { $0.id == selectedID }),
              selectedIndex != accounts.startIndex
        else { return accounts }
        var reordered = accounts
        reordered.insert(reordered.remove(at: selectedIndex), at: 0)
        return reordered
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    /// Row count with a hidden built-in still occupying its slot — the cap gate, so
    /// resuming a tombstoned built-in can never push a provider past its capacity.
    private func countIncludingHidden(_ visible: [ProviderAccount]) -> Int {
        visible.count + (visible.contains(where: \.isBuiltIn) ? 0 : 1)
    }

    /// The full stored list, with the given provider's built-in seed materialized so a
    /// first mutation doesn't drop the implicit account.
    private func allWithSeeds(for providerID: ProviderID) -> [ProviderAccount] {
        var all = load()
        if !all.contains(where: { $0.providerID == providerID && $0.isBuiltIn }) {
            all.append(.builtIn(for: providerID))
        }
        return all
    }

    private func normalizedLabel(_ label: String?) -> String? { Self.normalizedLabel(label) }

    /// Shared with remembered-account renames, so both kinds of row take the same names.
    static func normalizedLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }

    private func defaultLabel(existing: [ProviderAccount]) -> String {
        let used = Set(existing.map(\.label))
        var n = existing.count + 1
        while used.contains(ProviderAccount.extraDefaultLabel(ordinal: n)) { n += 1 }
        return ProviderAccount.extraDefaultLabel(ordinal: n)
    }
}

/// The exact Release 1.6.2 element of providerAccounts.v1.
struct PersistedAccount: Codable, Equatable {
    let id: AccountID
    let providerID: ProviderID
    let label: String
    let isBuiltIn: Bool

    init?(_ account: ProviderAccount) {
        guard account.borrowedHome == nil else { return nil }
        id = account.id
        providerID = account.providerID
        label = account.label
        isBuiltIn = account.isBuiltIn
    }

    var account: ProviderAccount {
        ProviderAccount(id: id, providerID: providerID, label: label, isBuiltIn: isBuiltIn)
    }
}

extension AccountRegistry {
    private func borrowedDecisions() -> BorrowedHomeDecisions {
        loadJSON(BorrowedHomeDecisions.self, key: BorrowedHomeDecisions.storageKey) ?? .init()
    }

    private func saveBorrowedDecisions(_ decisions: BorrowedHomeDecisions) {
        saveJSON(decisions, key: BorrowedHomeDecisions.storageKey)
    }

    var t3DiscoveryCache: T3DiscoveryCache { T3DiscoveryCache(defaults: defaults) }

    private func borrowedRoster(decisions: BorrowedHomeDecisions? = nil) -> BorrowedHomeRoster.Resolved {
        BorrowedHomeRoster.resolve(
            discovered: t3DiscoveryCache.load(), decisions: decisions ?? borrowedDecisions()
        )
    }

    public var tracksCLIDefaultAlongsideT3: Bool { borrowedDecisions().tracksCLIDefaultAlongsideT3 }

    public func setTracksCLIDefaultAlongsideT3(_ on: Bool) {
        var decisions = borrowedDecisions()
        guard decisions.tracksCLIDefaultAlongsideT3 != on else { return }
        decisions.tracksCLIDefaultAlongsideT3 = on
        saveBorrowedDecisions(decisions)
    }

    public func addBorrowedHome(
        _ path: CanonicalHomePath, label: String?, for providerID: ProviderID, capacity: Int
    ) -> Result<ProviderAccount, BorrowedHomeRejection> {
        guard providerID == .codex else { return .failure(.unsupportedProvider) }
        let key = AccountKey(providerID: providerID, accountID: .borrowedHome(path))
        let roster = borrowedRoster()
        guard !(roster.visible + roster.hidden).contains(where: { $0.key == key })
        else { return .failure(.alreadyTracked(key)) }
        guard canAddAccount(for: providerID, capacity: capacity) else { return .failure(.atCapacity) }
        var decisions = borrowedDecisions()
        decisions.hidden.remove(key.accountID)
        decisions.manualHomes.removeAll { $0.path == path }
        decisions.manualHomes.append(.init(path: path, addedAt: Date()))
        decisions.labels[key.accountID] = normalizedLabel(label)
        guard let row = borrowedRoster(decisions: decisions).visible.first(where: { $0.key == key })
        else { return .failure(.alreadyTracked(key)) }
        saveBorrowedDecisions(decisions)
        return .success(row)
    }

    func discoveredT3CodexAccounts() -> [ProviderAccount] {
        let roster = borrowedRoster()
        return (roster.visible + roster.hidden).filter { $0.borrowedHome?.source.isT3 == true }
    }

    public func hiddenBorrowedAccounts(for providerID: ProviderID) -> [ProviderAccount] {
        providerID == .codex ? borrowedRoster().hidden : []
    }

    @discardableResult
    public func restoreBorrowedAccount(_ key: AccountKey, capacity: Int = testedEnvelope) -> Bool {
        guard hiddenBorrowedAccounts(for: key.providerID).contains(where: { $0.key == key }),
              canAddAccount(for: key.providerID, capacity: capacity)
        else { return false }
        var decisions = borrowedDecisions()
        decisions.hidden.remove(key.accountID)
        saveBorrowedDecisions(decisions)
        return true
    }

    public func borrowedMenuBarBadge(for id: AccountID) -> String? {
        borrowedDecisions().menuBarBadges[id]
    }

    public func setBorrowedMenuBarBadge(_ badge: String?, for id: AccountID) {
        var decisions = borrowedDecisions()
        guard decisions.menuBarBadges[id] != badge else { return }
        decisions.menuBarBadges[id] = badge
        saveBorrowedDecisions(decisions)
    }
}
