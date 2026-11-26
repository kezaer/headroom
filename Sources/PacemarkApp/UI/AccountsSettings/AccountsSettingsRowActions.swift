#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import AppKit
import PacemarkCore

@MainActor
func settingsStopWaitingAccount(
    _ account: ProviderAccount,
    removalState: AccountRemovalState?,
    setupState: SetupSessionState,
    hasActiveHandoff: @MainActor (ProviderAccount) -> Bool = SetupSessions.hasActiveHandoff(for:)
) -> ProviderAccount? {
    guard setupSessionOffersStopWaiting(
              state: setupState,
              hasActiveHandoff: hasActiveHandoff(account)
          )
            || removalState == .setupActive
            || setupState == .blockedByOpenHandoff
    else { return nil }
    return account
}

extension AccountsSettingsTile {
    func accountMenu(_ row: DisplayAccount, source: AccountSourceKind, setupState: SetupSessionState) -> some View {
        let account = row.account
        let ownsLogin = AccountsSettingsInteractions.removalIsDestructive(for: row)
        let canReset = account.isBuiltIn && store.canResetBuiltInAccount(for: account.providerID)
            && source == .existingCLI
        let needsReset = if case .stale(let reason) = store.snapshot(for: row.key).freshness {
            reason.isPermanent
        } else {
            false
        }
        let merged = AccountsSettingsInteractions.mergedBuiltIn(for: account.providerID, in: store)
        let showsMerged = merged.map { store.displayProjection(for: account.providerID).mergeMap[$0.key] == row.key } ?? false
        return Menu {
            if AccountsSettingsInteractions.promotionState(for: row, in: store) == .available {
                Button("Make Main") { makeMain(account) }
            }
            if canReset && needsReset {
                Button("Sign Out & Set Up Again") { requestReset(account) }
            }
            if showsMerged, let merged {
                Button("Stop Tracking Default CLI") {
                    stopTracking(DisplayAccount(account: merged, kind: .engine))
                }
            }
            Button(AccountsSettingsInteractions.removalActionTitle(for: row), role: ownsLogin ? .destructive : nil) {
                if ownsLogin {
                    removalOrigin = row.key
                    removalCandidate = row
                } else {
                    stopTracking(row)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(SettingsType.help)
                .frame(width: 22, height: 22)
        }
        .accountActionsMenuChrome()
        .focused($focusedRemovalAction, equals: account.key)
        .accessibilityLabel("Actions for \(store.desktopAccountName(for: account))")
        .disabled(setupRowRecovery(for: setupState) == .sessionOnly && SetupSessions.hasActiveHandoff(for: account))
    }

    private func stopTracking(_ row: DisplayAccount) {
        commitLabel(for: row)
        Task { @MainActor in
            let result = await AccountsSettingsInteractions.stopTrackingSource(row, in: store)
            if result != .removed && result != .setupActive {
                sourceActionError = "Pacemark couldn’t stop tracking this source. Try again."
            }
        }
    }

    @ViewBuilder func removalRecovery(
        for row: DisplayAccount, removalState: AccountRemovalState?, setupState: SetupSessionState
    ) -> some View {
        let account = row.account
        if let stopWaitingAccount = settingsStopWaitingAccount(account, removalState: removalState, setupState: setupState) {
            StopWaitingButton(
                account: stopWaitingAccount,
                onConfirmationPresented: { removalOrigin = account.key },
                onStop: { AccountsSettingsInteractions.stopWaiting(for: $0, in: store) },
                onDismiss: restoreRemovalFocus
            )
        } else if removalState == .failed {
            Button("Retry") {
                Task { @MainActor in
                    _ = await AccountsSettingsInteractions.removeAccount(row, from: store)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Cancel") { store.cancelAccountRemoval(account.key) }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }
    /// Create the account and immediately open its official-CLI sign-in so the add
    /// flow is one gesture: click Add → Terminal opens → sign in → row goes live.
    func addAccount(for providerID: ProviderID) -> Bool {
        withAnimation(
            PacemarkMotion.resolved(PacemarkMotion.reorder, .movement, reduceMotion: reduceMotion)
        ) {
            AccountsSettingsInteractions.addAccount(
                for: providerID,
                to: store,
                openSetup: { account in
                    enableProvider(providerID)
                    openSetup(for: account)
                }
            ) != nil
        }
    }

    func openSetup(for account: ProviderAccount) {
        // Per-account retry: watching one sign-in must not re-probe the whole fleet
        // (each Claude account is a 20–30s CLI session — code-review finding).
        SetupSessions.openSetup(for: account, onRetry: { [store] in
            store.refreshAccountNow(account.key)
        })
    }
    private func requestReset(_ account: ProviderAccount) {
        removalOrigin = account.key
        resetCandidate = account
    }

    private func makeMain(_ account: ProviderAccount) {
        removalOrigin = account.key
        var feedback: AccountsSettingsInteractions.PromotionFeedback?
        withAnimation(
            PacemarkMotion.resolved(PacemarkMotion.reorder, .movement, reduceMotion: reduceMotion)
        ) {
            feedback = AccountsSettingsInteractions.makeMain(account, in: store)
        }
        guard let feedback else { return }
        Task { @MainActor in
            await Task.yield()
            focusedRemovalAction = feedback.accountKey
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: feedback.announcement,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }

    func restoreRemovalFocus() {
        let key = removalOrigin
        removalCandidate = nil
        resetCandidate = nil
        Task { @MainActor in
            await Task.yield()
            focusedRemovalAction = key
        }
    }
}
