#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

struct APISpendSettingsPane: View {
    @Environment(\.colorScheme) private var linkScheme
    let store: UsageStore
    @Binding var apiSpendPeriod: APISpendPeriod
    @Binding var apiKeyDrafts: [APIKeyProvider: String]
    @Binding var replacingKeyProviders: Set<APIKeyProvider>
    @Binding var credentialMessages: [APIKeyProvider: String]
    let savedKeyProviders: Set<APIKeyProvider>
    let surfaceBinding: (UsageSurface) -> Binding<Bool>
    let onSaveKey: (String, APIKeyProvider) -> Void
    let onRequestRemoval: (APIKeyProvider) -> Void
    /// Cancels the root's pending auto-dismiss task for a provider's result message; the
    /// task itself stays on the root (KTD3) so a pane switch can't strand it.
    let cancelMessageDismissal: (APIKeyProvider) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = BenchCounters.hit("APISpendSettingsPane")
        SettingsPaneScaffold(SettingsPane.apiSpend.label, subtitle: "Read API costs and balances with your own keys.") {
            SettingsLedgerTile("Spending") {
                PDSPickerRow("Period") {
                    Picker("Period", selection: $apiSpendPeriod) {
                        ForEach(APISpendPeriod.allCases, id: \.self) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    .pdsSegmented()
                    .accessibilityIdentifier("apiSpend.period")
                    .fixedSize()
                    .onChange(of: apiSpendPeriod) { _, period in
                        store.setAPISpendPeriod(period)
                        store.refreshAPISpendNow()
                    }
                }
                ForEach(store.registeredAPISpendProviderOrder, id: \.self) { providerID in
                    if let provider = APIKeyProvider.allCases.first(where: { $0.providerID == providerID }),
                       let surface = UsageSurface.api(for: providerID) {
                        apiProviderTile(surface: surface, provider: provider)
                    }
                }
            }
        }
    }

    private func apiProviderTile(surface: UsageSurface, provider: APIKeyProvider) -> some View {
        let saved = savedKeyProviders.contains(provider)
        let replacing = replacingKeyProviders.contains(provider)

        return VStack(alignment: .leading, spacing: .zero) {
            HStack(spacing: PDS.Space.xs) {
                ProviderLogoView(providerID: surface.providerID, size: PDS.Metrics.providerMark)
                SettingsCapsLabel(provider.displayName)
            }
            .padding(.vertical, PDS.Space.s)
            PDSPickerRow("Track spending") {
                Toggle(surface.displayName, isOn: apiSurfaceBinding(surface, provider: provider))
                    .toggleStyle(.switch)
                    .controlSize(.regular)
                    .labelsHidden()
            }
            if store.isSurfaceEnabled(surface) {
                if saved { spendReadout(for: provider) }
                ZStack(alignment: .topLeading) {
                    if saved && !replacing {
                        configuredAPIKeyRow(provider: provider, title: provider.adminKeyTitle)
                            .transition(.settingsReveal(reduceMotion: reduceMotion))
                    } else {
                        apiKeyEditor(provider: provider, title: provider.adminKeyTitle,
                                     placeholder: provider.keyPlaceholder,
                                     text: apiKeyDraftBinding(for: provider), replacing: replacing)
                            .transition(.settingsReveal(reduceMotion: reduceMotion))
                    }
                }
                .padding(.vertical, PDS.Space.s)
            }
            if store.isSurfaceEnabled(surface), let message = credentialMessages[provider] {
                SettingsLedgerHelp(message)
                    .transition(.settingsReveal(reduceMotion: reduceMotion))
            }
        }
        .animation(
            PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion),
            value: store.isSurfaceEnabled(surface)
        )
        .animation(
            PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion),
            value: savedKeyProviders
        )
        .animation(
            PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion),
            value: replacingKeyProviders
        )
        .animation(
            PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion),
            value: credentialMessages
        )
    }

    private func spendReadout(for provider: APIKeyProvider) -> some View {
        let snapshot = store.apiSpendSnapshot(for: provider.providerID)
        let status = APISpendPresentation.rowStatus(
            freshness: snapshot.freshness, providerID: snapshot.providerID,
            displayName: snapshot.displayName, kind: snapshot.kind
        )
        let amount = APISpendPresentation.amountText(amount: snapshot.amount, currency: snapshot.currency)
        return HStack(alignment: .firstTextBaseline, spacing: PDS.Space.xs) {
            Text(amount ?? "—")
                .font(PopoverLedgerType.hero)
                .foregroundStyle(snapshot.freshness == .live ? .primary : .secondary)
            SettingsLedgerHelp(snapshot.kind == .balance ? "Credit balance" : snapshot.periodLabel)
            if let badge = status.shortBadge {
                LedgerChip(text: badge, outlined: true)
            }
            Spacer()
        }
        .frame(minHeight: 32)
        .help(status.message ?? "")
    }

    private func apiSurfaceBinding(_ surface: UsageSurface, provider: APIKeyProvider) -> Binding<Bool> {
        let binding = surfaceBinding(surface)
        return Binding(
            get: { binding.wrappedValue },
            set: { isEnabled in
                binding.wrappedValue = isEnabled
                if !isEnabled {
                    replacingKeyProviders.remove(provider)
                    clearField(for: provider)
                }
            }
        )
    }

    private func apiKeyDraftBinding(for provider: APIKeyProvider) -> Binding<String> {
        Binding(
            get: { apiKeyDrafts[provider, default: ""] },
            set: { apiKeyDrafts[provider] = $0 }
        )
    }

    private func clearField(for provider: APIKeyProvider) {
        apiKeyDrafts[provider] = ""
    }

    private func configuredAPIKeyRow(provider: APIKeyProvider, title: String) -> some View {
        HStack(spacing: PDS.Space.s) {
            LedgerChip(text: "\(title) saved", icon: "checkmark", outlined: true)
            Spacer(minLength: 8)
            Button("Replace key") {
                credentialMessages[provider] = nil
                cancelMessageDismissal(provider)
                replacingKeyProviders.insert(provider)
            }
            .buttonStyle(SetupChipButtonStyle(size: .small))
            CardRowGlyphButton(label: "Remove key", systemImage: "trash", accountLabel: nil) {
                onRequestRemoval(provider)
            }
        }
        .frame(minHeight: PDS.Metrics.row)
    }

    private func apiKeyEditor(
        provider: APIKeyProvider,
        title: String,
        placeholder: String,
        text: Binding<String>,
        replacing: Bool
    ) -> some View {
        // PA2: no engineering status in this copy. Two of these sentences reported the state
        // of our own implementation ("known request-format issue", "isn't live-verified yet")
        // at the exact moment the user is pasting an org-wide admin key — one of them already
        // false — and neither named an action. Real failures are reported on the row that
        // fails ("Anthropic didn't accept the saved admin key"), where they can be acted on.
        let guidance: (text: String, linkLabel: String, url: URL) = switch provider {
        case .anthropic:
            (
                "A regular API key can’t read organization spend. Use a dedicated admin key you can revoke on its own.",
                "Open Anthropic Console",
                URL(string: "https://platform.claude.com/settings/admin-keys")!
            )
        case .openAI:
            (
                "A regular API key can’t read organization spend. Use a dedicated admin key with the narrowest access, so you can revoke it by itself.",
                "Open OpenAI Platform",
                URL(string: "https://platform.openai.com/settings/organization/admin-keys")!
            )
        case .xAI:
            (
                "A regular API key can’t read team spend. Use a dedicated management key with only the ACLs it needs, so you can revoke it on its own.",
                "Open xAI Console",
                URL(string: "https://console.x.ai/team/default/settings/management-keys")!
            )
        }

        return VStack(alignment: .leading, spacing: PDS.Space.xs) {
            Text(title).font(SettingsType.help).foregroundStyle(PDS.Ink.inkSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PDS.Space.s) {
                    apiKeyField(provider: provider, placeholder: placeholder, text: text)
                    apiKeyEditorButtons(provider: provider, replacing: replacing, text: text)
                }

                VStack(alignment: .leading, spacing: PDS.Space.s) {
                    apiKeyField(provider: provider, placeholder: placeholder, text: text)
                    apiKeyEditorButtons(provider: provider, replacing: replacing, text: text)
                }
            }
            VStack(alignment: .leading, spacing: SettingsMetrics.labelToControl) {
                SettingsHelpText(text: guidance.text)
                Link(guidance.linkLabel, destination: guidance.url)
                    .foregroundStyle(PDS.Ink.link(linkScheme))
                    .font(SettingsType.help)
            }
        }
    }

    private func apiKeyField(provider: APIKeyProvider, placeholder: String, text: Binding<String>) -> some View {
        SecureField(provider.adminKeyTitle, text: text, prompt: Text(placeholder).foregroundStyle(PDS.Ink.inkSecondary))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 160)
            .onChange(of: text.wrappedValue) {
                credentialMessages[provider] = nil
                cancelMessageDismissal(provider)
            }
            // R13: Return commits the key, matching the Save button's own guard, so a
            // pasted key doesn't need a mouse trip.
            .onSubmit {
                guard Self.hasSavableKey(text.wrappedValue) else { return }
                onSaveKey(text.wrappedValue, provider)
            }
    }

    /// One rule for "there is a key to save", shared by Return and the Save button.
    private static func hasSavableKey(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The editor is used for both first save and intentional replacement. Removal
    /// stays in the configured summary so a replacement never presents three competing
    /// actions beside a secure field.
    private func apiKeyEditorButtons(
        provider: APIKeyProvider,
        replacing: Bool,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: PDS.Space.s) {
            Button(replacing ? "Update" : "Save") {
                onSaveKey(text.wrappedValue, provider)
            }
            .buttonStyle(SetupChipButtonStyle(size: .small))
            .disabled(!Self.hasSavableKey(text.wrappedValue))

            if replacing {
                Button("Cancel") {
                    clearField(for: provider)
                    credentialMessages[provider] = nil
                    cancelMessageDismissal(provider)
                    replacingKeyProviders.remove(provider)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(PDS.Ink.inkSecondary)
            }
        }
    }
}

extension APIKeyProvider {
    var adminKeyTitle: String {
        switch self {
        case .anthropic: return "Anthropic admin key"
        case .openAI: return "OpenAI admin key"
        case .xAI: return "xAI management key"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-admin…"
        case .openAI: return "sk-…"
        case .xAI: return "xai-…"
        }
    }
}
