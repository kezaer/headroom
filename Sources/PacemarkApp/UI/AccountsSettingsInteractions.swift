import Foundation
import PacemarkCore

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

/// R2C7: `hasRetainedReading` is true when the same card still draws usage from an earlier
/// capture, so the sentence can say the reading is the last one rather than ignore it.
func capabilityRecoveryPresentation(
    state: ProviderCapabilityState?,
    hasActiveSetupSession: Bool,
    hasRetainedReading: Bool = false
) -> CapabilityRecoveryPresentation? {
    guard let recovery = state?.recoveryPresentation(hasRetainedReading: hasRetainedReading) else { return nil }
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
    enum PromotionState: Equatable {
        case unavailable
        case primary
        case available
    }

    struct PromotionFeedback: Equatable {
        let accountKey: AccountKey
        let announcement: String
    }

    enum BuiltInRowActions: Equatable {
        case unavailable
        case resetOnly
        case resetAndStopTracking
    }
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
        /// R2C11: two buttons need a line of their own. Only the *buttons* move — the status
        /// stays pinned in the trailing column in both silhouettes, so one list can't print
        /// the same state in two different places.
        var usesSecondLine: Bool {
            secondaryLabel != nil && secondaryAction != nil
        }
    }

    /// R9/R10 (KTD6): the provider group header's subscription switch. The switch is the
    /// only thing "off" governs — it decides whether Pacemark *fetches* the provider, so
    /// its disabled state exists purely to stop a flip mid-handoff, never to lock the
    /// group's account management.
    struct SubscriptionSwitchPresentation: Equatable {
        let isEnabled: Bool
        /// Non-nil only while disabled: the tooltip that names the blocking sign-in (R10).
        let helpText: String?
        let accessibilityLabel: String
    }

    /// Provider enablement gates fetch-derived recovery. Source management stays available.
    struct ProviderGroupPresentation: Equatable {
        let subscriptionSwitch: SubscriptionSwitchPresentation
        let isFetching: Bool

        var dimsAccountRows: Bool { !isFetching }
        /// R11: only *fetch-derived* status hides while the provider is off. Sign-in the
        /// user starts anyway ("Waiting for sign-in…", setup failure, blocked, removal)
        /// is management state and must stay visible, or the handoff looks like nothing
        /// happened (code-review finding).
        func hidesAccountStatus(isSetupState: Bool) -> Bool {
            !isFetching && !isSetupState
        }
        var hidesFetchRecovery: Bool { !isFetching }
        var hidesCapabilityBanner: Bool { !isFetching }
        /// R2B1: one constant, shared with the Menu Bar pane's Off-tag tooltip, so the two
        /// statements of this rule cannot drift — they already disagreed on the full stop.
        var offHelpText: String? {
            isFetching ? nil : SettingsCopy.providerOffNotice
        }
    }

    static func subscriptionSwitchPresentation(
        providerDisplayName: String,
        accounts: [ProviderAccount],
        isSurfaceEnabled: Bool,
        hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
    ) -> SubscriptionSwitchPresentation {
        let accessibilityLabel = "\(providerDisplayName) subscription"
        guard accounts.contains(where: hasActiveHandoff) else {
            return SubscriptionSwitchPresentation(
                isEnabled: true,
                helpText: nil,
                accessibilityLabel: accessibilityLabel
            )
        }
        // R10: an open Terminal handoff owns the provider until it resolves; flipping the
        // switch under it would either drop the account it is about to produce or start
        // polling a half-written config home.
        let direction = isSurfaceEnabled ? "off" : "on"
        return SubscriptionSwitchPresentation(
            isEnabled: false,
            helpText: "Finish or stop the sign-in in progress before turning \(providerDisplayName) \(direction)",
            accessibilityLabel: accessibilityLabel
        )
    }

    /// A provider's standing help line under its group, shown whether or not it is fetched.
    /// Only OpenCode has one (KTD21): each home reads one Console workspace.
    static func providerGroupNote(for providerID: ProviderID) -> String? {
        providerID == .opencode ? SettingsCopy.opencodeWorkspaceScope : nil
    }

    static func providerGroupPresentation(
        providerDisplayName: String,
        accounts: [ProviderAccount],
        isSurfaceEnabled: Bool,
        hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
    ) -> ProviderGroupPresentation {
        ProviderGroupPresentation(
            subscriptionSwitch: subscriptionSwitchPresentation(
                providerDisplayName: providerDisplayName,
                accounts: accounts,
                isSurfaceEnabled: isSurfaceEnabled,
                hasActiveHandoff: hasActiveHandoff
            ),
            isFetching: isSurfaceEnabled
        )
    }

    nonisolated static func accountCounterText(usedSlots: Int, capacity: Int) -> String {
        "\(usedSlots) of \(capacity)"
    }

    nonisolated static func defaultCLIPath(for providerID: ProviderID) -> String? {
        switch providerID {
        case .codex: "~/.codex"
        case .claude: "~/.claude"
        case .antigravity: "~/.gemini"
        case .grok: "~/.grok"
        case .cursor: "~/.cursor"
        case .copilot: "~/.config/gh"
        case .opencode: "~/.local/share/opencode"
        default: nil
        }
    }

    /// R12: leaving Accounts (pane switch or window close) must not silently discard a
    /// typed rename. Uses the same rule as `commitLabel` so the caller commits exactly the
    /// drafts that would change something, in the list's own order.
    nonisolated static func pendingLabelCommits(
        drafts: [AccountKey: String],
        accounts: [ProviderAccount]
    ) -> [ProviderAccount] {
        accounts.filter { account in
            guard let draft = drafts[account.key] else { return false }
            return pendingRename(draft, for: account) != nil
        }
    }

    /// The same sweep over the display rows (default-login plan U7), so a typed rename of
    /// a remembered row commits to the record store like any other.
    nonisolated static func pendingLabelCommits(
        drafts: [AccountKey: String],
        rows: [DisplayAccount]
    ) -> [DisplayAccount] {
        rows.filter { row in
            guard let draft = drafts[row.key] else { return false }
            return pendingRename(draft, for: row.account) != nil
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
        guard let trimmed = pendingRename(draft, for: account) else { return false }
        store.renameAccount(account.key, to: trimmed)
        return true
    }

    /// KTD8: a rename follows the row's kind. A remembered row's label lives in the record
    /// store, so it never reaches the registry.
    @discardableResult
    static func commitLabel(
        _ draft: String,
        for row: DisplayAccount,
        in store: UsageStore
    ) -> Bool {
        switch row.kind {
        case .engine:
            return commitLabel(draft, for: row.account, in: store)
        case .remembered:
            guard let trimmed = pendingRename(draft, for: row.account) else { return false }
            return store.renameRememberedAccount(row.key, to: trimmed)
        }
    }

    /// The one rule for "this draft renames the account": trimmed, non-empty, and
    /// different from the current label. Shared by the commit path and the
    /// leave-Accounts sweep so the two can never disagree (R12).
    nonisolated static func pendingRename(_ draft: String, for account: ProviderAccount) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != account.label else { return nil }
        return trimmed
    }

    /// Built-in rows route to the non-destructive stop-tracking path — their config
    /// home is the user's own CLI login, which Pacemark never deletes. Extras keep the
    /// destructive removal that deletes their Pacemark-owned config home.
    static func removeAccount(
        _ account: ProviderAccount,
        from store: UsageStore
    ) async -> AccountRemovalResult {
        account.isBuiltIn
            ? await store.stopTrackingBuiltInAccount(for: account.providerID)
            : await store.removeAccount(account.key)
    }

    // MARK: Remembered rows (default-login plan U8)

    /// The removal dialog's title, by row kind: stop-tracking for the built-in row, removal
    /// for an extra or a remembered row.
    nonisolated static func removalPolicy(for row: DisplayAccount) -> AccountRowPolicy.Removal? {
        guard !row.isRemembered else { return nil }
        return AccountRowPolicy.make(for: row.account, canStopTrackingBuiltIn: true).removal
    }

    nonisolated static func removalActionTitle(for row: DisplayAccount) -> String {
        removalIsDestructive(for: row) ? "Sign Out & Stop Tracking" : "Stop Tracking"
    }

    static func stopTrackingSource(_ row: DisplayAccount, in store: UsageStore) async -> AccountRemovalResult {
        guard !removalIsDestructive(for: row) else { return .notAllowed }
        if row.account.isBuiltIn {
            return await store.stopTrackingBuiltInAccount(for: row.account.providerID, allowingEmpty: true)
        }
        if !row.isRemembered, row.account.borrowedHome != nil {
            return await store.removeAccount(row.key, keepingCLISourceStopped: true)
        }
        return await removeAccount(row, from: store)
    }

    nonisolated static func removalDialogTitle(for row: DisplayAccount) -> String {
        switch removalPolicy(for: row) {
        case .stopTrackingCLIDefault: "Stop tracking this account?"
        case .hideT3Home: "Hide this T3 account?"
        case .forgetFolder: "Forget this Codex folder?"
        case .deleteOwnedHome: "Sign out and stop tracking this account?"
        case nil: "Remove this account?"
        }
    }

    nonisolated static func removalDialogMessage(for row: DisplayAccount) -> String {
        switch removalPolicy(for: row) {
        case .stopTrackingCLIDefault:
            "Pacemark stops showing it. Your CLI stays signed in — nothing on this Mac is deleted."
        case .deleteOwnedHome:
            "Its sign-in on this Mac is deleted with it. Your subscription is untouched."
        case .hideT3Home, .forgetFolder:
            removalPolicy(for: row)?.confirmationMessage ?? ""
        case nil:
            "It stays hidden until your CLI is signed in to this account again. Nothing is deleted."
        }
    }

    nonisolated static func removalIsDestructive(for row: DisplayAccount) -> Bool {
        removalPolicy(for: row) == .deleteOwnedHome
    }

    /// U8 (R7): the status a remembered row prints in Settings, the popover's own tag
    /// ("Last read 2 min ago"). Nil only when nothing records when it was read.
    nonisolated static func rememberedStatus(lastReadAt: Date?, snapshot: UsageSnapshot, now: Date) -> String? {
        Countdown.lastReadLabel(capturedAt: lastReadAt ?? snapshot.capturedAt, now: now)
    }

    /// U8: the status line's tooltip. A remembered row is never read on its own; it goes
    /// live when the CLI is signed in to it again, or after adding a separate login.
    nonisolated static let rememberedStatusHelp =
        "Pacemark reads this account again when your CLI is signed in to it. To keep it live alongside your current login, choose Separate login in Add source…"

    /// KTD8: removing a remembered row hides it in the record store (R11); it deletes no
    /// config home and writes no registry tombstone. Engine rows keep their two paths.
    static func removeAccount(
        _ row: DisplayAccount,
        from store: UsageStore
    ) async -> AccountRemovalResult {
        switch row.kind {
        case .engine:
            return await removeAccount(row.account, from: store)
        case .remembered:
            return store.removeRememberedAccount(row.key) ? .removed : .notAllowed
        }
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

    static func builtInRowActions(
        for account: ProviderAccount,
        in store: UsageStore
    ) -> BuiltInRowActions {
        guard account.isBuiltIn,
              store.canResetBuiltInAccount(for: account.providerID)
        else { return .unavailable }
        if account.providerID == .antigravity,
           store.antigravitySourcePreference == .autoPreferT3,
           AppComposition.isT3AntigravityAvailable() {
            return .unavailable
        }
        return store.canStopTrackingBuiltInAccount(for: account.providerID)
            ? .resetAndStopTracking
            : .resetOnly
    }

    // MARK: One account, one row (default-login plan U10)

    /// KTD11: the built-in row the one-row merge hides, if any. Its row shows through the
    /// extra that reads the same account, so its own actions move to the provider header.
    static func mergedBuiltIn(for providerID: ProviderID, in store: UsageStore) -> ProviderAccount? {
        let merged = store.displayProjection(for: providerID).mergeMap.keys
        guard !merged.isEmpty else { return nil }
        return store.accounts(for: providerID).first { $0.isBuiltIn && merged.contains($0.key) }
    }

    /// U10: what the provider header offers for a merged built-in. `.unavailable` when
    /// nothing is merged, so a setup with no merge draws the header as before (R15).
    static func mergedBuiltInActions(for providerID: ProviderID, in store: UsageStore) -> BuiltInRowActions {
        guard let builtIn = mergedBuiltIn(for: providerID, in: store) else { return .unavailable }
        return builtInRowActions(for: builtIn, in: store)
    }

    /// The "Sign out and set up again?" message. For the built-in OpenCode account it is
    /// also the D7 warning, so a reset from Settings asks once, not twice.
    static func resetDialogMessage(for account: ProviderAccount, providerDisplayName: String) -> String {
        if account.providerID == .opencode {
            return BuiltInSignInConfirmation.message(for: .reset)
        }
        return "Signing in again switches the \(providerDisplayName) CLI login across this Mac, including Terminal sessions. If you only want Pacemark to show another login, add it as a separate account and use Make Main."
    }

    @discardableResult
    static func resetBuiltIn(
        _ account: ProviderAccount,
        in store: UsageStore,
        beginReset: @MainActor (ProviderAccount) -> Void = { SetupSessions.resetSetup(for: $0) }
    ) -> Bool {
        guard account.isBuiltIn,
              store.canResetBuiltInAccount(for: account.providerID)
        else { return false }
        beginReset(account)
        return true
    }

    /// The Main badge reads the display primary (KTD8); a remembered row is never main
    /// and never offered Make Main (KTD12).
    static func promotionState(
        for account: ProviderAccount,
        in store: UsageStore
    ) -> PromotionState {
        if store.displayPrimaryKey(for: account.providerID) == account.key { return .primary }
        return store.canPromoteAccount(account.key) ? .available : .unavailable
    }

    static func promotionState(
        for row: DisplayAccount,
        in store: UsageStore
    ) -> PromotionState {
        row.isRemembered ? .unavailable : promotionState(for: row.account, in: store)
    }

    @discardableResult
    static func makeMain(
        _ account: ProviderAccount,
        in store: UsageStore
    ) -> PromotionFeedback? {
        guard store.promoteAccount(account.key) else { return nil }
        return PromotionFeedback(
            accountKey: account.key,
            announcement: "\(account.label) is now Main"
        )
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

    /// Provider capability belongs to the shared executable: the handoff binds to the
    /// selected primary, while Check Again refreshes every account of this provider (R18).
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
            if let refresh {
                for account in store.accounts(for: providerID) { refresh(account.key) }
            } else {
                store.refreshProviderNow(providerID)
            }
        }
        return true
    }
}
