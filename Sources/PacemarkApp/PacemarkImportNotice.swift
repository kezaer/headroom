import AppKit
import PacemarkCore
import SwiftUI

@MainActor
final class FirstLaunchImport: NSObject, NSWindowDelegate {
    private static var presenter: FirstLaunchImport?
    private static var imported = false
    private let loginChoice = ImportLoginChoice()
    private static let sourceID = "com.kylezantos.headroom"
    private var window: NSWindow?

    static func run(bundleID: String? = Bundle.main.bundleIdentifier,
                    inert: Bool = AppComposition.usesIsolatedServices(),
                    importPreferences: @MainActor () -> Bool = importPreferences) {
        guard bundleID == "com.kezaer.pacemark", !inert else { return }
        imported = importPreferences()
    }

    private static func importPreferences() -> Bool {
        let defaults = UserDefaults.standard
        return PacemarkImport.apply(from: {
            CFPreferencesCopyMultiple(nil, sourceID as CFString, kCFPreferencesCurrentUser,
                                      kCFPreferencesAnyHost) as? [String: Any] ?? [:]
        }, to: defaults, domain: "com.kezaer.pacemark")
    }

    static func showIfImported() {
        guard imported else { return }
        imported = false
        let presenter = FirstLaunchImport()
        Self.presenter = presenter
        presenter.show()
    }

    private func show() {
        let defaults = UserDefaults.standard
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.sourceID)
        let warn = PacemarkImport.warnAboutRunningApp(running: !running.isEmpty, defaults: defaults)
        let notice = PacemarkImportNotice(running: warn, loginChoice: loginChoice) { choice in
            if warn {
                if choice { running.forEach { $0.terminate() } }
                else { defaults.set(true, forKey: PacemarkImport.keepBoth) }
            }
            self.window?.close()
        }
        let panel = NSWindow(contentViewController: NSHostingController(rootView: notice))
        panel.styleMask = [.titled, .closable]
        panel.title = "Welcome to Pacemark"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        window = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        do { try LaunchAtLogin().setEnabled(loginChoice.enabled) }
        catch { NSApp.presentError(error) }
        window = nil
        Self.presenter = nil
    }
}

@MainActor @Observable
final class ImportLoginChoice {
    var enabled = true
}

struct PacemarkImportNotice: View {
    let running: Bool
    @Bindable var loginChoice: ImportLoginChoice
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsAppIcon(size: 40)
            Text("Imported your settings and accounts from Headroom.")
            Toggle("Open Pacemark at login", isOn: $loginChoice.enabled).toggleStyle(.checkbox)
            Text("If Headroom opens at login, its login item stays until you remove it in System Settings.")
                .foregroundStyle(.secondary)
            if running { Text("Headroom is running. Both apps will read the same accounts.") }
            HStack {
                Spacer()
                if running { Button("Quit Headroom") { finish(true) } }
                Button(running ? "Keep Both" : "OK") { finish(false) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
