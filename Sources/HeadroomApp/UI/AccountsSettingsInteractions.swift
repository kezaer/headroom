import HeadroomCore

enum CapabilityRecoveryActionState: Equatable {
    case enabled
    case refused(String)
}

/// Provider-wide recovery stays separate from account snapshots. This wrapper adds only
/// surface state: an open Terminal handoff keeps the notice visible while retry/setup
/// actions explain why they cannot start another handoff yet.
struct CapabilityRecoveryPresentation: Equatable {
    let recovery: ProviderRecoveryPresentation
    let hasActiveSetupSession: Bool

    func state(for action: SetupRecoveryAction) -> CapabilityRecoveryActionState {
        guard hasActiveSetupSession else { return .enabled }
        switch action {
        case .checkNow, .openClaudeSetup:
            return .refused("Close setup, then retry")
        default:
            return .enabled
        }
    }
}

func capabilityRecoveryPresentation(
    state: ProviderCapabilityState?,
    hasActiveSetupSession: Bool
) -> CapabilityRecoveryPresentation? {
    guard let recovery = state?.recoveryPresentation else { return nil }
    return CapabilityRecoveryPresentation(
        recovery: recovery,
        hasActiveSetupSession: hasActiveSetupSession
    )
}

struct CapabilityAnnouncementDedupe {
    private var lastStates: [ProviderID: ProviderCapabilityState] = [:]

    mutating func announcement(
        for providerID: ProviderID,
        state: ProviderCapabilityState?
    ) -> String? {
        guard lastStates[providerID] != state else { return nil }
        lastStates[providerID] = state
        guard let status = state?.recoveryPresentation?.status else { return nil }
        return "Claude Code availability. \(status)"
    }
}

/// App-boundary account actions shared by the Settings controls and their deterministic tests.
/// Provider effects remain injected: adding an account invokes only the selected account's
/// official-CLI handoff, while persistence and cleanup stay owned by `UsageStore`.
@MainActor
enum AccountsSettingsInteractions {
    struct RecoveryRowActions: Equatable {
        let presentation: ProviderRecoveryPresentation
        let accountLabel: String

        var primaryLabel: String { presentation.primaryLabel }
        var primaryAction: SetupRecoveryAction { presentation.primaryAction }
        var primaryAccessibilityLabel: String { "\(primaryLabel) for \(accountLabel)" }
        var secondaryLabel: String? { presentation.secondaryLabel }
        var secondaryAction: SetupRecoveryAction? { presentation.secondaryAction }
        var secondaryAccessibilityLabel: String? {
            secondaryLabel.map { "\($0) for \(accountLabel)" }
        }
        var usesSecondLine: Bool {
            secondaryLabel != nil && secondaryAction != nil
        }
    }

    enum CapabilityRowPresentation: Equatable {
        case standard
        case waitingForClaudeCode
        case retainedUsage
    }

    nonisolated static func capabilityRowPresentation(
        snapshot: UsageSnapshot,
        capability: CapabilityRecoveryPresentation?
    ) -> CapabilityRowPresentation {
        guard capability != nil else { return .standard }
        return snapshot.windows.isEmpty ? .waitingForClaudeCode : .retainedUsage
    }

    nonisolated static func recoveryRowActions(
        snapshot: UsageSnapshot,
        account: ProviderAccount
    ) -> RecoveryRowActions? {
        guard case .stale(let reason) = snapshot.freshness,
              let presentation = reason.providerSetupOutcome?.recoveryPresentation
        else { return nil }
        return RecoveryRowActions(presentation: presentation, accountLabel: account.label)
    }

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

    /// Built-in rows route to the non-destructive stop-tracking path — their config
    /// home is the user's own CLI login, which Headroom never deletes. Extras keep the
    /// destructive removal that deletes their Headroom-owned config home.
    static func removeAccount(
        _ account: ProviderAccount,
        from store: UsageStore
    ) async -> AccountRemovalResult {
        account.isBuiltIn
            ? await store.stopTrackingBuiltInAccount(for: account.providerID)
            : await store.removeAccount(account.key)
    }

    /// Shared Settings/popover action for an abandoned Terminal handoff. The store
    /// cleanup makes a prior `.setupActive` removal refusal immediately retryable.
    static func stopWaiting(
        for account: ProviderAccount,
        in store: UsageStore,
        forceCancel: @MainActor (ProviderAccount) -> Void = SetupSessions.forceCancel(for:)
    ) {
        forceCancel(account)
        store.cancelAccountRemoval(account.key)
    }

    /// Undo for stop-tracking: resurface the CLI's own login and fetch it right away.
    @discardableResult
    static func resumeTrackingBuiltIn(
        for providerID: ProviderID,
        in store: UsageStore
    ) -> ProviderAccount? {
        guard let account = store.resumeTrackingBuiltInAccount(for: providerID) else { return nil }
        store.refreshAccountNow(account.key)
        return account
    }

    /// Provider capability belongs to the shared executable, so the notice always binds
    /// its recovery to the built-in/primary account. Check Again's callback consequently
    /// refreshes one account after forced discovery instead of sweeping every configured login.
    @discardableResult
    static func performCapabilityRecovery(
        _ action: SetupRecoveryAction,
        for providerID: ProviderID,
        in store: UsageStore,
        perform: (SetupRecoveryAction, ProviderAccount, @escaping () -> Void) -> Void = {
            SetupSessions.performRecovery($0, for: $1, onRetry: $2)
        },
        refresh: ((AccountKey) -> Void)? = nil
    ) -> Bool {
        guard let primary = store.primaryAccount(for: providerID) else { return false }
        perform(action, primary) {
            (refresh ?? store.refreshAccountNow)(primary.key)
        }
        return true
    }
}
