#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import HeadroomCore

extension AccountsSettingsTile {
    @ViewBuilder func providerGroup(_ providerID: ProviderID) -> some View {
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

    func providerName(_ id: ProviderID) -> String {
        id == .copilot ? "GitHub Copilot" : store.displayNames[id] ?? id.displayName
    }

    func enableProvider(_ id: ProviderID) {
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
}
