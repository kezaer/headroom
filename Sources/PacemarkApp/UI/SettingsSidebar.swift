#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import SwiftUI
import PacemarkCore

/// Sidebar column of the Settings window (R1/R3): identity block on top, then the
/// destinations in their sections. Order and section membership are read straight off
/// `SettingsPane`, so there is no second list to keep in sync.
///
/// KTD1: the list is a value-driven `List(selection:)`, never `NavigationLink(destination:)`
/// — the latter leaves the detail column blank on the first selection on macOS 15.
struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?
    let softwareUpdates: SoftwareUpdateControlling

    @Environment(\.controlActiveState) private var controlState
    @Environment(\.colorScheme) private var scheme

    /// R2M8: the window opens with the destination list focused, so arrow keys move between
    /// rooms without a mouse trip first. Nothing here animates — a keyboard-initiated pane
    /// change rides the same 120ms cross-fade a click does, which is M6B's decision, and
    /// focus itself is instant by construction.
    @FocusState private var listFocused: Bool

    /// L10A: gap between the identity block and the first navigation row.
    private static let navigationGap: CGFloat = PDS.Space.m

    private static let logoSize: CGFloat = 32

    var body: some View {
        let _ = BenchCounters.hit("SettingsSidebar")
        VStack(alignment: .leading, spacing: .zero) {
            header
                .padding(.top, PDS.Space.xl + PDS.Space.l)
                // Match the native sidebar row inset plus its content padding.
                .padding(.horizontal, PDS.Space.xl)
                .padding(.bottom, Self.navigationGap - 10) // The native list contributes its own 10pt inset.

            List(selection: $selection) {
                ForEach(SettingsPane.allCases) { pane in
                    PDSSidebarRow(pane.label, symbol: pane.symbolName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PDS.Space.s)
                        .foregroundStyle(selection == pane ? selectionInk : Color.primary)
                        .background {
                            if selection == pane {
                                RoundedRectangle(cornerRadius: PDS.Radius.control)
                                    .fill(selectionFill)
                                    .padding(.horizontal, -PDS.Space.xs)
                            }
                        }
                        .background(SidebarSelectionChrome())
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("pane.\(pane.rawValue)")
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .focused($listFocused)

            SettingsSidebarActions(softwareUpdates: softwareUpdates)
        }
        // R2M8: focus the destination list when the window opens.
        .defaultFocus($listFocused, true)
    }

    private var selectionInk: Color {
        controlState == .key || scheme == .dark ? .white : .black
    }

    private var selectionFill: Color {
        controlState == .key
            ? Color(nsColor: .selectedContentBackgroundColor).mix(with: .black, by: 0.20)
            : Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    /// Identity block replacing the removed window title and Done footer (KD3).
    private var header: some View {
        HStack(spacing: PDS.Space.s) {
            SettingsAppIcon(size: Self.logoSize)
            VStack(alignment: .leading, spacing: PDS.Space.xs) {
                Text("Pacemark")
                    .font(PDS.Typography.rowTitle)
                    .kerning(-0.2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let version = Self.versionLabel {
                    // Quiet stamp under the name. Hidden under `swift run` (no bundle
                    // Info.plist) rather than showing a placeholder.
                    Text(version)
                        .font(SettingsType.footnote.monospacedDigit())
                        .foregroundStyle(PDS.Ink.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The sidebar and About share the version stamped in the bundle.
    static var versionLabel: String? { AppVersionLabel.prefixed }
}

/// Keep the table's keyboard and accessibility selection while the row paints its pill.
private struct SidebarSelectionChrome: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            var ancestor = superview
            while let view = ancestor {
                if let table = view as? NSTableView {
                    table.selectionHighlightStyle = .none
                    return
                }
                ancestor = view.superview
            }
        }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}

extension SettingsPane {
    /// SF Symbol per destination. Kept beside the sidebar rather than in Core: the
    /// enum is the pure identity, the glyph is presentation.
    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .appearance: "rectangle.portrait.topthird.inset.filled"
        case .menuBar: "menubar.rectangle"
        // R1 (notifications plan): the outline bell, matching the sidebar's outline family.
        case .warmUp: "sunrise"
        case .notifications: "bell"
        case .accounts: "person.2"
        case .apiSpend: "key"
        case .about: "info.circle"
        }
    }

}

/// Observe update progress at the footer, without rebuilding the destination list or
/// app scene when Sparkle changes state. Actions sit outside the selectable navigation.
private struct SettingsSidebarActions: View {
    let softwareUpdates: SoftwareUpdateControlling
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if softwareUpdates.canCheckForUpdates,
           let title = softwareUpdates.presentation.availability.title {
            Button(action: softwareUpdates.checkForUpdates) {
                Label(title, systemImage: softwareUpdates.presentation.availability.symbol)
                    .font(PDS.Typography.rowTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PDS.Space.s)
                    // 36pt gives the footer action comfortable hit areas.
                    .frame(height: 36)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!softwareUpdates.presentation.canCheckForUpdates)
            .help("Open the Pacemark software updater")
            .padding(.horizontal, PDS.Space.s)
            .padding(.vertical, PDS.Space.m)
        }
    }
}

/// The app's marketing version and build, read once from the bundle. Nil under `swift run`.
enum AppVersionLabel {
    /// "1.0 (1)", or "1.0" when no build number is stamped.
    static let plain: String? = {
        guard let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
              !short.isEmpty else { return nil }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }()

    /// "v1.0 (1)" — the sidebar identity block's form.
    static var prefixed: String? { plain.map { "v\($0)" } }
}

struct SettingsAppIcon: View {
    let size: CGFloat
    var header = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let image = header ? (scheme == .dark ? AppIconGlyph.darkMark : AppIconGlyph.lightMark) : AppIconGlyph.tile {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

/// Loads the vessel mark straight from its bundled SVG (mirrors `ProviderLogoView`'s
/// `BrandIconImage` lookup) so the Settings sidebar always renders crisp, resolution-
/// independent art instead of depending on the OS's cached app-icon snapshot.
enum AppIconGlyph {
    static let image = url(forResource: "pacemark-mark").flatMap(NSImage.init(contentsOf:))
    static let tile = url(forResource: "pacemark-icon").flatMap(NSImage.init(contentsOf:))
    static let darkMark = url(forResource: "pacemark-header-dark").flatMap(NSImage.init(contentsOf:))
    static let lightMark = url(forResource: "pacemark-header-light").flatMap(NSImage.init(contentsOf:))

    private static func url(forResource name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            return url
        }
        let swiftPMBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Pacemark_PacemarkApp.bundle")
        return Bundle(url: swiftPMBundleURL)?
            .url(forResource: name, withExtension: "svg")
    }
}
