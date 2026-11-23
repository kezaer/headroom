#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import HeadroomCore

@MainActor
func settingsRecoveryActions(
    snapshot: UsageSnapshot,
    account: ProviderAccount,
    setupState: SetupSessionState
) -> AccountsSettingsInteractions.RecoveryRowActions? {
    guard setupHandoffRefusalMessage(for: setupState) == nil else { return nil }
    // R13/KTD12 (2026-09-19 sign-in plan): the row rendered Sign In *and* Check Now all
    // through a handoff, because `recoveryButtons` is gated on this being non-nil. While
    // the session owns its own controls — waiting, confirming, the timeout, a too-old CLI
    // — the outcome's fetch-recovery pair is suppressed the way a refusal already does.
    guard setupRowRecovery(for: setupState) == .outcomeRecovery else { return nil }
    return AccountsSettingsInteractions.recoveryRowActions(
        snapshot: snapshot,
        account: account
    )
}

extension AccountsSettingsTile {
    @ViewBuilder func accountStatus(
        _ capabilityRow: AccountsSettingsInteractions.CapabilityRowPresentation,
        status: AccountStatus,
        setupFailure: String?,
        setupSentence: String?,
        account: ProviderAccount
    ) -> some View {
        capabilityStatusLabel(
            capabilityRow,
            fallbackStatus: status,
            setupFailure: setupFailure,
            setupSentence: setupSentence,
            setupMode: SetupSessions.mode(for: account),
            setupWaitingTitle: SetupSessions.waitingPhase(for: account)?.copy.title,
            providerDisplayName: store.displayNames[account.providerID]
                ?? account.providerID.raw.capitalized
        )
    }

    @ViewBuilder func recoveryButtons(
        for account: ProviderAccount,
        status: AccountStatus,
        setupState: SetupSessionState,
        recoveryActions: AccountsSettingsInteractions.RecoveryRowActions?
    ) -> some View {
        switch setupRowRecovery(for: setupState) {
        case .sessionOnly:
            // R13: the session's own control is Stop Waiting, in the row's trailing slot.
            EmptyView()
        case .tryAgain:
            // KTD12: not `.checkNow` and never labelled "Check Now" — Try Again brings the
            // still-open window forward and resumes the wait (R10), or with none open stages
            // a fresh handoff, which is what re-reads a too-old CLI's version (R6).
            Button(SetupRowChip.tryAgain.label) {
                SetupSessions.tryAgain(
                    for: account,
                    onRetry: { store.refreshAccountNow(account.key) }
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Try signing in again for \(store.desktopAccountName(for: account))")
        case .outcomeRecovery:
            if account.borrowedHome == nil || recoveryActions != nil {
                outcomeRecoveryButtons(
                    for: account,
                    status: status,
                    recoveryActions: recoveryActions
                )
            }
        }
    }

    @ViewBuilder private func outcomeRecoveryButtons(
        for account: ProviderAccount,
        status: AccountStatus,
        recoveryActions: AccountsSettingsInteractions.RecoveryRowActions?
    ) -> some View {
        if status.needsRecovery || recoveryActions != nil {
            // PA12: no ellipsis on "Sign In". The popover's button for the same action has
            // never had one, and two surfaces spelling one action two ways reads as two
            // actions. ("Add Account…" and "Check for Updates…" keep theirs — those open a
            // further choice; signing in is the whole action.)
            //
            // R2B1: "Continue Setup", not "Continue…". The ellipsis promised a further choice
            // that never arrives — the button resumes the handoff already open — and a bare
            // "Continue" doesn't say what it continues. R2C6: the primary label otherwise
            // comes from Core's `ProviderSetupOutcome`, which owns the one sign-in verb.
            Button(status == .blocked
                   ? "Continue Setup"
                   : (recoveryActions?.primaryLabel
                      ?? (status == .setupFailed ? "Retry…" : "Sign In"))) {
                if status == .blocked {
                    SetupSessions.continueSetup(for: account)
                } else if let recoveryActions {
                    SetupSessions.performRecovery(
                        recoveryActions.primaryAction,
                        for: account,
                        onRetry: { store.refreshAccountNow(account.key) }
                    )
                } else {
                    openSetup(for: account)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(
                recoveryActions?.primaryAccessibilityLabel
                    ?? "\(status == .blocked ? "Continue setup" : "Sign in") for \(store.desktopAccountName(for: account))"
            )
            if let secondaryLabel = recoveryActions?.secondaryLabel,
               let secondaryAction = recoveryActions?.secondaryAction {
                Button(secondaryLabel) {
                    SetupSessions.performRecovery(
                        secondaryAction,
                        for: account,
                        onRetry: { store.refreshAccountNow(account.key) }
                    )
                }
                // B3A/B3H: bare beside a bordered primary was the worst mix in Settings; the
                // small chip gives it a resting container and its own font and ink, and it
                // keeps that container — its neighbour is a `.bordered` button.
                .buttonStyle(SetupChipButtonStyle(size: .small, chrome: .resting))
                .accessibilityLabel(
                    recoveryActions?.secondaryAccessibilityLabel
                        ?? "\(secondaryLabel) for \(store.desktopAccountName(for: account))"
                )
            }
        }
    }
    @ViewBuilder private func capabilityStatusLabel(
        _ presentation: AccountsSettingsInteractions.CapabilityRowPresentation,
        fallbackStatus: AccountStatus,
        setupFailure: String?,
        setupSentence: String?,
        setupMode: SetupHandoffMode,
        setupWaitingTitle: String?,
        providerDisplayName: String
    ) -> some View {
        switch presentation {
        case .standard:
            statusLabel(
                fallbackStatus,
                setupFailure: setupFailure,
                setupSentence: setupSentence,
                setupMode: setupMode,
                setupWaitingTitle: setupWaitingTitle,
                providerDisplayName: providerDisplayName
            )
        case .waitingForClaudeCode:
            // R2B1: the ellipsis says the wait is ongoing, matching every other waiting
            // status in the window ("Waiting for sign-in…", "Fetching…").
            Text("Waiting for Claude Code…")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        case .retainedUsage:
            Text("Last reading retained")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func statusLabel(
        _ status: AccountStatus,
        setupFailure: String?,
        setupSentence: String?,
        setupMode: SetupHandoffMode,
        setupWaitingTitle: String?,
        providerDisplayName: String
    ) -> some View {
        switch status {
        case .connected:
            // PB13: the window's one affirmative-state treatment, shared with "Saved
            // securely" in API Spend. Plain secondary text rendered identically to Stale,
            // which is the opposite state.
            if let setupWaitingTitle {
                Text(setupWaitingTitle).font(SettingsType.help).foregroundStyle(.secondary)
            }
        case .fetching:
            Text("Fetching…")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        case .waiting:
            Text(setupWaitingTitle ?? (setupMode == .deviceCode ? "Waiting for device code…" : "Waiting for sign-in…"))
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        case .stale:
            // Clock glyph separates "data gone old" from the affirmative "Connected" —
            // the two rendered identically before (impeccable audit P1). Restrained on
            // purpose: stale is usually a transient blip, not an alarm.
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9, weight: .medium))
                Text("Stale")
                    .font(SettingsType.help)
            }
            .foregroundStyle(.secondary)
        case .needsSignIn:
            // R2C6: the popover's own sentence, read from Core. Settings used to print
            // "Needs sign-in" beside a row whose button said "Sign In" and whose popover card
            // said "Sign in with the official Claude CLI" — one act under three names, which
            // makes people ask whether the three do different things.
            Text(setupSentence ?? "Sign in with the official \(providerDisplayName) CLI")
                .font(SettingsType.help)
                // R2C5: a lifecycle sentence, not a measurement — it stays off the amber ramp
                // here as it does in the popover.
                .foregroundStyle(ProviderStyle.meterLabelInk(scheme: colorScheme))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        case .blocked:
            // PB9: "sign-in", the word the popover and every other status here uses for this
            // event. "login" was the only place it was called something else.
            Text("Another \(providerDisplayName) sign-in is open")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
        case .setupFailed:
            Text(setupFailure ?? "Setup failed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
                .lineLimit(2)
        case .removing:
            Text("Removing…").font(SettingsType.help).foregroundStyle(.secondary)
        case .setupActive:
            Text("Close setup, then retry")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
        case .removalFailed:
            Text("Removal failed")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
        }
    }

    // MARK: - Status

    enum AccountStatus {
        case connected, fetching, waiting, stale, needsSignIn, blocked, setupFailed
        case removing, setupActive, removalFailed

        init(
            snapshot: UsageSnapshot,
            waiting: Bool,
            blocked: Bool,
            blockedByOpenHandoff: Bool,
            setupFailed: Bool,
            removalState: AccountRemovalState?
        ) {
            switch removalState {
            case .removing: self = .removing; return
            case .setupActive: self = .setupActive; return
            case .failed: self = .removalFailed; return
            case nil: break
            }
            if blockedByOpenHandoff { self = .setupActive; return }
            if blocked { self = .blocked; return }
            if setupFailed { self = .setupFailed; return }
            if waiting { self = .waiting; return }
            switch snapshot.freshness {
            case .live:
                self = .connected
            case .pending:
                self = .fetching
            case .stale(let reason):
                self = reason.isPermanent ? .needsSignIn : .stale
            }
        }

        var needsRecovery: Bool {
            self == .needsSignIn || self == .blocked || self == .setupFailed
        }

        /// R11: sign-in and removal states are management, not fetch health, so they
        /// survive a provider whose subscription switch is off — that switch only stops
        /// fetching, and an in-flight sign-in still reports itself. (L11A dims Add
        /// Account while off; a handoff already under way is unaffected.)
        var isSetupState: Bool {
            self == .waiting || self == .setupActive || self == .setupFailed
                || self == .blocked || self == .removing || self == .removalFailed
        }
    }
}
