#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

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
        let enabled = !presentation.dimsAccountRows
        let expanded = enabled || expandedOffProviders.contains(providerID)
        SettingsLedgerTile(accountsProvider: displayName, provider: providerID) {
            if enabled {
                LedgerChip(text: AccountsSettingsInteractions.accountCounterText(usedSlots: accounts.count, capacity: capacity))
            } else {
                Button {
                    expandedOffProviders.formSymmetricDifference([providerID])
                } label: {
                    Label("Off · not read", systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(PopoverLedgerType.sentence)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityHint(expanded ? "Hide account management" : "Show account management")
            }
            if capacity > 1 {
                Button("Add source…") {
                    commitPendingLabels()
                    focusedLabel = nil
                    addSource = AccountSourceSheetRequest(id: providerID)
                }
                .buttonStyle(SetupChipButtonStyle(size: .small))
                .accessibilityLabel("Add \(displayName) source")
                .disabled(accounts.count >= capacity)
            }
            if let surface {
                subscriptionSwitch(surface, displayName: displayName, presentation: presentation.subscriptionSwitch)
            }
        } content: {
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
                .padding(.leading, PDS.Space.l)
                .transition(PacemarkMotion.fade(PacemarkMotion.settle, reduceMotion: reduceMotion))
            }
            if expanded {
                if rows.isEmpty {
                    SettingsLedgerHelp("No \(displayName) accounts. Use Add source… to track one.")
                        .padding(.vertical, PDS.Space.s)
                } else {
                    AccountsColumns {
                        SettingsTableHeading("Account").padding(.leading, MenuBarMeterGlyph.defaultSize + PDS.Space.xs)
                    } source: {
                        SettingsTableHeading("Source")
                    } plan: {
                        SettingsTableHeading("Plan")
                    } lastRead: {
                        SettingsTableHeading("Last read")
                    } actions: {
                        Color.clear.frame(height: 1).accessibilityHidden(true)
                    }
                    .frame(minHeight: 22)
                    .pdsTableStart()
                    ForEach(rows) { row in
                        accountRow(row, lastReadAt: lastReadAt[row.key], capability: capability,
                                   presentation: presentation)
                            .transition(SettingsAccountExit.transition(reduceMotion: reduceMotion))
                    }
                }
                AccountsProviderOptions(providerID: providerID, store: store)
            }
        }
        // M7A: the single scope for add / remove / Make Main. A row travels roughly its own
        // height, so the list rides the `reorder` spring — slower than `valueSpring`, and a
        // spring so a second Make Main mid-flight retargets instead of restarting. It is one
        // `.movement` scope on purpose: splitting the row's fade from the group's height
        // change is exactly what made the contraction land a beat late. Nothing between this
        // and the tile's `raisedTile` pins a height, so the tile follows the group per frame.
        .animation(
            PacemarkMotion.resolved(PacemarkMotion.reorder, .movement, reduceMotion: reduceMotion),
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
            .accessibilityIdentifier("accounts.\(displayName)")
            .controlSize(.small)
            .labelsHidden()
            .disabled(!presentation.isEnabled)
            .help(presentation.helpText ?? "Fetch \(displayName) usage")
            .accessibilityLabel(presentation.accessibilityLabel)
    }
}
