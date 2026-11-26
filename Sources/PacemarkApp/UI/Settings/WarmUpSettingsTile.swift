#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import PacemarkCore
import SwiftUI

struct WarmUpSettingsTile: View {
    let store: UsageStore

    @Environment(\.colorScheme) private var scheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = BenchCounters.hit("WarmUpSettingsTile")
        SettingsPaneScaffold("Warm-up", subtitle: "Choose which idle limits to start early.") {
            SettingsLedgerTile {
                PDSToggleRow(title: "Warm up idle limits", help: "Sends one tiny message to start an idle limit’s clock early, so it resets sooner. Uses a very small amount of your plan. Only at 0% used, at most once per account every 30 minutes and 4 times a day.\n\(WarmUpCapability.billingPeriodProviders.map(\.displayName).formatted(.list(type: .and))) use billing periods. Warm-up skips OpenCode.", isOn: Binding(
                    get: { store.warmUp.settings.isEnabled }, set: store.warmUp.setEnabled
                ))
                if store.warmUp.settings.isEnabled { activeHours }
                if store.warmUp.settings.isEnabled, store.warmUp.ledger == nil {
                    Label("Warm-up paused: attempt history could not be read.", systemImage: "exclamationmark.triangle")
                            .font(PopoverLedgerType.sentence)
                            .foregroundStyle(StatusSentenceSeverity.attention.ink(scheme: scheme))
                }
            }
            if store.warmUp.settings.isEnabled {
                ForEach(store.accountSettingsProviderOrder.filter { WarmUpCapability.forProvider($0) == .supported }, id: \.self) { provider in
                    let accounts = store.displayAccounts(for: provider).filter { !$0.isRemembered }.map(\.account)
                    PDSCard(provider.displayName, count: accounts.count, mark: {
                        ProviderLogoView(providerID: provider, size: PDS.Metrics.providerMark)
                    }, accessory: { EmptyView() }) {
                        accountTable(provider, accounts)
                        if provider == .antigravity {
                            SettingsLedgerHelp("A Gemini message starts only Gemini limits. Claude & GPT use a separate pool.")
                        }
                    }
                }
            }
        }
        .animation(PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion), value: store.warmUp.settings.isEnabled)
    }

    private var activeHours: some View {
        let hours = store.warmUp.settings.activeHours
        let anyTime = hours == .anyTime
        return PDSPickerRow("Active hours") {
            VStack(alignment: .trailing, spacing: PDS.Space.s) {
                Picker("Active hours", selection: Binding(get: { anyTime }, set: {
                    store.warmUp.setActiveHours($0 ? .anyTime : .standard)
                })) {
                    Text("Any time").tag(true)
                    Text("Set hours").tag(false)
                }.pdsSegmented().fixedSize()
                if case let .interval(start, end) = hours {
                    HStack(spacing: PDS.Space.s) {
                        timePicker("From", minute: start) {
                            store.warmUp.setActiveHours(.interval(startMinute: $0, endMinute: end))
                        }
                        timePicker("to", minute: end) {
                            store.warmUp.setActiveHours(.interval(startMinute: start, endMinute: $0))
                        }
                    }
                }
                if case let .interval(start, end) = hours, start == end {
                    SettingsLedgerHelp("Choose different start and end times, or turn on Any time.")
                        .padding(.bottom, LedgerMetrics.nameGap)
                }
            }
            .padding(.bottom, anyTime ? 0 : 2)
        }
    }

    private func timePicker(_ title: String, minute: Int, set: @escaping (Int) -> Void) -> some View {
        let calendar = Calendar.current
        // A fixed reference day keeps edits to wall-clock hours independent of DST today.
        let reference = calendar.date(from: DateComponents(year: 2001, month: 1, day: 15)) ?? .now
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: reference) ?? reference
        return HStack(spacing: PDS.Space.xs) {
            Text(title).font(PDS.Typography.body)
            WarmUpTimeField(title: title, selection: Binding(get: { date }, set: {
                set(calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0))
            }))
            .frame(width: 80)
        }
    }

    private let limitWidth = 4 * PDS.Space.l
    private let attemptWidth = 10 * PDS.Space.l

    private func accountTable(_ provider: ProviderID, _ accounts: [ProviderAccount]) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            HStack(spacing: LedgerMetrics.rowGap) {
                SettingsTableHeading("Account").pdsColumnGuide("pds.heading.text.account").padding(.leading, PDS.Metrics.providerMark + PDS.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SettingsTableHeading(provider == .antigravity && store.showsAntigravityOtherModels ? "Gemini 5h" : "5h").frame(width: limitWidth)
                SettingsTableHeading(provider == .antigravity && store.showsAntigravityOtherModels ? "Gemini weekly" : "Weekly").frame(width: limitWidth)
                SettingsTableHeading("Last attempt").pdsColumnGuide("pds.heading.text.attempt").frame(width: attemptWidth, alignment: .leading)
            }
            .padding(.vertical, PDS.Space.s)
            PDSTableRows(followsHeadings: true) {
                ForEach(accounts, id: \.key) { account in
                    accountRow(account).frame(height: PDS.Metrics.control + 2 * PDS.Space.s)
                }
            }
        }
    }

    private func accountRow(_ account: ProviderAccount) -> some View {
        let key = account.key
        let selections = store.warmUpSelections(for: key)
        let enabled = store.providerOrder.contains(account.providerID)
        let canEdit = enabled && store.canEditWarmUp(for: key)
        let title = store.desktopAccountName(for: account)
        let status = !enabled ? "Turned off in Accounts" : store.lastWarmUpAttempt(for: key).map(activity)
            ?? (canEdit ? "No attempts" : "Verification required")
        let reported = store.snapshot(for: key).windows.filter { !$0.freshness.isUnavailable }
        let available = WarmUpSettings.windows(for: key.providerID).filter { kind in reported.contains { $0.kind == kind } }
        return HStack(spacing: LedgerMetrics.rowGap) {
            HStack(spacing: LedgerMetrics.nameGap) {
                Text(title).font(PopoverLedgerType.name)
                    .foregroundStyle(enabled ? Color.primary : PDS.Ink.disabledText)
                    .lineLimit(1).pdsColumnGuide("pds.cell.text.account").help(title).padding(.leading, PDS.Metrics.providerMark + PDS.Space.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("\(account.providerID.displayName), \(title)")
            ForEach(WarmUpSettings.windows(for: key.providerID), id: \.persistentID) { kind in
                let label = AntigravityOtherModels.displayLabel(for: kind, showsOtherModels: store.showsAntigravityOtherModels) ?? kind.spokenName
                Group {
                    if available.contains(kind) {
                        Toggle(label, isOn: Binding(
                            get: { selections.contains { $0.windowID == kind.persistentID } },
                            set: { store.setWarmUpEnabled($0, for: key, window: kind) }
                        ))
                        .toggleStyle(.checkbox).labelsHidden()
                        .overlay {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(PDS.Ink.disabledText).allowsHitTesting(false)
                        }
                        .disabled(!canEdit)
                        .accessibilityLabel("\(account.providerID.displayName), \(title), \(label)")
                        .accessibilityIdentifier("warmUp.\(account.providerID.displayName).\(title).\(kind.spokenName)")
                    } else {
                        Text("—").foregroundStyle(PDS.Ink.inkTertiary)
                    }
                }.frame(width: limitWidth)
            }
            HStack(spacing: LedgerMetrics.nameGap) {
                Text(status)
                    .font(PopoverLedgerType.sentence)
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .pdsColumnGuide("pds.cell.text.attempt").help(status)
                if enabled, !canEdit, store.warmUp.settings.enabled.contains(where: { $0.account == key }) {
                    Button {
                        store.warmUp.turnOff(for: key)
                    } label: {
                        Label("Turn off warm-up", systemImage: "power").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Turn off warm-up")
                }
            }
            // Keep the header and last-attempt text aligned as individual statuses change.
            .frame(width: attemptWidth, alignment: .leading)
        }
    }

    private func activity(_ attempt: WarmUpLedger.Attempt) -> String {
        if store.warmUp.activeAttemptID == attempt.id { return "Warming…" }
        return switch attempt.outcome {
        case .reserved: "Interrupted"
        case .sent: "Started \(attempt.startedLimits ?? "limit") · \(attempt.startedAt.formatted(date: .omitted, time: .shortened))"
        case .failed(let reason): "Failed: \(reason.message)"
        case .skipped: "Skipped: no longer eligible"
        }
    }
}

private struct WarmUpTimeField: NSViewRepresentable {
    let title: String
    @Binding var selection: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let field = NSDatePicker()
        field.datePickerElements = .hourMinute
        field.datePickerStyle = .textField
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.isBezeled = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed(_:))
        field.setAccessibilityLabel(title)
        return field
    }

    func updateNSView(_ field: NSDatePicker, context: Context) {
        context.coordinator.selection = $selection
        if field.dateValue != selection { field.dateValue = selection }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    @MainActor final class Coordinator {
        var selection: Binding<Date>
        init(selection: Binding<Date>) { self.selection = selection }
        @objc func changed(_ sender: NSDatePicker) { selection.wrappedValue = sender.dateValue }
    }
}
