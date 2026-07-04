import SwiftUI
import AppKit
import HeadroomCore

/// The Liquid Glass popover (U7). Composes one card per provider on a Tahoe glass
/// surface, a gear that opens Settings, and a Quit control (required — the app has no
/// Dock presence, KTD9). A `TimelineView` drives a per-minute `now` so countdowns and
/// "updated N min ago" tick without a data poll.
struct PopoverView: View {
    var store: UsageStore
    var preferences = Preferences()
    var onClose: () -> Void = {}
    var onOpenSettings: () -> Void

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
                        onOpenSettings: openSettingsDismissingPopover
                    )
                }
                APISpendSectionView(store: store, now: context.date, onOpenSettings: openSettingsDismissingPopover)
                footer
            }
            .padding(14)
            .frame(width: 320)
            .background(.ultraThinMaterial)
            .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// Native pattern: navigating out of the transient menu-bar popover into the persistent
    /// Settings window dismisses the popover (mirrors Control Center → System Settings).
    private func openSettingsDismissingPopover() {
        onClose()
        onOpenSettings()
    }

    private var header: some View {
        HStack {
            Text("Usage").font(.headline)
            Spacer()
            Button(action: openSettingsDismissingPopover) {
                Image(systemName: "gearshape").foregroundStyle(.secondary)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 5, verticalPadding: 5))
            .accessibilityLabel("Settings")
        }
    }

    /// Left slot shows a live "Refreshing…" state while a cycle is in flight (UI-02) —
    /// a manual refresh spawns a 20–30s Claude session, so without this the button reads
    /// as broken. The spinner is bound to real work, not decorative motion.
    private var footer: some View {
        HStack {
            if store.isRefreshing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityLabel("Refreshing usage")
            } else {
                Button("Refresh") { store.refreshNow() }
                    .buttonStyle(HoverButtonStyle())
                    .font(.caption)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(HoverButtonStyle())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
