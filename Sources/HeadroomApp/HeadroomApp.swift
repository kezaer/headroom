import SwiftUI
import AppKit
import WidgetKit
import HeadroomCore

/// Entry point. Supports a hidden `--probe-claude` diagnostic that runs the real
/// PTY capture once and prints the parsed windows — used to verify the Claude CLI
/// path works on this machine without launching the menu bar UI.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--probe-claude") {
            runClaudeProbe()
            return
        }
        if CommandLine.arguments.contains("--probe-codex") {
            runCodexProbe()
            return
        }
        HeadroomApp.main()
    }

    private static func runClaudeProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let path = ClaudeUsageCLIProbe.resolveClaudePath() ?? "(not found)"
            print("claude path: \(path)")
            switch await ClaudeUsageCLIProbe(workingDirectory: claudeWorkingDirectory()).capturePanel() {
            case .cliNotFound:
                print("RESULT: CLI not found")
            case .failed:
                print("RESULT: capture failed (no panel text)")
            case .panel(let text):
                let windows = ClaudeUsageParser.parse(text)
                print("RESULT: captured panel (\(text.count) chars), parsed \(windows.count) window(s):")
                for w in windows {
                    print("  • \(w.kind)  \(Int(w.percentUsed))% used  →  \(w.resetLabel ?? "no reset")  (remaining \(Int(100 - w.percentUsed))%)")
                }
                // Always dump the raw panel so we can see fields the parser doesn't yet
                // extract (e.g. the subscription tier for the plan pill).
                print("--- RAW PANEL (first 1500 chars) ---")
                print(String(text.prefix(1500)))
            }
            semaphore.signal()
        }
        semaphore.wait()
    }

    fileprivate static func claudeWorkingDirectory() -> String {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL.deletingLastPathComponent().path
        }
        return FileManager.default.currentDirectoryPath
    }

    private static func runCodexProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let snapshot = await CodexProvider(credentials: CredentialStore()).fetchSnapshot()
            switch snapshot.freshness {
            case .pending:
                print("RESULT: pending")
            case .live:
                print("RESULT: live Codex snapshot, parsed \(snapshot.windows.count) window(s):")
                if let plan = snapshot.planLabel {
                    print("  plan: \(plan)")
                }
                for window in snapshot.windows {
                    print("  • \(window.kind)  \(Int(window.utilization.rounded()))% used  →  \(window.resetsAt)  (remaining \(Int(window.percentRemaining.rounded()))%)")
                }
            case .stale(let reason):
                print("RESULT: stale Codex snapshot: \(reason.message)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}

/// Menu bar app (U1). The menu bar shell is owned by `StatusItemController`
/// (`NSStatusItem`) so AppKit can provide native status-item tooltip behavior. No Dock
/// icon in the shipped app — `LSUIElement = YES` is stamped into the Xcode app target.
struct HeadroomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @MainActor
    init() {
        let store = AppComposition.store()
        AppDelegate.configure(store: store, softwareUpdates: SoftwareUpdateController())
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Pins the process to `.accessory` at launch so it behaves as a pure menu-bar app —
/// no Dock icon, no app-switcher entry — even when run via `swift run` (which has no
/// `LSUIElement` Info.plist). This also makes the Settings-window activation path
/// identical in development and in the shipped bundle, so "does the window open and
/// close properly" can be verified with `swift run Headroom`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingStore: UsageStore?
    private static var pendingSoftwareUpdates: SoftwareUpdateControlling?
    private var statusItemController: StatusItemController?

    static func configure(store: UsageStore, softwareUpdates: SoftwareUpdateControlling) {
        pendingStore = store
        pendingSoftwareUpdates = softwareUpdates
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let store = Self.pendingStore,
              let softwareUpdates = Self.pendingSoftwareUpdates
        else { return }
        let controller = StatusItemController(store: store, softwareUpdates: softwareUpdates)
        statusItemController = controller
        controller.start()
    }
}

/// Composition root (R13): the one place concrete providers are wired to the engine.
/// Adding a third provider is a one-line append here plus a card — no engine change.
enum AppComposition {
    @MainActor
    static func store(preferences: Preferences = Preferences()) -> UsageStore {
        let credentials = CredentialStore()
        return UsageStore(
            providers: providers(credentials: credentials),
            apiSpendProviders: apiSpendProviders(credentials: credentials),
            preferences: preferences,
            widgetExporter: widgetExporter()
        )
    }

    static func providers() -> [any UsageProvider] {
        providers(credentials: CredentialStore())
    }

    private static func providers(credentials: CredentialStore) -> [any UsageProvider] {
        return [
            ClaudeProvider(source: ClaudeUsageCLIProbe(workingDirectory: Entry.claudeWorkingDirectory())),
            CodexProvider(credentials: credentials), // reads ~/.codex/auth.json + wham/usage
        ]
    }

    private static func apiSpendProviders(credentials: CredentialStore) -> [any APISpendProvider] {
        [
            AnthropicAPISpendProvider(credentials: credentials),
            OpenAIAPISpendProvider(credentials: credentials),
        ]
    }

    static func widgetExporter() -> any WidgetSnapshotExporting {
        WidgetSnapshotExporter(cache: .appGroup()) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
