#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import Combine
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

func accountLabelFieldValue(
    for account: ProviderAccount,
    draft: String?,
    focusedAccountKey: AccountKey?
) -> String {
    focusedAccountKey == account.key ? (draft ?? account.label) : account.label
}

func acceptsAccountLabelDraftChange(
    for accountKey: AccountKey,
    focusedAccountKey: AccountKey?
) -> Bool {
    focusedAccountKey == accountKey
}

struct AccountsSettingsTile: View {
    let store: UsageStore
    /// KTD3: resolved on the settings root so a pane switch neither blanks the badges nor
    /// re-reads every account's `.claude.json`.
    let duplicateLoginLabels: [AccountKey: String]
    /// R9: the provider group headers own the subscription switches, so the tile needs the
    /// root's surface binding (set + animate + provider-scoped due dispatch, KTD11) rather
    /// than a local toggle.
    let surfaceBinding: (UsageSurface) -> Binding<Bool>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var addSource: AccountSourceSheetRequest?
    @State private var t3Sources = SharedT3AccountSources()
    @State private var sourceActionError: String?
    @State private var labelDrafts: [AccountKey: String] = [:]
    /// KTD8: a display row, so the confirmed removal follows the row's kind.
    @State private var removalCandidate: DisplayAccount?
    @State private var resetCandidate: ProviderAccount?
    @State private var removalOrigin: AccountKey?
    @State private var removalInProgress: AccountKey?
    @State private var hoveredLabel: AccountKey?
    @FocusState private var focusedLabel: AccountKey?
    @FocusState private var focusedRemovalAction: AccountKey?

    private var providerOrder: [ProviderID] {
        let order: [ProviderID] = [.codex, .claude, .antigravity, .grok, .cursor, .copilot, .opencode]
        let available = store.accountSettingsProviderIDs
        return order.filter(available.contains) + store.registeredProviderOrder.filter { !order.contains($0) }
    }

    var body: some View {
        SettingsTile {
            SettingsHelpText(text: "Track several subscriptions side by side. Every account signs in through its official CLI in Terminal — Headroom never sees your credentials.")

            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsSwitchRow(
                    title: "Use email addresses as account names",
                    isOn: Binding(
                        get: { store.useEmailAsAccountName },
                        set: { enabled in
                            commitPendingLabels()
                            focusedLabel = nil
                            store.setUseEmailAsAccountName(enabled)
                        }
                    )
                )
                SettingsHelpText(text: "Applies to every account, in the Mac app and on a synced iPhone or iPad. Saved names return when turned off, and are used whenever an email is unavailable.")
            }

            Divider()
            ForEach(providerOrder, id: \.self) { providerID in
                providerGroup(providerID)
            }
        }
        .task { t3Sources = await SharedT3AccountSources.discover() }
        .sheet(item: $addSource) { request in
            AddAccountSourceSheet(
                providerID: request.id,
                displayName: providerName(request.id),
                store: store,
                t3Sources: $t3Sources,
                enableProvider: { enableProvider(request.id) },
                addSeparateLogin: { addAccount(for: request.id) }
            )
        }
        .alert("Couldn’t Stop Tracking", isPresented: Binding(
            get: { sourceActionError != nil },
            set: { if !$0 { sourceActionError = nil } }
        )) {
            Button("OK", role: .cancel) { sourceActionError = nil }
        } message: {
            Text(sourceActionError ?? "")
        }
        .confirmationDialog(
            removalCandidate.map(AccountsSettingsInteractions.removalDialogTitle(for:))
                ?? "Remove this account?",
            isPresented: removalDialogPresented,
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { row in
            let account = row.account
            // Stop-tracking is deliberately not `.destructive` — it hides the row and
            // deletes nothing, unlike extra-account removal. Removing a remembered row
            // only hides it too (R11).
            Button(
                AccountsSettingsInteractions.removalActionTitle(for: row),
                role: AccountsSettingsInteractions.removalIsDestructive(for: row) ? .destructive : nil
            ) {
                removalInProgress = account.key
                Task { @MainActor in
                    let result = await AccountsSettingsInteractions.removeAccount(row, from: store)
                    guard result == .removed else {
                        removalInProgress = nil
                        restoreRemovalFocus()
                        return
                    }
                    // KTD12: the store already detached the row. Its exit transition owns
                    // the drain; this transaction only settles the dialog bookkeeping.
                    withAnimation(
                        HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
                    ) {
                        removalInProgress = nil
                        removalCandidate = nil
                        removalOrigin = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { restoreRemovalFocus() }
        } message: { row in
            Text(AccountsSettingsInteractions.removalDialogMessage(for: row))
        }
        .confirmationDialog(
            "Sign out and set up again?",
            isPresented: resetDialogPresented,
            titleVisibility: .visible,
            presenting: resetCandidate
        ) { account in
            Button("Sign Out & Set Up Again") {
                // D7 (OpenCode plan): this dialog is the built-in warning for a reset, so the
                // start is already confirmed and must not ask a second time.
                _ = AccountsSettingsInteractions.resetBuiltIn(
                    account,
                    in: store,
                    beginReset: { SetupSessions.resetSetup(for: $0, confirmed: true) }
                )
                resetCandidate = nil
                restoreRemovalFocus()
            }
            Button("Cancel", role: .cancel) { restoreRemovalFocus() }
        } message: { account in
            Text(AccountsSettingsInteractions.resetDialogMessage(
                for: account,
                providerDisplayName: store.displayNames[account.providerID]
                    ?? account.providerID.raw.capitalized
            ))
        }
        // Commit a pending rename when the field loses focus — Enter-only commit
        // silently discarded renames while still displaying the draft (code-review
        // finding).
        .onChange(of: focusedLabel) { previous, _ in
            if let previous, let row = displayRow(for: previous) {
                commitLabel(for: row)
            }
        }
        // R12: leaving Accounts — pane switch or window close — commits a typed rename
        // instead of discarding it. Focus loss already commits, but ⌘W tears the tile
        // down without moving focus first.
        .onDisappear {
            commitPendingLabels()
            // R12 follow-up: SwiftUI restores focus to the last focused `TextField`, so
            // without this the renamed row reopened wearing its editing chrome while its
            // siblings looked static.
            focusedLabel = nil
        }
        // R12: `onDisappear` is not guaranteed on app termination, so ⌘Q with a focused,
        // uncommitted draft could still discard it. Same single commit path, one more trigger.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            commitPendingLabels()
        }
    }

    private func displayRow(for key: AccountKey) -> DisplayAccount? {
        store.displayProjection(for: key.providerID).row(for: key)
    }

    // MARK: - Provider group

    @ViewBuilder private func providerGroup(_ providerID: ProviderID) -> some View {
        // Engine rows drive capacity, the counter, the switch and capability recovery;
        // the list draws the display rows, remembered ones after the engine rows (KTD8).
        let accounts = store.accounts(for: providerID)
        let rows = store.displayAccounts(for: providerID)
        // U8: one read per provider, and only when a remembered row needs its last-read time.
        let lastReadAt: [AccountKey: Date] = rows.contains(where: \.isRemembered)
            ? Dictionary(
                store.rememberedAccounts(for: providerID).compactMap { summary in
                    summary.lastReadAt.map { (summary.key, $0) }
                },
                uniquingKeysWith: { first, _ in first }
            )
            : [:]
        let capacity = store.accountCapacity(for: providerID)
        let capabilityState = store.providerCapabilities[providerID]?.state
        let displayName = providerName(providerID)
        let surface = UsageSurface.subscription(for: providerID)
        let presentation = AccountsSettingsInteractions.providerGroupPresentation(
            providerDisplayName: displayName,
            accounts: accounts,
            isSurfaceEnabled: surface.map { store.isSurfaceEnabled($0) } ?? true
        )
        let allCapability = capabilityRecoveryPresentation(
            state: capabilityState,
            hasActiveSetupSession: accounts.contains(where: { SetupSessions.hasActiveHandoff(for: $0) })
        )
        // R11: a provider that isn't fetched has nothing to say about its fetch health.
        let capability = presentation.hidesCapabilityBanner ? nil : allCapability
        // R11: VoiceOver follows the banner. Announcing a hidden capability failure would
        // both speak state the screen doesn't show and burn the per-provider dedupe entry,
        // so the announcement would be lost once the provider is switched back on.
        let announcedCapability = presentation.hidesCapabilityBanner ? nil : capabilityState
        VStack(alignment: .leading, spacing: SettingsMetrics.withinGroup) {
            HStack(spacing: 7) {
                ProviderLogoView(providerID: providerID, size: 15)
                SettingsGroupLabel(displayName)
                Text(AccountsSettingsInteractions.accountCounterText(usedSlots: accounts.count, capacity: capacity))
                    .font(SettingsType.help.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 8)
                Button("+ Add Source…") {
                    commitPendingLabels()
                    focusedLabel = nil
                    addSource = AccountSourceSheetRequest(id: providerID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Add \(displayName) source")
                if let surface {
                    subscriptionSwitch(surface, displayName: displayName, presentation: presentation.subscriptionSwitch)
                }
            }
            if let capability, !accounts.isEmpty {
                // RM1: self-timed so it still fades under Reduce Motion.
                ProviderCapabilityRecoveryView(
                    presentation: capability,
                    stopWaitingAccount: accounts.first {
                        SetupSessions.hasActiveHandoff(for: $0)
                    },
                    // B3A: Settings keeps the leading row and the small chip; only the
                    // popover card foot takes P4C's trailing action row.
                    placement: .settingsGroup,
                    onPrimaryAction: {
                        AccountsSettingsInteractions.performCapabilityRecovery(
                            capability.recovery.primaryAction,
                            for: providerID,
                            in: store
                        )
                    },
                    onSecondaryAction: capability.recovery.secondaryAction.map { action in
                        {
                            AccountsSettingsInteractions.performCapabilityRecovery(
                                action,
                                for: providerID,
                                in: store
                            )
                        }
                    }
                )
                .padding(.leading, 16)
                .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
            let showsBadge = rows.count > 1
            VStack(spacing: 0) {
                if rows.isEmpty {
                    SettingsHelpText(text: "No \(displayName) accounts. Use Add Source… to track one.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                } else {
                    AccountsColumns(showsBadge: showsBadge) {
                        columnTitle("Account")
                    } source: {
                        columnTitle("Source")
                    } plan: {
                        columnTitle("Plan")
                    } version: {
                        columnTitle("Version")
                    } badge: {
                        columnTitle("Badge")
                    } actions: {
                        Color.clear.frame(height: 1).accessibilityHidden(true)
                    }
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.025))
                    ForEach(rows) { row in
                        Divider()
                        accountRow(
                            row, showsBadge: showsBadge, lastReadAt: lastReadAt[row.key],
                            capability: capability, presentation: presentation
                        )
                        .transition(SettingsAccountExit.transition(reduceMotion: reduceMotion))
                    }
                }
            }
            .accountSettingsInset(radius: 9)
            if let offHelpText = presentation.offHelpText {
                // R11: one line naming the only consequence of "off". Without it, an
                // account added while the surface is off would look broken rather than
                // simply unpolled (code-review finding).
                SettingsHelpText(text: offHelpText)
                    .transition(HeadroomMotion.fade(HeadroomMotion.settle, reduceMotion: reduceMotion))
            }
        }
        // M7A: the single scope for add / remove / Make Main. A row travels roughly its own
        // height, so the list rides the `reorder` spring — slower than `valueSpring`, and a
        // spring so a second Make Main mid-flight retargets instead of restarting. It is one
        // `.movement` scope on purpose: splitting the row's fade from the group's height
        // change is exactly what made the contraction land a beat late. Nothing between this
        // and the tile's `raisedTile` pins a height, so the tile follows the group per frame.
        .animation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion),
            value: rows.map(\.id)
        )
        .onAppear {
            SetupSessions.announceCapabilityIfNeeded(announcedCapability, for: providerID)
        }
        .onChange(of: capabilityState) {
            SetupSessions.announceCapabilityIfNeeded(announcedCapability, for: providerID)
        }
    }

    private func providerName(_ id: ProviderID) -> String {
        id == .copilot ? "GitHub Copilot" : store.displayNames[id] ?? id.displayName
    }

    private func enableProvider(_ id: ProviderID) {
        guard let surface = UsageSurface.subscription(for: id), !store.isSurfaceEnabled(surface) else { return }
        surfaceBinding(surface).wrappedValue = true
    }

    private func columnTitle(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// R9/R10: the provider's on/off switch now sits with the accounts it governs. Its
    /// binding is the root's (`setSurfaceEnabled` inside the settle animation, then a
    /// refresh), so turning a provider on fetches it immediately.
    private func subscriptionSwitch(
        _ surface: UsageSurface,
        displayName: String,
        presentation: AccountsSettingsInteractions.SubscriptionSwitchPresentation
    ) -> some View {
        Toggle(displayName, isOn: surfaceBinding(surface))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(!presentation.isEnabled)
            .help(presentation.helpText ?? "Fetch \(displayName) usage")
            .accessibilityLabel(presentation.accessibilityLabel)
    }

    // MARK: - Account row

    private func accountRow(
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

    private func accountSource(for row: DisplayAccount) -> (label: String, path: String?) {
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

    @ViewBuilder private func accountStatus(
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

    @ViewBuilder private func recoveryButtons(
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

    private func accountMenu(_ row: DisplayAccount, setupState: SetupSessionState) -> some View {
        let account = row.account
        let ownsLogin = AccountsSettingsInteractions.removalIsDestructive(for: row)
        let canReset = account.isBuiltIn && store.canResetBuiltInAccount(for: account.providerID)
            && accountSource(for: row).label == "CLI"
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
                sourceActionError = "Headroom couldn’t stop tracking this source. Try again."
            }
        }
    }

    @ViewBuilder private func removalRecovery(
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

    /// Nil for an account with no known address yet — a row can render before its first
    /// poll (or from a source without the claim), so the line collapses rather than
    /// holding a placeholder. Non-nil, not `.live`, is the gate: a stale row keeps the
    /// last-known address, which is exactly when "which login is this?" gets asked.
    private func accountEmail(from snapshot: UsageSnapshot) -> String? {
        guard let email = snapshot.accountEmail, !email.isEmpty else { return nil }
        return email
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

    // MARK: - Actions

    /// Create the account and immediately open its official-CLI sign-in so the add
    /// flow is one gesture: click Add → Terminal opens → sign in → row goes live.
    private func addAccount(for providerID: ProviderID) -> Bool {
        withAnimation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
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

    private func openSetup(for account: ProviderAccount) {
        // Per-account retry: watching one sign-in must not re-probe the whole fleet
        // (each Claude account is a 20–30s CLI session — code-review finding).
        SetupSessions.openSetup(for: account, onRetry: { [store] in
            store.refreshAccountNow(account.key)
        })
    }

    private func isWaitingForSetup(_ account: ProviderAccount) -> Bool {
        SetupSessions.isWaiting(for: account)
    }

    // MARK: - Rename plumbing

    private func labelBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: {
                accountLabelFieldValue(
                    for: account,
                    draft: labelDrafts[account.key],
                    focusedAccountKey: focusedLabel
                )
            },
            set: { value in
                guard acceptsAccountLabelDraftChange(
                    for: account.key,
                    focusedAccountKey: focusedLabel
                ) else { return }
                labelDrafts[account.key] = value
            }
        )
    }

    /// R12: the ⌘W / pane-switch backstop for focus-loss commit.
    private func commitPendingLabels() {
        guard !labelDrafts.isEmpty else { return }
        for providerID in providerOrder {
            for row in AccountsSettingsInteractions.pendingLabelCommits(
                drafts: labelDrafts,
                rows: store.displayAccounts(for: providerID)
            ) {
                commitLabel(for: row)
            }
        }
        labelDrafts.removeAll()
    }

    private func commitLabel(for row: DisplayAccount) {
        guard let draft = labelDrafts[row.key] else { return }
        AccountsSettingsInteractions.commitLabel(draft, for: row, in: store)
        labelDrafts[row.key] = nil
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: {
                if !$0 {
                    removalCandidate = nil
                    if removalInProgress == nil { restoreRemovalFocus() }
                }
            }
        )
    }

    private var resetDialogPresented: Binding<Bool> {
        Binding(
            get: { resetCandidate != nil },
            set: {
                if !$0 {
                    resetCandidate = nil
                    restoreRemovalFocus()
                }
            }
        )
    }

    private func requestReset(_ account: ProviderAccount) {
        removalOrigin = account.key
        resetCandidate = account
    }

    private func makeMain(_ account: ProviderAccount) {
        removalOrigin = account.key
        var feedback: AccountsSettingsInteractions.PromotionFeedback?
        withAnimation(
            HeadroomMotion.resolved(HeadroomMotion.reorder, .movement, reduceMotion: reduceMotion)
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

    private func restoreRemovalFocus() {
        let key = removalOrigin
        removalCandidate = nil
        resetCandidate = nil
        Task { @MainActor in
            await Task.yield()
            focusedRemovalAction = key
        }
    }
}

private struct AccountMenuBarBadgeField: View {
    let value: String
    let accountLabel: String
    let onCommit: (String?) -> Void
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        TextField("Badge", text: $draft)
            .font(SettingsType.help.monospaced())
            .multilineTextAlignment(.center)
            .frame(width: 36)
            .controlSize(.small)
            .focused($editing)
            .help("Menu bar badge. Clear it to use the account’s default.")
            .accessibilityLabel("Menu bar badge for \(accountLabel)")
            .onAppear { draft = value }
            .onChange(of: value) { _, value in if !editing { draft = value } }
            .onChange(of: editing) { _, editing in if !editing { commit() } }
            .onSubmit { editing = false }
            .onDisappear { if editing { commit() } }
    }

    private func commit() {
        let edited = MenuBarAccountBadge.sanitize(draft)
        if edited != value { onCommit(edited) }
        draft = edited ?? value
    }
}

private extension View {
    /// R2C21: one control language in the Accounts action column. The `•••` menus get the
    /// same chrome as the `arrow.clockwise` and `trash` glyphs beside them — `.button` menu
    /// style routed through `HoverButtonStyle`, so one hover pill, one press, and one ~38pt
    /// target serve all three. `.borderlessButton` gave the menus no hover, no press, a bare
    /// 22pt target, and an AppKit `⌄` the glyph set has nowhere else.
    func accountActionsMenuChrome() -> some View {
        self
            .menuStyle(.button)
            .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
            .foregroundStyle(.secondary)
            .menuIndicator(.hidden)
            .fixedSize()
    }
}

private struct AccountsColumns<Identity: View, Source: View, Plan: View, Version: View, Badge: View, Actions: View>: View {
    let showsBadge: Bool
    @ViewBuilder let identity: () -> Identity
    @ViewBuilder let source: () -> Source
    @ViewBuilder let plan: () -> Plan
    @ViewBuilder let version: () -> Version
    @ViewBuilder let badge: () -> Badge
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 7) {
            identity().frame(maxWidth: .infinity, alignment: .leading)
            source().frame(width: 47, alignment: .leading)
            plan().frame(width: 102, alignment: .leading)
            version()
                .frame(width: 64, alignment: .leading)
                .padding(.trailing, showsBadge ? 0 : 43)
            if showsBadge {
                badge().frame(width: 36)
            }
            actions().frame(width: 26)
        }
        .padding(.horizontal, 10)
    }
}

private struct AccountSourceSheetRequest: Identifiable {
    let id: ProviderID
}

private struct SharedT3AccountSources: Sendable {
    var claudeName: String?
    var antigravityPath: String?

    @MainActor static func discover() async -> Self {
        if let capture = AppComposition.capturedDemo {
            return Self(claudeName: capture.hasT3Claude ? "Claude" : nil,
                        antigravityPath: capture.hasT3Antigravity ? "/demo-capture/antigravity" : nil)
        }
        guard !AppComposition.usesInertAntigravity() else { return Self() }
        return await Task.detached(priority: .utility) {
            let installation = T3Installation()
            let antigravity = installation.antigravity().map {
                ($0.dataDirectory.path as NSString).abbreviatingWithTildeInPath
            }
            return Self(claudeName: installation.claudeInstanceName(), antigravityPath: antigravity)
        }.value
    }
}

private struct AddAccountSourceSheet: View {
    private enum Step { case choose, t3, cli, separate }
    @Environment(\.dismiss) private var dismiss
    let providerID: ProviderID
    let displayName: String
    let store: UsageStore
    @Binding var t3Sources: SharedT3AccountSources
    let enableProvider: () -> Void
    let addSeparateLogin: () -> Bool
    @State private var step = Step.choose
    @State private var status: String?
    @State private var busy = false
    @State private var folderPath = ""
    @State private var folderLabel = ""

    private var defaultPath: String { AccountsSettingsInteractions.defaultCLIPath(for: providerID) ?? "" }
    private var builtIn: ProviderAccount? { store.accounts(for: providerID).first(where: \.isBuiltIn) }
    private var showsT3: Bool { [.codex, .claude, .antigravity].contains(providerID) }
    private var sharesBuiltIn: Bool { providerID == .claude || providerID == .antigravity }
    private var tracksSharedT3: Bool {
        if providerID == .claude { return store.tracksT3Claude && t3Sources.claudeName != nil }
        return providerID == .antigravity && store.antigravitySourcePreference == .autoPreferT3 && t3Sources.antigravityPath != nil
    }
    private var tracksDefault: Bool { builtIn != nil && !tracksSharedT3 }
    private var canChangeBuiltIn: Bool {
        builtIn.map { !SetupSessions.hasActiveHandoff(for: $0) } ?? true
    }
    private var title: String {
        switch step {
        case .choose: "Add \(displayName) source"
        case .t3: "T3 Code · \(displayName)"
        case .cli: "Existing CLI · \(displayName)"
        case .separate: "Separate \(displayName) login"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if step != .choose {
                Button {
                    navigate(to: .choose)
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(busy)
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            switch step {
            case .choose: choices
            case .t3: t3Selector
            case .cli: existingCLI
            case .separate: separateLogin
            }
            if let status {
                SettingsHelpText(text: status)
            }
            footer
        }
        .padding(18)
        .frame(width: 390)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsHelpText(text: "Choose where Headroom should read \(displayName) usage from.")
            VStack(spacing: 0) {
                if showsT3 {
                    choice("T3 Code", detail: "Choose from discovered T3 Code logins", icon: "macwindow", destination: .t3)
                    Divider()
                }
                choice("Existing CLI", detail: "Default \(defaultPath) or another CLI folder", icon: "folder", destination: .cli)
                Divider()
                choice("Separate login", detail: "Sign in to a Headroom-managed home via CLI", icon: "terminal", destination: .separate)
            }
            .accountSettingsInset(radius: 10)
        }
    }

    private func choice(_ title: String, detail: String, icon: String, destination: Step) -> some View {
        Button {
            navigate(to: destination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 28, height: 28)
                    .accountSettingsInset(radius: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    SettingsHelpText(text: detail)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountSourceOptionStyle())
    }

    private var t3Selector: some View {
        let homes = providerID == .codex ? store.discoveredT3CodexAccounts() : []
        return VStack(alignment: .leading, spacing: 10) {
            SettingsHelpText(text: "Select a T3 Code login to start or stop tracking it.")
            let catalog =
                VStack(spacing: 0) {
                    if providerID == .codex, !homes.isEmpty {
                        ForEach(homes) { account in
                            if account.id != homes.first?.id { Divider() }
                            let tracked = store.accounts(for: .codex).contains { $0.key == account.key }
                            let path = account.borrowedHome?.path.abbreviated(userHome: NSHomeDirectory()) ?? ""
                            let plan = PlanLabelPresentation.displayName(store.snapshot(for: account.key).planLabel, provider: .codex)
                            trackingChoice(plan.map { "\(account.label) · Codex \($0)" } ?? account.label,
                                           path: path, tracked: tracked) {
                                toggleT3Codex(account, tracked: tracked)
                            }
                            .disabled(busy || (!tracked && !store.canAddAccount(for: .codex)))
                        }
                    } else if providerID == .claude, let name = t3Sources.claudeName {
                        sharedT3Choice(name, path: defaultPath)
                    } else if providerID == .antigravity, let path = t3Sources.antigravityPath {
                        sharedT3Choice("Antigravity", path: path)
                    } else {
                        SettingsHelpText(text: "No T3 Code \(displayName) logins found.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                }
            if providerID == .codex, homes.count > 5 {
                ScrollView { catalog }
                    .frame(height: 250)
                    .accountSettingsInset(radius: 10)
            } else {
                catalog.accountSettingsInset(radius: 10)
            }
            if providerID == .claude, t3Sources.claudeName != nil {
                SettingsHelpText(text: "T3 Code and Terminal share the same ~/.claude login.")
            }
        }
    }

    private func sharedT3Choice(_ name: String, path: String) -> some View {
        trackingChoice(name, path: path, tracked: builtIn != nil && tracksSharedT3) {
            if tracksSharedT3, let builtIn {
                stop(builtIn)
            } else {
                activateBuiltIn(useT3: true)
            }
        }
        .disabled(busy || !canChangeBuiltIn)
    }

    private var existingCLI: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsHelpText(text: "Track an existing CLI login without signing in again.")
            trackingChoice("Default CLI", path: defaultPath, tracked: tracksDefault) {
                if tracksDefault, let builtIn {
                    stop(builtIn)
                } else {
                    activateBuiltIn(useT3: false)
                }
            }
            .disabled(busy || !canChangeBuiltIn)
            .accountSettingsInset(radius: 10)

            Text("Or track another CLI config folder")
                .font(SettingsType.help)
                .foregroundStyle(.secondary)
            HStack {
                TextField("~/path/to/config-home", text: $folderPath)
                    .accessibilityLabel("CLI config folder path")
                    .onChange(of: folderPath) { status = nil }
                Button("Choose Folder…", action: chooseFolder)
            }
            TextField("Label (optional)", text: $folderLabel)
            if providerID != .codex {
                SettingsHelpText(text: "Headroom supports only the default \(displayName) CLI folder here.")
            } else if !store.canAddAccount(for: providerID) {
                SettingsHelpText(text: "Stop tracking an account to add another folder.")
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func trackingChoice(_ title: String, path: String, tracked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
                Spacer(minLength: 4)
                Text(tracked ? "Tracking ✓" : "Add")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tracked ? Color.green : Color.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tracked ? Color.green.opacity(0.12) : Color.primary.opacity(0.07), in: Capsule())
                    .fixedSize()
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(AccountSourceOptionStyle())
        .accessibilityHint(tracked ? "Stop tracking this login" : "Track this login")
    }

    private var separateLogin: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.accountCapacity(for: providerID) == 1 {
                SettingsHelpText(text: "\(displayName) supports one CLI account. Use Existing CLI to track that login.")
            } else if !store.canAddAccount(for: providerID) {
                SettingsHelpText(text: "Stop tracking an account to make room for a separate login.")
            } else {
                SettingsHelpText(text: "Headroom creates an isolated config home and opens Terminal so you can sign in through the official \(displayName) CLI.")
                if let note = AccountsSettingsInteractions.providerGroupNote(for: providerID) {
                    SettingsHelpText(text: note)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if step == .t3 {
                Button("Rescan", systemImage: "arrow.clockwise", action: rescan).disabled(busy)
            }
            Spacer()
            if step == .t3 {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if step == .cli {
                Button("Done", role: .cancel) { dismiss() }
                Button("Add Folder", action: addFolder)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || providerID != .codex || !store.canAddAccount(for: providerID)
                              || folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                if step == .separate, store.accountCapacity(for: providerID) > 1, store.canAddAccount(for: providerID) {
                    Button("Add Separate Login") {
                        if addSeparateLogin() { dismiss() }
                        else { status = "Headroom couldn’t create a separate login. Try again." }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func navigate(to destination: Step) {
        status = nil
        step = destination
    }

    private func rescan() {
        if store.isReplayingDemoCapture {
            status = "Using captured T3 Code logins."
            return
        }
        busy = true
        Task { @MainActor in
            let summary = providerID == .codex ? store.rescanBorrowedHomes() : nil
            t3Sources = await SharedT3AccountSources.discover()
            busy = false
            if let summary, !summary.read {
                status = "Couldn’t read T3 Code settings. Kept your current accounts."
            } else {
                status = "Rescanned T3 Code settings."
            }
        }
    }

    private func toggleT3Codex(_ account: ProviderAccount, tracked: Bool) {
        if tracked {
            stop(account)
        } else if store.restoreBorrowedAccount(account.key) {
            enableProvider()
            store.refreshAccountNow(account.key)
            status = nil
        } else {
            status = BorrowedHomeRejection.atCapacity.message
        }
    }

    private func activateBuiltIn(useT3: Bool) {
        guard canChangeBuiltIn else { return }
        if sharesBuiltIn {
            if providerID == .claude { store.setTracksT3Claude(useT3) }
            else { store.setAntigravitySourcePreference(useT3 ? .autoPreferT3 : .systemCLI) }
        }
        if providerID == .codex {
            store.setTracksCLIDefaultAlongsideT3(true)
        } else if builtIn == nil {
            store.resumeTrackingBuiltInAccount(for: providerID)
        }
        guard let builtIn else {
            status = "Headroom couldn’t start tracking this login."
            return
        }
        enableProvider()
        store.refreshAccountNow(builtIn.key)
        status = nil
    }

    private func stop(_ account: ProviderAccount) {
        busy = true
        Task { @MainActor in
            let row = DisplayAccount(account: account, kind: .engine)
            let result = await AccountsSettingsInteractions.stopTrackingSource(row, in: store)
            busy = false
            switch result {
            case .removed: status = nil
            case .setupActive: status = "Finish or stop the sign-in in progress, then try again."
            default: status = "Headroom couldn’t stop tracking this source. Try again."
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose Folder"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    private func addFolder() {
        let path = (folderPath.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else {
            status = "Enter an absolute path or choose a folder."
            return
        }
        switch store.addExternalCodexHome(at: URL(fileURLWithPath: path, isDirectory: true), label: folderLabel) {
        case .success(let account):
            enableProvider()
            store.refreshAccountNow(account.key)
            dismiss()
        case .failure(let reason):
            status = reason.message
        }
    }
}

private struct AccountSourceOptionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(isEnabled && (hovering || configuration.isPressed) ? 0.06 : 0))
            .opacity(isEnabled ? 1 : 0.55)
            .onHover { hovering = $0 }
    }
}

private extension View {
    func accountSettingsInset(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(Color.primary.opacity(0.035), in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.primary.opacity(0.13), lineWidth: 1).allowsHitTesting(false) }
    }
}
