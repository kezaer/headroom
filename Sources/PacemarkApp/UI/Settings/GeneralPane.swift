#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

struct GeneralSettingsPane: View {
    @Binding var intervalMinutes: Int
    @Binding var launchAtLogin: Bool
    let softwareUpdates: SoftwareUpdateControlling
    let store: UsageStore
    let onIntervalChange: (Int) -> Void
    let onLaunchAtLoginChange: (Bool) -> Void

    @Environment(\.loadingDate) private var pinnedDate
    private var controls = MenuBarMeterControls()

    var body: some View {
        let _ = BenchCounters.hit("GeneralSettingsPane")
        let slower = PollCadencePresentation.effectiveIntervals(
            for: store.providerOrder, cadences: store.pollCadences
        )
        let subtitle = softwareUpdates.canCheckForUpdates ? "Refresh, startup and software updates."
            : "How often Pacemark reads, and when it starts."
        SettingsPaneScaffold(SettingsPane.general.label, subtitle: subtitle) {
            MenuBarMeterLegend(tuning: controls.tuning, date: pinnedDate ?? Date())
            SettingsLedgerTile("Background activity") {
                PDSRow {
                    VStack(alignment: .leading, spacing: PDS.Space.xs) {
                        Text("Refresh every").font(PDS.Typography.body)
                        if slower.isEmpty { SettingsLedgerHelp("Every account is read every \(intervalMinutes) min.") }
                    }
                } trailing: {
                    Picker("Refresh every", selection: $intervalMinutes) {
                        ForEach(1...60, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pdsFormPicker().fixedSize()
                    .accessibilityIdentifier("general.refreshInterval")
                    .onChange(of: intervalMinutes) { _, minutes in onIntervalChange(minutes) }
                }
                if !slower.isEmpty {
                    HStack {
                        SettingsCapsLabel("Provider")
                        Spacer()
                        SettingsCapsLabel("Effective interval")
                    }
                    .padding(.top, PDS.Space.xs)
                    .frame(minHeight: 24)
                    ForEach(slower, id: \.providerID) { row in
                        HStack(spacing: PDS.Space.xs) {
                            ProviderLogoView(providerID: row.providerID, size: 14)
                            Text(store.displayNames[row.providerID] ?? row.providerID.displayName)
                                .font(PDS.Typography.body)
                            Spacer()
                            Text("Every \(row.minutes) min")
                                .font(PopoverLedgerType.value)
                        }
                        .frame(minHeight: PDS.Metrics.row)
                    }
                    SettingsLedgerHelp("Providers read through a CLI take turns. When one has many accounts, each account is read less often than you chose.")
                        .padding(.vertical, PDS.Space.xs)
                }
                SettingsLedgerSwitch(title: "Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in onLaunchAtLoginChange(enabled) }
            }

            if softwareUpdates.canCheckForUpdates {
                SoftwareUpdatesTile(softwareUpdates: softwareUpdates)
            }
        }
    }
}

struct SoftwareUpdatesTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let softwareUpdates: SoftwareUpdateControlling
    private var automaticChecks: Binding<Bool> {
        Binding(
            get: { softwareUpdates.automaticallyChecksForUpdates },
            set: { softwareUpdates.automaticallyChecksForUpdates = $0 }
        )
    }

    private var automaticDownloads: Binding<Bool> {
        Binding(
            get: { softwareUpdates.automaticallyDownloadsUpdates },
            set: { softwareUpdates.automaticallyDownloadsUpdates = $0 }
        )
    }

    var body: some View {
        SettingsLedgerTile("Updates") {
            SettingsLedgerSwitch(title: "Automatically check for updates", isOn: automaticChecks)
            if softwareUpdates.automaticallyChecksForUpdates {
                SettingsLedgerSwitch(title: "Download and install updates automatically", help: "Installs when you quit Pacemark.", isOn: automaticDownloads)
                    .disabled(!softwareUpdates.allowsAutomaticUpdates)
            }

            checkRow.frame(minHeight: PDS.Metrics.row)
        }
        .animation(PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion), value: softwareUpdates.automaticallyChecksForUpdates)
    }

    private var checkRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: PDS.Space.m) {
            Button("Check for Updates…") {
                softwareUpdates.checkForUpdates()
            }
            .buttonStyle(SetupChipButtonStyle(size: .small))
            .controlSize(.small)
            .disabled(!softwareUpdates.presentation.canCheckForUpdates)
            Spacer(minLength: 12)
            // Sparkle's date isn't observable, so the line re-reads it on a slow tick and
            // picks up a check made while the pane is open.
            TimelineView(.periodic(from: .now, by: 15)) { _ in
                if let lastChecked = softwareUpdates.lastUpdateCheckDate {
                    Text("Last checked \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                        .font(SettingsType.help)
                        .foregroundStyle(PDS.Ink.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}
