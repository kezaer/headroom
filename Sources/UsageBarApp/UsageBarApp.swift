import SwiftUI
import UsageBarCore

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
        UsageBarApp.main()
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
                if windows.isEmpty {
                    print("--- RAW PANEL (first 1500 chars) ---")
                    print(String(text.prefix(1500)))
                }
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

/// Menu bar app (U1). `MenuBarExtra(.window)` gives a custom Liquid Glass popover
/// (KTD9). No Dock icon in the shipped app — set `LSUIElement = YES` in the Xcode app
/// target's Info.plist when finalizing the bundle (U1/KTD8).
struct UsageBarApp: App {
    @State private var store = UsageStore(providers: AppComposition.providers())
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store) {
                openWindow(id: "settings")
            }
                .task { await store.start() }
        } label: {
            MenuBarLabel(
                summary: store.menuBarSummary,
                showsPercentage: store.showMenuBarPercentage
            )
        }
        .menuBarExtraStyle(.window)

        Window("UsageBar Settings", id: "settings") {
            SettingsView(store: store)
        }
        .windowResizability(.contentSize)
    }
}

/// Composition root (R13): the one place concrete providers are wired to the engine.
/// Adding a third provider is a one-line append here plus a card — no engine change.
enum AppComposition {
    static func providers() -> [any UsageProvider] {
        return [
            ClaudeProvider(source: ClaudeUsageCLIProbe(workingDirectory: Entry.claudeWorkingDirectory())),
            CodexProvider(credentials: CredentialStore()), // reads ~/.codex/auth.json + wham/usage
        ]
    }
}
