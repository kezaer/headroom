import Foundation

/// Persisted catalog of configured subscription accounts (multi-account, Jul 2026).
/// UserDefaults-backed like `Preferences` — account metadata is non-secret (labels and
/// IDs only; credentials stay in each CLI's own config home, KTD4).
///
/// Invariants the registry maintains:
/// - Every provider has its built-in `.primary` account, listed first — unless the user
///   stopped tracking it while extras exist (persisted tombstone, Aug 2026). A provider
///   never ends up with zero rows: the tombstone only takes effect alongside at least
///   one extra, and removing the last extra clears it.
/// - At most `maxPerProvider` accounts per provider (UI affordances are designed to 5).
///   A hidden built-in keeps its slot so resuming can never overflow the cap.
/// - Built-in accounts can be renamed and stop-tracked but never deleted — their config
///   home is the user's own CLI login, which Headroom must never touch.
public struct AccountRegistry: @unchecked Sendable { // UserDefaults is thread-safe
    public static let maxPerProvider = 5

    private let defaults: UserDefaults
    private static let storageKey = "providerAccounts.v1"
    private static let hiddenBuiltInsKey = "hiddenBuiltInAccounts.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Accounts for one provider, built-in first, extras in creation order. The
    /// built-in account is synthesized when nothing is stored yet, so first launch
    /// after upgrade needs no migration step.
    public func accounts(for providerID: ProviderID) -> [ProviderAccount] {
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
        let extras = stored.compactMap { account -> ProviderAccount? in
            guard !account.isBuiltIn, account.id != .primary,
                  seen.insert(account.id).inserted
            else { return nil }
            return account
        }
        // The tombstone hides the built-in row only while an extra exists — a torn
        // write or manual defaults edit can never leave a provider with zero rows.
        if !extras.isEmpty, hiddenBuiltIns().contains(providerID) {
            return Array(extras.prefix(Self.maxPerProvider - 1))
        }
        return Array(([builtIn] + extras).prefix(Self.maxPerProvider))
    }

    public func canAddAccount(for providerID: ProviderID) -> Bool {
        countIncludingHidden(for: providerID) < Self.maxPerProvider
    }

    /// Create and persist a new account with a fresh ID and a default label
    /// ("Account 2", "Account 3", …). Nil once the provider is at the cap.
    @discardableResult
    public func addAccount(for providerID: ProviderID, label: String? = nil) -> ProviderAccount? {
        guard countIncludingHidden(for: providerID) < Self.maxPerProvider else { return nil }
        let account = ProviderAccount(
            id: AccountID(UUID().uuidString.lowercased()),
            providerID: providerID,
            label: normalizedLabel(label) ?? defaultLabel(existing: accounts(for: providerID))
        )
        save(allWithSeeds(for: providerID) + [account])
        return account
    }

    // MARK: - Built-in tracking (stop/resume)

    /// True while the provider's built-in row is tombstoned (hidden from `accounts(for:)`).
    public func isBuiltInHidden(for providerID: ProviderID) -> Bool {
        hiddenBuiltIns().contains(providerID)
    }

    /// Stop-tracking needs a surviving row: refused while the built-in is the only account.
    public func canStopTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        !isBuiltInHidden(for: providerID)
            && accounts(for: providerID).contains { !$0.isBuiltIn }
    }

    /// Hide the built-in account from the tracked list without touching its registry
    /// record, label, or (crucially) anything on disk — the CLI login stays untouched.
    @discardableResult
    public func stopTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        guard canStopTrackingBuiltIn(for: providerID) else { return false }
        saveHiddenBuiltIns(hiddenBuiltIns().union([providerID]))
        return true
    }

    /// Clear the tombstone; the built-in resurfaces first with its persisted label.
    @discardableResult
    public func resumeTrackingBuiltIn(for providerID: ProviderID) -> Bool {
        guard isBuiltInHidden(for: providerID) else { return false }
        saveHiddenBuiltIns(hiddenBuiltIns().subtracting([providerID]))
        return true
    }

    public func renameAccount(_ key: AccountKey, to label: String) {
        guard let normalized = normalizedLabel(label) else { return }
        var all = allWithSeeds(for: key.providerID)
        guard let index = all.firstIndex(where: { $0.key == key }) else { return }
        all[index].label = normalized
        save(all)
    }

    /// Replace the stored catalog wholesale. Fixture/test seeding only — production
    /// mutations go through `addAccount`/`renameAccount`/`removeAccount`, which keep
    /// the invariants.
    public func seed(_ accounts: [ProviderAccount]) {
        save(accounts)
    }

    /// Remove a non-built-in account's registry entry. The caller owns removing its
    /// on-disk config home (`AccountStorage`) and any in-memory provider/snapshot.
    public func removeAccount(_ key: AccountKey) {
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
        guard let data = defaults.data(forKey: Self.storageKey),
              let accounts = try? JSONDecoder().decode([ProviderAccount].self, from: data)
        else { return [] }
        return accounts
    }

    private func save(_ accounts: [ProviderAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func hiddenBuiltIns() -> Set<ProviderID> {
        guard let data = defaults.data(forKey: Self.hiddenBuiltInsKey),
              let ids = try? JSONDecoder().decode(Set<ProviderID>.self, from: data)
        else { return [] }
        return ids
    }

    private func saveHiddenBuiltIns(_ ids: Set<ProviderID>) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        defaults.set(data, forKey: Self.hiddenBuiltInsKey)
    }

    /// Row count with a hidden built-in still occupying its slot — the cap gate, so
    /// resuming a tombstoned built-in can never push a provider past `maxPerProvider`.
    private func countIncludingHidden(for providerID: ProviderID) -> Int {
        let visible = accounts(for: providerID)
        let hiddenSlot = isBuiltInHidden(for: providerID)
            && !visible.contains(where: { $0.isBuiltIn })
        return visible.count + (hiddenSlot ? 1 : 0)
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

    private func normalizedLabel(_ label: String?) -> String? {
        guard let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(40))
    }

    private func defaultLabel(existing: [ProviderAccount]) -> String {
        let used = Set(existing.map(\.label))
        var n = existing.count + 1
        while used.contains("Account \(n)") { n += 1 }
        return "Account \(n)"
    }
}
