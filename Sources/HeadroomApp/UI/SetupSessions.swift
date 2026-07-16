import SwiftUI
import Observation
import HeadroomCore

/// Observable mirror of per-account Terminal-handoff state. The session enums'
/// static dictionaries are invisible to SwiftUI observation, so a row couldn't
/// repaint to "Waiting for sign-in…" until the first auto-retry mutated the store
/// (~8–12s of a dead-looking button — code-review finding). Views read this object
/// in `body`, so the flip is immediate.
@MainActor
@Observable
final class SetupSessionActivity {
    static let shared = SetupSessionActivity()

    private var openedAt: [AccountKey: Date] = [:]

    func openedAt(for key: AccountKey) -> Date? { openedAt[key] }

    func set(_ date: Date?, for key: AccountKey) { openedAt[key] = date }
}

/// The single provider→session routing switch. Views call these instead of
/// switching on `providerID` themselves — four parallel copies of that switch is
/// how a future provider ends up with a Sign In button that silently no-ops
/// (code-review finding).
@MainActor
enum SetupSessions {
    static func openSetup(for account: ProviderAccount, onRetry: @escaping () -> Void) {
        switch account.providerID {
        case .claude: ClaudeSetupSession.openSetup(for: account, onRetry: onRetry)
        case .codex: CodexSetupSession.openSetup(for: account, onRetry: onRetry)
        default: assertionFailure("No setup session registered for \(account.providerID)")
        }
    }

    static func isWaiting(for account: ProviderAccount) -> Bool {
        SetupSessionActivity.shared.openedAt(for: account.key) != nil
    }

    /// End an account's handoff session: cancel pending retries and clear the waiting
    /// flag. Called when the account goes live — and when it's removed, so orphaned
    /// retry tasks can't keep spawning poll cycles for a deleted account.
    static func settle(for account: ProviderAccount) {
        switch account.providerID {
        case .claude: ClaudeSetupSession.cancelRetries(for: account.id)
        case .codex: CodexSetupSession.cancelRetries(for: account.id)
        default: break
        }
        SetupSessionActivity.shared.set(nil, for: account.key)
    }
}
