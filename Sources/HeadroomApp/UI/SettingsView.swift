import SwiftUI
import HeadroomCore

/// Settings pane (U8): poll interval, per-provider renewal dates (R4), and
/// launch-at-login (R15). Presented in its own window so dismissing settings never
/// closes the menu bar popover behind it.
struct SettingsView: View {
    let store: UsageStore
    var preferences = Preferences()
    var launchControl: LaunchAtLoginControlling = LaunchAtLogin()

    @Environment(\.dismiss) private var dismiss
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var showMenuBarPercentage = false
    @State private var widgetsEnabled = true
    @State private var launchAtLogin = false
    @State private var renewalDates: [ProviderID: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title3.bold())

            VStack(alignment: .leading, spacing: 2) {
                Stepper("Refresh every \(intervalMinutes) min", value: $intervalMinutes, in: 2...60)
                    .onChange(of: intervalMinutes) { _, newValue in
                        preferences.pollIntervalMinutes = newValue
                        store.reschedulePolling()
                    }
                Text("Each Claude refresh runs a CLI session (~20–30s). Minimum 2 min.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Toggle("Show percentage in menu bar", isOn: $showMenuBarPercentage)
                .onChange(of: showMenuBarPercentage) { _, newValue in
                    store.setShowMenuBarPercentage(newValue)
                }

            WidgetSettingsSection(widgetsEnabled: $widgetsEnabled)
                .onChange(of: widgetsEnabled) { _, newValue in
                    store.setWidgetsEnabled(newValue)
                }

            Divider()

            ForEach(store.providerOrder, id: \.self) { id in
                DatePicker(
                    "\(store.displayNames[id] ?? id.raw) renews",
                    selection: Binding(
                        get: { renewalDates[id] ?? Date() },
                        set: { renewalDates[id] = $0; preferences.setRenewalDate($0, for: id) }
                    ),
                    displayedComponents: .date
                )
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    try? launchControl.setEnabled(newValue)
                }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            // Clamp any legacy sub-2-minute interval up to the new floor.
            let saved = max(2, preferences.pollIntervalMinutes)
            if saved != preferences.pollIntervalMinutes {
                preferences.pollIntervalMinutes = saved
                store.reschedulePolling()
            }
            intervalMinutes = saved
            showMenuBarPercentage = store.showMenuBarPercentage
            widgetsEnabled = store.widgetsEnabled
            launchAtLogin = launchControl.isEnabled
            for id in store.providerOrder {
                if let date = preferences.renewalDate(for: id) { renewalDates[id] = date }
            }
        }
    }
}
