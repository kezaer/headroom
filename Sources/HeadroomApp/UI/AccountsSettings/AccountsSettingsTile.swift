#if SWIFT_PACKAGE
import HeadroomSharedUI
#endif
import SwiftUI
import AppKit
import Combine
import HeadroomCore

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

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    @State var addSource: AccountSourceSheetRequest?
    @State var t3Sources = SharedT3AccountSources()
    @State var sourceActionError: String?
    @State private var labelDrafts: [AccountKey: String] = [:]
    /// KTD8: a display row, so the confirmed removal follows the row's kind.
    @State var removalCandidate: DisplayAccount?
    @State var resetCandidate: ProviderAccount?
    @State var removalOrigin: AccountKey?
    @State private var removalInProgress: AccountKey?
    @State var hoveredLabel: AccountKey?
    @FocusState var focusedLabel: AccountKey?
    @FocusState var focusedRemovalAction: AccountKey?

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
    // MARK: - Rename plumbing

    func labelBinding(for account: ProviderAccount) -> Binding<String> {
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
    func commitPendingLabels() {
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

    func commitLabel(for row: DisplayAccount) {
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
}
