import HeadroomCore

/// App-boundary account actions shared by the Settings controls and their deterministic tests.
/// Provider effects remain injected: adding an account invokes only the selected account's
/// official-CLI handoff, while persistence and cleanup stay owned by `UsageStore`.
@MainActor
enum AccountsSettingsInteractions {
    @discardableResult
    static func addAccount(
        for providerID: ProviderID,
        to store: UsageStore,
        openSetup: (ProviderAccount) -> Void
    ) -> ProviderAccount? {
        guard let account = store.addAccount(for: providerID) else { return nil }
        openSetup(account)
        return account
    }

    @discardableResult
    static func commitLabel(
        _ draft: String,
        for account: ProviderAccount,
        in store: UsageStore
    ) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != account.label else { return false }
        store.renameAccount(account.key, to: trimmed)
        return true
    }

    static func removeAccount(
        _ account: ProviderAccount,
        from store: UsageStore
    ) async -> AccountRemovalResult {
        await store.removeAccount(account.key)
    }
}
