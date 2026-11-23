#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import HeadroomCore

extension AccountsSettingsTile {
    func accountRow(
        _ row: DisplayAccount,
        showsBadge: Bool,
        lastReadAt: Date?,
        capability: CapabilityRecoveryPresentation?,
        presentation: AccountsSettingsInteractions.ProviderGroupPresentation
    ) -> some View {
        let account = row.account
        // A remembered row is never probed: no sign-in, retry or recovery action (R12).
        let offersRecovery = row.kind.offersRetry
        let snapshot = store.snapshot(for: account.key)
        let removalState = store.accountRemovalStates[account.key]
        let setupState = SetupSessions.state(for: account)
        let setupFailure = SetupSessions.failureMessage(for: account)
        let capabilityRow = AccountsSettingsInteractions.capabilityRowPresentation(
            snapshot: snapshot,
            capability: capability
        )
        // R11: fetch-recovery ("Check Again", "Install…", "Reconnect…") is fetch state,
        // so it goes with the status text while the provider is off; the plain sign-in
        // affordance below is management and stays.
        let recoveryActions = presentation.hidesFetchRecovery || !offersRecovery
            ? nil
            : settingsRecoveryActions(
                snapshot: snapshot,
                account: account,
                setupState: setupState
            )
        let status = AccountStatus(
            snapshot: snapshot,
            waiting: isWaitingForSetup(account),
            blocked: {
                if case .blockedByProviderLogin = setupState { return true }
                return false
            }(),
            blockedByOpenHandoff: setupState == .blockedByOpenHandoff,
            setupFailed: setupFailure != nil,
            removalState: removalState
        )
        let isEditingLabel = focusedLabel == account.key || hoveredLabel == account.key
        let loadingLevel = SettingsAccountLoadingState.displayedLevel(snapshot: store.appDisplaySnapshot(for: account.key),
            mode: store.usagePercentageMode, choice: store.menuBarWindowChoice(for: account.providerID))
        let email = accountEmail(from: snapshot)
        // R2C6: the row prints the *popover's* sentence for this state ("Sign in with the
        // official Claude CLI") rather than a Settings-only "Needs sign-in". One act, one
        // wording — and read from Core's `ProviderSetupOutcome`, never duplicated here.
        let setupSentence: String? = {
            guard case .stale(let reason) = snapshot.freshness else { return nil }
            return reason.providerSetupOutcome?.message
        }()
        let source = accountSource(for: row)
        let rawPlan = snapshot.exportedPlanLabel
        let showsCredits = account.providerID == .antigravity
            && (rawPlan?.hasSuffix(" credit") == true || rawPlan?.hasSuffix(" credits") == true)
        let plan = showsCredits ? nil : PlanLabelPresentation.displayName(rawPlan, provider: account.providerID)
        let planName = plan.map { value in
            let name = providerName(account.providerID)
            return value.localizedCaseInsensitiveContains(name) ? value : "\(name) \(value)"
        }
        let showsStatus = !presentation.hidesAccountStatus(isSetupState: status.isSetupState)
            && (status != .connected || capabilityRow != .standard)
        return VStack(alignment: .leading, spacing: 5) {
            AccountsColumns(showsBadge: showsBadge) {
                accountIdentity(row, email: email, path: source.path, isEditingLabel: isEditingLabel)
            } source: {
                metadataText(source.label)
            } plan: {
                metadataText(planName ?? "")
            } version: {
                Text(store.observedCLIVersions[row.key] ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } badge: {
                if let badge = store.menuBarBadge(for: row.key), !row.isRemembered {
                    AccountMenuBarBadgeField(value: badge, accountLabel: account.label) {
                        store.setMenuBarBadge($0, for: account.key)
                    }
                }
            } actions: {
                accountMenu(row, setupState: setupState)
            }
            if row.isRemembered {
                if let text = AccountsSettingsInteractions.rememberedStatus(
                    lastReadAt: lastReadAt, snapshot: snapshot, now: Date()
                ) {
                    rememberedStatusLabel(text)
                        .padding(.horizontal, 10)
                }
            } else if showsStatus || status.isSetupState || recoveryActions != nil {
                HStack(spacing: 6) {
                    SettingsAccountWaitPill(
                        store: store, account: account, status: status,
                        waitingForClaudeCode: capabilityRow == .waitingForClaudeCode,
                        showsStatus: showsStatus, level: loadingLevel
                    )
                    if showsStatus {
                        accountStatus(
                            capabilityRow, status: status, setupFailure: setupFailure,
                            setupSentence: setupSentence, account: account
                        )
                    }
                    Spacer(minLength: 4)
                    if removalState == nil, capability == nil {
                        recoveryButtons(
                            for: account, status: status, setupState: setupState,
                            recoveryActions: recoveryActions
                        )
                    }
                    removalRecovery(for: row, removalState: removalState, setupState: setupState)
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 8)
        .opacity(presentation.dimsAccountRows && !status.isSetupState ? 0.62 : 1)
        .disabled(removalState == .removing)
        .onAppear { SetupSessions.announceFailureIfNeeded(for: account) }
        .onChange(of: setupState) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    func accountSource(for row: DisplayAccount) -> (label: String, path: String?) {
        let account = row.account
        if let home = account.borrowedHome {
            return (home.source.isT3 ? "T3 Code" : "CLI", home.path.abbreviated(userHome: NSHomeDirectory()))
        }
        if row.isRemembered { return ("CLI", nil) }
        if !account.isBuiltIn {
            let path = AccountStorage.accountDirectoryURL(for: account).path
            return ("Separate", (path as NSString).abbreviatingWithTildeInPath)
        }
        if account.providerID == .antigravity, store.antigravitySourcePreference == .autoPreferT3,
           let path = t3Sources.antigravityPath {
            return ("T3 Code", path)
        }
        let path = AccountsSettingsInteractions.defaultCLIPath(for: account.providerID)
        let usesT3Claude = account.providerID == .claude && store.tracksT3Claude && t3Sources.claudeName != nil
        return (usesT3Claude ? "T3 Code" : "CLI", path)
    }

    private func metadataText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(value)
    }

    private func accountIdentity(
        _ row: DisplayAccount, email: String?, path: String?, isEditingLabel: Bool
    ) -> some View {
        let account = row.account
        let name = store.desktopAccountName(for: account)
        return VStack(alignment: .leading, spacing: 2) {
            if store.useEmailAsAccountName, let email {
                Text(email)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .help(email)
            } else {
                TextField("Account name", text: labelBinding(for: account))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($focusedLabel, equals: account.key)
                    .onSubmit { commitLabel(for: row); focusedLabel = nil }
                    .background(Color.primary.opacity(isEditingLabel ? 0.06 : 0),
                                in: RoundedRectangle(cornerRadius: 4))
                    .onHover { hovering in
                        hoveredLabel = hovering ? account.key : (hoveredLabel == account.key ? nil : hoveredLabel)
                    }
                    .help("Click to rename this account")
                    .accessibilityLabel("Account name for \(name)")
                if let email { metadataText(email) }
            }
            if let path {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            if let original = duplicateLoginLabels[account.key] {
                metadataText("Same login as \(original)")
            }
        }
    }

    /// U8: the stale status's clock-and-text treatment, worded "Last read …". Its tooltip
    /// points at Add Account for someone who wants the account live.
    private func rememberedStatusLabel(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .medium))
            Text(text)
                .font(SettingsType.help.monospacedDigit())
        }
        .foregroundStyle(.secondary)
        .help(AccountsSettingsInteractions.rememberedStatusHelp)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
    /// Nil for an account with no known address yet — a row can render before its first
    /// poll (or from a source without the claim), so the line collapses rather than
    /// holding a placeholder. Non-nil, not `.live`, is the gate: a stale row keeps the
    /// last-known address, which is exactly when "which login is this?" gets asked.
    private func accountEmail(from snapshot: UsageSnapshot) -> String? {
        guard let email = snapshot.accountEmail, !email.isEmpty else { return nil }
        return email
    }
    private func isWaitingForSetup(_ account: ProviderAccount) -> Bool {
        SetupSessions.isWaiting(for: account)
    }
}
