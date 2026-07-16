import Foundation

/// Persisted catalog of configured subscription accounts (multi-account, Jul 2026).
/// UserDefaults-backed like `Preferences` — account metadata is non-secret (labels and
/// IDs only; credentials stay in each CLI's own config home, KTD4).
///
/// Invariants the registry maintains:
/// - Every provider always has its built-in `.primary` account, listed first.
/// - At most `maxPerProvider` accounts per provider (UI affordances are designed to 5).
/// - Built-in accounts can be renamed but never removed.
public struct AccountRegistry: @unchecked Sendable { // UserDefaults is thread-safe
    public static let maxPerProvider = 5

    private let defaults: UserDefaults
    private static let storageKey = "providerAccounts.v1"

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
        return Array(([builtIn] + extras).prefix(Self.maxPerProvider))
    }

    public func canAddAccount(for providerID: ProviderID) -> Bool {
        accounts(for: providerID).count < Self.maxPerProvider
    }

    /// Create and persist a new account with a fresh ID and a default label
    /// ("Account 2", "Account 3", …). Nil once the provider is at the cap.
    @discardableResult
    public func addAccount(for providerID: ProviderID, label: String? = nil) -> ProviderAccount? {
        let existing = accounts(for: providerID)
        guard existing.count < Self.maxPerProvider else { return nil }
        let account = ProviderAccount(
            id: AccountID(UUID().uuidString.lowercased()),
            providerID: providerID,
            label: normalizedLabel(label) ?? defaultLabel(existing: existing)
        )
        save(allWithSeeds(for: providerID) + [account])
        return account
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
