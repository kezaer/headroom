import SwiftUI
import UsageBarCore

/// Settings pane (U8): poll interval, per-provider renewal dates (R4), and
/// launch-at-login (R15). Reached from the popover gear or a card's "not set"
/// affordance. Controls follow a sensible keyboard focus order (design review).
struct SettingsView: View {
    let store: UsageStore
    var preferences = Preferences()
    var launchControl: LaunchAtLoginControlling = LaunchAtLogin()

    @Environment(\.dismiss) private var dismiss
    @State private var intervalMinutes: Int = Preferences.defaultIntervalMinutes
    @State private var launchAtLogin = false
    @State private var renewalDates: [ProviderID: Date] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.title3.bold())

            Stepper("Refresh every \(intervalMinutes) min", value: $intervalMinutes, in: 1...60)
                .onChange(of: intervalMinutes) { _, newValue in
                    preferences.pollIntervalMinutes = newValue
                    store.reschedulePolling()
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
            intervalMinutes = preferences.pollIntervalMinutes
            launchAtLogin = launchControl.isEnabled
            for id in store.providerOrder {
                if let date = preferences.renewalDate(for: id) { renewalDates[id] = date }
            }
        }
    }
}
