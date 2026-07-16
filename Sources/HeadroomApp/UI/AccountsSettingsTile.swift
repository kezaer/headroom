import SwiftUI
import AppKit
import HeadroomCore

/// Settings → Accounts (multi-account, Jul 2026): one tile managing every configured
/// subscription account. Grouped per provider — brand row with a live "n of 5" count
/// and an Add button, then one row per account: an editable label, a plain-language
/// status, and the account's actions (Sign in for a pending login, Remove for extras).
///
/// The built-in account is pinned and unremovable — it *is* the user's own CLI login —
/// so its row shows a quiet "CLI login" tag where extras get the trash affordance.
/// All sign-ins run through the official CLI in Terminal (compliance boundary
/// unchanged); this tile only opens that handoff and reflects the result.
struct AccountsSettingsTile: View {
    let store: UsageStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var labelDrafts: [AccountKey: String] = [:]
    @State private var removalCandidate: ProviderAccount?
    @FocusState private var focusedLabel: AccountKey?

    private static let providerIDs: [ProviderID] = [.claude, .codex]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts")
                .font(.system(size: 15, weight: .semibold))
                .kerning(-0.2)
            SettingsHelpText(text: "Track several subscriptions side by side. Every account signs in through its official CLI in Terminal — Headroom never sees your credentials.")

            ForEach(Array(Self.providerIDs.enumerated()), id: \.element) { index, providerID in
                if index > 0 {
                    Rectangle()
                        .fill(ClaudeSetupStyle.hairline(dark: colorScheme == .dark))
                        .frame(height: 1)
                        .padding(.vertical, 2)
                }
                providerGroup(providerID)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10, surface: .opaque)
        .confirmationDialog(
            "Remove this account?",
            isPresented: removalDialogPresented,
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { account in
            Button("Remove \(account.label)", role: .destructive) {
                withAnimation(reduceMotion ? nil : HeadroomMotion.settle) {
                    store.removeAccount(account.key)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text("Its sign-in on this Mac is deleted with it. Your subscription is untouched.")
        }
    }

    // MARK: - Provider group

    @ViewBuilder private func providerGroup(_ providerID: ProviderID) -> some View {
        let accounts = store.accounts(for: providerID)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    ProviderLogoView(providerID: providerID, size: 15)
                    Text(store.displayNames[providerID] ?? providerID.raw.capitalized)
                }
                Text("\(accounts.count) of \(AccountRegistry.maxPerProvider)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 12)
                Button("Add Account…") { addAccount(for: providerID) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!store.canAddAccount(for: providerID))
                    .help(store.canAddAccount(for: providerID)
                          ? "Sign in another account via the official CLI"
                          : "Up to \(AccountRegistry.maxPerProvider) accounts per provider")
            }
            ForEach(accounts) { account in
                accountRow(account)
            }
        }
        .animation(reduceMotion ? nil : HeadroomMotion.settle, value: accounts.map(\.id))
    }

    // MARK: - Account row

    private func accountRow(_ account: ProviderAccount) -> some View {
        let snapshot = store.snapshot(for: account.key)
        let status = AccountStatus(snapshot: snapshot, waiting: isWaitingForSetup(account))
        return HStack(spacing: 8) {
            TextField("Account name", text: labelBinding(for: account))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focusedLabel, equals: account.key)
                .onSubmit { commitLabel(for: account) }
                .frame(maxWidth: 150, alignment: .leading)
                .accessibilityLabel("\(account.label) account name")
            if account.isBuiltIn {
                Text("CLI login")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(ClaudeSetupStyle.stepBackground(dark: colorScheme == .dark), in: Capsule())
                    .help("Uses the account your CLI is signed into")
            }
            Spacer(minLength: 8)
            statusLabel(status)
            if status.needsSignIn {
                Button("Sign In…") { openSetup(for: account) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if !account.isBuiltIn {
                Button { removalCandidate = account } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
                .foregroundStyle(.secondary)
                .help("Remove this account")
                .accessibilityLabel("Remove \(account.label)")
            }
        }
        .padding(.leading, 22) // aligns rows under the provider name, past the logo
    }

    @ViewBuilder private func statusLabel(_ status: AccountStatus) -> some View {
        switch status {
        case .connected:
            Text("Connected")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .fetching:
            Text("Fetching…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        case .waiting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Waiting for sign-in…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .stale:
            Text("Stale")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .needsSignIn:
            Text("Needs sign-in")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: colorScheme))
        }
    }

    // MARK: - Status

    private enum AccountStatus {
        case connected, fetching, waiting, stale, needsSignIn

        init(snapshot: UsageSnapshot, waiting: Bool) {
            switch snapshot.freshness {
            case .live:
                self = .connected
            case .pending:
                self = .fetching
            case .stale(let reason):
                if reason.isPermanent {
                    self = waiting ? .waiting : .needsSignIn
                } else {
                    self = .stale
                }
            }
        }

        var needsSignIn: Bool {
            if case .needsSignIn = self { return true }
            return false
        }
    }

    // MARK: - Actions

    /// Create the account and immediately open its official-CLI sign-in so the add
    /// flow is one gesture: click Add → Terminal opens → sign in → row goes live.
    private func addAccount(for providerID: ProviderID) {
        guard let account = withAnimation(reduceMotion ? nil : HeadroomMotion.settle, {
            store.addAccount(for: providerID)
        }) else { return }
        openSetup(for: account)
    }

    private func openSetup(for account: ProviderAccount) {
        switch account.providerID {
        case .claude: ClaudeSetupSession.openSetup(for: account, onRetry: { store.refreshNow() })
        case .codex: CodexSetupSession.openSetup(for: account, onRetry: { store.refreshNow() })
        default: break
        }
    }

    private func isWaitingForSetup(_ account: ProviderAccount) -> Bool {
        switch account.providerID {
        case .claude: ClaudeSetupSession.openedSetupAt(for: account.id) != nil
        case .codex: CodexSetupSession.openedSetupAt(for: account.id) != nil
        default: false
        }
    }

    // MARK: - Rename plumbing

    private func labelBinding(for account: ProviderAccount) -> Binding<String> {
        Binding(
            get: { labelDrafts[account.key] ?? account.label },
            set: { labelDrafts[account.key] = $0 }
        )
    }

    private func commitLabel(for account: ProviderAccount) {
        guard let draft = labelDrafts[account.key] else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != account.label {
            store.renameAccount(account.key, to: trimmed)
        }
        labelDrafts[account.key] = nil
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(
            get: { removalCandidate != nil },
            set: { if !$0 { removalCandidate = nil } }
        )
    }
}
