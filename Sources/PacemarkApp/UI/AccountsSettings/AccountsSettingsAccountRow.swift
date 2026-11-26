#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import AppKit
import PacemarkCore

extension AccountsSettingsTile {
    func accountRow(
        _ row: DisplayAccount,
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
        let email = accountEmail(from: snapshot)
        // R2C6: the row prints the *popover's* sentence for this state ("Sign in with the
        // official Claude CLI") rather than a Settings-only "Needs sign-in". One act, one
        // wording — and read from Core's `ProviderSetupOutcome`, never duplicated here.
        let setupSentence: String? = {
            guard case .stale(let reason) = snapshot.freshness else { return nil }
            return reason.providerSetupOutcome?.message
        }()
        let source = accountSource(for: row)
        let plan = PlanLabelPresentation.displayName(snapshot.exportedPlanLabel, provider: account.providerID)
        let showsStatus = !presentation.hidesAccountStatus(isSetupState: status.isSetupState)
            && (status != .connected || capabilityRow != .standard)
        return VStack(alignment: .leading, spacing: PDS.Space.xs) {
            AccountsColumns {
                HStack(spacing: PDS.Space.xs) {
                    MenuBarMeterGlyph(meter: store.popoverMeter(for: row, at: fixtureDate ?? Date()), tuning: .defaults)
                    accountIdentity(row, email: email, path: email == nil ? source.path : nil, isEditingLabel: isEditingLabel)
                }
            } source: {
                VStack(alignment: .leading, spacing: PDS.Space.xs) {
                    Text(source.kind.rowLabel).font(PDS.Typography.body)
                    if let version = store.observedCLIVersions[row.key] {
                        Text(version).font(PopoverLedgerType.countdown)
                            .foregroundStyle(PDS.Ink.inkSecondary).lineLimit(1).help(version)
                    }
                }
            } plan: {
                if let plan {
                    LedgerChip(text: plan)
                }
            } lastRead: {
                lastReadCell(row, snapshot: snapshot, lastReadAt: lastReadAt, status: status,
                             hidesStatus: presentation.hidesAccountStatus(isSetupState: status.isSetupState))
            } actions: {
                accountMenu(row, source: source.kind, setupState: setupState)
            }
            if !row.isRemembered, showsStatus || status.isSetupState || recoveryActions != nil {
                HStack(spacing: PDS.Space.xs) {
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
            }
        }
        .frame(minHeight: 30)
        .padding(.vertical, PDS.Space.xs)
        .opacity(presentation.dimsAccountRows && !status.isSetupState ? 0.62 : 1)
        .disabled(removalState == .removing)
        .onAppear { SetupSessions.announceFailureIfNeeded(for: account) }
        .onChange(of: setupState) {
            SetupSessions.announceFailureIfNeeded(for: account)
        }
    }

    private func accountSource(for row: DisplayAccount) -> (kind: AccountSourceKind, path: String?) {
        let account = row.account
        if let home = account.borrowedHome {
            return (home.source.isT3 ? .t3Code : .externalCLI, home.path.abbreviated(userHome: NSHomeDirectory()))
        }
        if row.isRemembered { return (.existingCLI, nil) }
        if !account.isBuiltIn {
            let path = AccountStorage.accountDirectoryURL(for: account).path
            return (.separateLogin, (path as NSString).abbreviatingWithTildeInPath)
        }
        let kind = t3Sources.builtInSource(for: account.providerID, in: store)
        if account.providerID == .antigravity, kind == .t3Code {
            return (kind, t3Sources.antigravityPath)
        }
        return (kind, AccountsSettingsInteractions.defaultCLIPath(for: account.providerID))
    }

    private func metadataText(_ value: String) -> some View {
        Text(value)
            .font(PDS.Typography.secondary)
            .foregroundStyle(PDS.Ink.inkSecondary)
            .lineLimit(1)
            .help(value)
    }

    private func accountIdentity(
        _ row: DisplayAccount, email: String?, path: String?, isEditingLabel: Bool
    ) -> some View {
        let account = row.account
        let name = store.desktopAccountName(for: account)
        return VStack(alignment: .leading, spacing: PDS.Space.xs) {
            HStack(spacing: PDS.Space.xs) {
                if store.useEmailAsAccountName, let email {
                    Text(email)
                        .font(PopoverLedgerType.name)
                        .lineLimit(1)
                        .help(email)
                } else {
                    let label = labelBinding(for: account)
                    // Size the field to its single-line text so the state chip stays next to the name.
                    Text(label.wrappedValue.isEmpty ? "Account name" : label.wrappedValue)
                        .font(PopoverLedgerType.name)
                        .lineLimit(1)
                        .padding(.trailing, PDS.Space.xs)
                        .hidden()
                        .overlay(alignment: .leading) {
                            TextField("Account name", text: label)
                                .textFieldStyle(.plain)
                                .font(PopoverLedgerType.name)
                                .focused($focusedLabel, equals: account.key)
                                .onSubmit { commitLabel(for: row); focusedLabel = nil }
                                .background(Color.primary.opacity(isEditingLabel ? 0.06 : 0),
                                            in: RoundedRectangle(cornerRadius: 4))
                                .onHover { hovering in
                                    hoveredLabel = hovering ? account.key : (hoveredLabel == account.key ? nil : hoveredLabel)
                                }
                                .help("Click to rename this account")
                                .accessibilityLabel("Account name for \(name)")
                        }
                }
                if row.isRemembered {
                    LedgerChip(text: "Remembered", compact: true).fixedSize()
                } else if store.displayPrimaryKey(for: account.providerID) == account.key, account.label != "Main" {
                    LedgerChip(text: "Main", compact: true).fixedSize()
                }
            }
            if !store.useEmailAsAccountName, let email { metadataText(email) }
            if let path {
                Text(path)
                    .font(PDS.Typography.numberSmall)
                    .foregroundStyle(PDS.Ink.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            if let original = duplicateLoginLabels[account.key] {
                metadataText("Same login as \(original)")
            }
        }
    }

    @ViewBuilder
    private func lastReadCell(
        _ row: DisplayAccount, snapshot: UsageSnapshot, lastReadAt: Date?, status: AccountStatus, hidesStatus: Bool
    ) -> some View {
        if !row.isRemembered, !hidesStatus, status == .stale || status == .needsSignIn {
            LedgerChip(text: lastReadStatus(snapshot.freshness, status: status), outlined: true)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let readAt = row.isRemembered ? lastReadAt : snapshot.capturedAt
                Text(Countdown.updatedLabel(capturedAt: readAt, now: fixtureDate ?? context.date) ?? "—")
                    .font(PopoverLedgerType.countdown)
                    .foregroundStyle(PDS.Ink.inkSecondary)
                    .lineLimit(1)
                    .help(row.isRemembered ? AccountsSettingsInteractions.rememberedStatusHelp : "Last successful reading")
            }
        }
    }

    private func lastReadStatus(_ freshness: Freshness, status: AccountStatus) -> String {
        if status == .stale { return "Stale" }
        switch freshness {
        case .stale(.notLoggedIn), .stale(.needsReauth): return "Signed out"
        default: return "Needs action"
        }
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

private extension AccountSourceKind {
    var rowLabel: String {
        switch self {
        case .t3Code: "T3 Code"
        case .existingCLI, .externalCLI: "CLI"
        case .separateLogin: "Separate"
        }
    }
}
