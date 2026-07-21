import SwiftUI
import Observation
import AppKit
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
    enum RecoveryRoute: Equatable {
        case documentation(URL)
        case setup(SetupHandoffMode)
        case privacyGuidance(URL)
        case copyManualCommand(SetupHandoffMode)
        case checkNow
    }

    private struct PreparedScript: Sendable {
        let scriptURL: URL
        let completionMarker: SetupCompletionMarker
    }

    private static var coordinator: SetupSessionCoordinator?
    private static var preparedScripts: [AccountKey: PreparedScript] = [:]
    private static var completionTasks: [AccountKey: Task<Void, Never>] = [:]
    private static var announcedFailures: [AccountKey: SetupSessionFailure] = [:]

    static func configure(store: UsageStore) {
        let coordinator = SetupSessionCoordinator(
            prepare: { account, mode in await prepareHandoff(for: account, mode: mode) },
            open: { handoff in openPreparedHandoff(handoff) },
            discard: { handoff in await discardPreparedHandoff(handoff) },
            accountExists: { key in
                store.accounts(for: key.providerID).contains(where: { $0.key == key })
            },
            requestRefresh: { key in store.refreshAccountNow(key) }
        )
        self.coordinator = coordinator
        store.attachSetupCoordinator(coordinator)
        for providerID in store.providerOrder {
            for account in store.accounts(for: providerID) {
                let marker = completionMarker(for: account)
                if AccountStorage.setupHandoffIsActive(marker: marker) {
                    coordinator.restoreActiveHandoff(
                        account.key,
                        mode: AccountStorage.setupHandoffMode(marker: marker) ?? .standard
                    )
                    monitorCompletion(marker, for: account.key)
                } else {
                    let completion = AccountStorage.setupHandoffCompletion(marker: marker)
                    if completion != .unknown {
                        coordinator.handoffDidEnd(account.key, completion: completion)
                        try? FileManager.default.removeItem(atPath: marker.completedPath)
                    }
                }
            }
        }
    }

    static func openSetup(for account: ProviderAccount, onRetry: @escaping () -> Void) {
        if let coordinator {
            coordinator.begin(for: account)
            return
        }
        // Render harnesses do not construct the app composition root. Preserve their
        // deterministic preview state and the legacy fallback outside production.
        switch account.providerID {
        case .claude: ClaudeSetupSession.openSetup(for: account, onRetry: onRetry)
        case .codex: CodexSetupSession.openSetup(for: account, onRetry: onRetry)
        default: assertionFailure("No setup session registered for \(account.providerID)")
        }
    }

    /// Execute the action selected by the core recovery table. Keeping this switch at
    /// the app boundary means Settings and the popover cannot accidentally turn a
    /// permission problem into another login attempt or drift on provider behavior.
    static func performRecovery(
        _ action: SetupRecoveryAction,
        for account: ProviderAccount,
        onRetry: @escaping () -> Void
    ) {
        switch recoveryRoute(for: action) {
        case .documentation(let url), .privacyGuidance(let url):
            NSWorkspace.shared.open(url)
        case .setup(.standard):
            openSetup(for: account, onRetry: onRetry)
        case .setup(.deviceCode):
            if let coordinator {
                coordinator.begin(for: account, mode: .deviceCode)
            } else {
                CodexSetupSession.openSetup(for: account, onRetry: onRetry)
            }
        case .copyManualCommand(let mode):
            _ = copyManualCommand(for: account.key, mode: mode)
        case .checkNow:
            onRetry()
        }
    }

    /// App-boundary routing for the complete typed recovery table. Keeping this pure makes the
    /// UI contract testable without opening Terminal, System Settings, or a browser.
    static func recoveryRoute(for action: SetupRecoveryAction) -> RecoveryRoute {
        switch action {
        case .installClaudeCLI:
            .documentation(URL(string: "https://docs.anthropic.com/en/docs/claude-code/getting-started")!)
        case .copyManualCommand:
            .copyManualCommand(.standard)
        case .openClaudeSetup, .connectCodex, .reconnectCodex, .resolveCodexStorage:
            .setup(.standard)
        case .installCodexCLI:
            .documentation(URL(string: "https://developers.openai.com/codex/cli/")!)
        case .connectCodexDeviceCode:
            .setup(.deviceCode)
        case .showPrivacyGuidance:
            .privacyGuidance(URL(string: "https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac")!)
        case .checkNow:
            .checkNow
        }
    }

    static func continueSetup(for account: ProviderAccount) {
        coordinator?.continueSetup(for: account)
    }

    static func isWaiting(for account: ProviderAccount) -> Bool {
        if let coordinator {
            switch coordinator.state(for: account.key) {
            case .preparing, .waiting, .verifying: return true
            default: return false
            }
        }
        return SetupSessionActivity.shared.openedAt(for: account.key) != nil
    }

    static func state(for account: ProviderAccount) -> SetupSessionState {
        coordinator?.state(for: account.key)
            ?? (isWaiting(for: account) ? .waiting(attempt: 0) : .idle)
    }

    static func mode(for account: ProviderAccount) -> SetupHandoffMode {
        coordinator?.sessionMode(for: account.key) ?? .standard
    }

    /// Redaction-safe, actionable copy for coordinator failures. Views use the typed
    /// state so preparation/open/retry failures do not collapse back into a dead-looking
    /// Connect button or expose caught filesystem/AppKit errors.
    static func failureMessage(for account: ProviderAccount) -> String? {
        guard case .failed(let failure) = state(for: account) else { return nil }
        switch failure {
        case .executableMissing:
            return account.providerID == .claude
                ? "Claude Code CLI wasn't found. Install or update it, then try again."
                : "Codex CLI wasn't found. Install or update it, then try again."
        case .stagingFailed:
            return "Headroom couldn't prepare the Terminal handoff. Try again."
        case .terminalRejected:
            return "Terminal didn't open. The official CLI command was copied for you."
        case .pasteboardFailed:
            return "Terminal didn't open, and the recovery command couldn't be copied. Try again."
        case .retryExhausted:
            return "Sign-in wasn't confirmed. Check now or reopen the official CLI."
        case .provider(let outcome):
            return outcome.message
        }
    }

    /// Multiple surfaces can observe the same account simultaneously. Deduplicate the
    /// VoiceOver announcement at the session boundary so a single transition is spoken
    /// once even when both Settings and the popover are mounted.
    static func announceFailureIfNeeded(for account: ProviderAccount) {
        guard case .failed(let failure) = state(for: account) else {
            announcedFailures.removeValue(forKey: account.key)
            return
        }
        guard announcedFailures[account.key] != failure,
              let message = failureMessage(for: account)
        else { return }
        announcedFailures[account.key] = failure
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "Setup failed. \(message)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    static func isConnected(_ account: ProviderAccount) -> Bool {
        if coordinator != nil { return state(for: account) == .connected }
        return SetupSessionActivity.shared.openedAt(for: account.key) != nil
    }

    /// End an account's handoff session: cancel pending retries and clear the waiting
    /// flag. Called when the account goes live — and when it's removed, so orphaned
    /// retry tasks can't keep spawning poll cycles for a deleted account.
    static func settle(for account: ProviderAccount) {
        if let coordinator {
            coordinator.settleConnected(account.key)
            return
        }
        switch account.providerID {
        case .claude: ClaudeSetupSession.cancelRetries(for: account.id)
        case .codex: CodexSetupSession.cancelRetries(for: account.id)
        default: break
        }
        SetupSessionActivity.shared.set(nil, for: account.key)
    }

    static func cancel(for account: ProviderAccount) {
        coordinator?.cancel(account.key)
        SetupSessionActivity.shared.set(nil, for: account.key)
    }

    private static func prepareHandoff(
        for account: ProviderAccount,
        mode: SetupHandoffMode
    ) async -> SetupPreparationResult {
        let accountCompletionMarker = completionMarker(for: account)
        let preparation = await Task.detached(priority: .userInitiated) { () -> Result<PreparedScript, SetupSessionFailure> in
            do {
                if !account.isBuiltIn {
                    _ = try AccountStorage.ensureDirectories(for: account)
                }
                let supportDirectory = ClaudeUsageWorkspace.defaultDirectoryURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Setup", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: supportDirectory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: supportDirectory.path
                )
                let scriptURL = supportDirectory
                    .appendingPathComponent("\(UUID().uuidString).command")
                let completionMarker = accountCompletionMarker
                let script: String
                switch account.providerID {
                case .claude:
                    let executable = ClaudeUsageCLIProbe.resolveClaudePath()
                    guard executable != nil else { return .failure(.executableMissing) }
                    let configuration = ProviderAccountConfiguration.make(for: account)
                    guard let workspace = configuration.claudeWorkspaceDirectory else {
                        return .failure(.stagingFailed)
                    }
                    let fallback = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                    let descriptor = ClaudeSetupDescriptor(
                        accountKey: account.key,
                        executablePath: executable,
                        loginPath: CLIExecutableResolver.resolveLoginPath(fallback: fallback),
                        workspaceDirectory: workspace.path,
                        configDirectory: configuration.claudeConfigDirectory?.path,
                        completionMarker: completionMarker
                    )
                    script = ClaudeSetupCommand.script(for: descriptor)
                case .codex:
                    let executable = CodexCLI.resolveExecutable()
                    guard executable != nil else { return .failure(.executableMissing) }
                    let configuration = ProviderAccountConfiguration.make(for: account)
                    script = CodexCLI.loginScript(
                        executablePath: executable,
                        codexHome: configuration.codexHomeDirectory?.path,
                        mode: mode,
                        completionMarker: completionMarker
                    )
                default:
                    return .failure(.stagingFailed)
                }
                try script.write(to: scriptURL, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
                return .success(PreparedScript(scriptURL: scriptURL, completionMarker: completionMarker))
            } catch {
                return .failure(.stagingFailed)
            }
        }.value

        switch preparation {
        case .success(let preparedScript):
            preparedScripts[account.key] = preparedScript
            return .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
        case .failure(let failure):
            return .failure(failure)
        }
    }

    private static func openPreparedHandoff(_ handoff: PreparedSetupHandoff) -> SetupOpenResult {
        guard let prepared = preparedScripts.removeValue(forKey: handoff.accountKey) else {
            return .failure(.stagingFailed)
        }
        do {
            try AccountStorage.prepareSetupCompletionMarker(prepared.completionMarker)
        } catch {
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return .failure(.stagingFailed)
        }
        guard NSWorkspace.shared.open(prepared.scriptURL) else {
            AccountStorage.clearPreparedSetupCompletionMarker(prepared.completionMarker)
            try? FileManager.default.removeItem(at: prepared.scriptURL)
            return copyManualCommand(for: handoff.accountKey, mode: handoff.mode)
                ? .failure(.terminalRejected)
                : .failure(.pasteboardFailed)
        }
        monitorCompletion(prepared.completionMarker, for: handoff.accountKey)
        return .success(())
    }

    private static func discardPreparedHandoff(_ handoff: PreparedSetupHandoff) async {
        guard let prepared = preparedScripts.removeValue(forKey: handoff.accountKey) else { return }
        await Task.detached(priority: .utility) {
            AccountStorage.clearPreparedSetupCompletionMarker(prepared.completionMarker)
            try? FileManager.default.removeItem(at: prepared.scriptURL)
        }.value
    }

    private static func completionMarker(for account: ProviderAccount) -> SetupCompletionMarker {
        if !account.isBuiltIn { return AccountStorage.setupCompletionMarker(for: account) }
        let directory = ClaudeUsageWorkspace.defaultDirectoryURL
            .deletingLastPathComponent()
            .appendingPathComponent("Setup", isDirectory: true)
        let stem = ".headroom-\(account.providerID.raw)-setup"
        return SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("\(stem)-pending").path,
            completedPath: directory.appendingPathComponent("\(stem)-complete").path
        )
    }

    private static func monitorCompletion(_ marker: SetupCompletionMarker, for key: AccountKey) {
        completionTasks.removeValue(forKey: key)?.cancel()
        completionTasks[key] = Task { @MainActor in
            while !Task.isCancelled, AccountStorage.setupHandoffIsActive(marker: marker) {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            coordinator?.handoffDidEnd(
                key,
                completion: AccountStorage.setupHandoffCompletion(marker: marker)
            )
            try? FileManager.default.removeItem(atPath: marker.completedPath)
            completionTasks[key] = nil
        }
    }

    @discardableResult
    private static func copyManualCommand(
        for key: AccountKey,
        mode: SetupHandoffMode
    ) -> Bool {
        let account = ProviderAccount(
            id: key.accountID,
            providerID: key.providerID,
            label: "Account",
            isBuiltIn: key.accountID == .primary
        )
        let command: String
        switch key.providerID {
        case .claude:
            let configuration = ProviderAccountConfiguration.make(for: account)
            guard let workspace = configuration.claudeWorkspaceDirectory else { return false }
            command = ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
                accountKey: key,
                executablePath: ClaudeUsageCLIProbe.resolveClaudePath(),
                loginPath: "",
                workspaceDirectory: workspace.path,
                configDirectory: configuration.claudeConfigDirectory?.path
            ))
        case .codex:
            command = CodexCLI.accountLoginCommand(
                codexHome: ProviderAccountConfiguration.make(for: account).codexHomeDirectory?.path,
                mode: mode
            )
        default:
            return false
        }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(command, forType: .string)
    }
}
