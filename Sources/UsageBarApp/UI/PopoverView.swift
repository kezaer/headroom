import SwiftUI
import AppKit
import UsageBarCore

/// The Liquid Glass popover (U7). Composes one card per provider on a Tahoe glass
/// surface, a gear that opens Settings, and a Quit control (required — the app has no
/// Dock presence, KTD9). A `TimelineView` drives a per-minute `now` so countdowns and
/// "updated N min ago" tick without a data poll.
struct PopoverView: View {
    @Bindable var store: UsageStore
    var preferences = Preferences()
    @State private var showingSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 10) {
                header
                ForEach(store.providerOrder, id: \.self) { id in
                    ProviderCardView(
                        providerID: id,
                        displayName: store.displayNames[id] ?? id.raw,
                        snapshot: store.snapshot(for: id),
                        renewalDate: preferences.renewalDate(for: id),
                        now: context.date,
                        onOpenSettings: { showingSettings = true }
                    )
                }
                footer
            }
            .padding(14)
            .frame(width: 300)
            .background(.ultraThinMaterial)
            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, preferences: preferences)
        }
    }

    private var header: some View {
        HStack {
            Text("Usage").font(.headline)
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { store.refreshNow() }
                .buttonStyle(.plain)
                .font(.caption)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
