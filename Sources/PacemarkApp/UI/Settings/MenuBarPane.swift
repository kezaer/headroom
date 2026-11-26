#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import PacemarkCore

struct MenuBarSettingsPane: View {
    let store: UsageStore
    var onOpenAccounts: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.loadingDate) private var pinnedDate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredAccount: AccountKey?
    private var controls = MenuBarMeterControls()

    var body: some View {
        let _ = BenchCounters.hit("MenuBarSettingsPane")
        let tuning = controls.tuning
        let date = pinnedDate ?? Date()
        SettingsPaneScaffold(SettingsPane.menuBar.label, subtitle: "Which accounts the menu bar shows, and how each meter looks.") {
            MenuBarPreviewStrip(
                meters: store.menuBarMeters(at: date),
                tuning: tuning, highlightedAccount: hoveredAccount, previewAppearance: pinnedDate == nil ? nil : scheme
            )
            MenuBarMeterTable(store: store, tuning: tuning, date: date, hoveredAccount: $hoveredAccount,
                              onOpenAccounts: onOpenAccounts)
            MenuBarStyleTile(controls: controls, showLabels: Binding(get: { store.showMenuBarLabels }, set: { store.showMenuBarLabels = $0 }))
        }
        .animation(PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion), value: store.showMenuBarLabels)
    }
}
