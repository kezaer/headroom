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
        UsageBarApp.main()
    }

    private static func runClaudeProbe() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let path = ClaudeUsageCLIProbe.resolveClaudePath() ?? "(not found)"
            print("claude path: \(path)")
            switch await ClaudeUsageCLIProbe().capturePanel() {
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
}

/// Menu bar app (U1). `MenuBarExtra(.window)` gives a custom Liquid Glass popover
/// (KTD9). No Dock icon in the shipped app — set `LSUIElement = YES` in the Xcode app
/// target's Info.plist when finalizing the bundle (U1/KTD8).
struct UsageBarApp: App {
    @State private var store = UsageStore(providers: AppComposition.providers())

    var body: some Scene {
        MenuBarExtra {
            PopoverView(store: store)
                .task { await store.start() }
        } label: {
            MenuBarLabel(summary: store.menuBarSummary)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Composition root (R13): the one place concrete providers are wired to the engine.
/// Adding a third provider is a one-line append here plus a card — no engine change.
enum AppComposition {
    static func providers() -> [any UsageProvider] {
        return [
            ClaudeProvider(),                              // reads Claude Code's /usage panel
            CodexProvider(credentials: CredentialStore()), // reads ~/.codex/auth.json + wham/usage
        ]
    }
}
