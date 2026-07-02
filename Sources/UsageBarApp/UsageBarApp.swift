import SwiftUI
import UsageBarCore

/// Menu bar entry point (U1). `MenuBarExtra(.window)` gives a custom Liquid Glass
/// popover (KTD9). No Dock icon in the shipped app — set `LSUIElement = YES` in the
/// Xcode app target's Info.plist when finalizing the bundle (U1/KTD8).
@main
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
        let credentials = CredentialStore()
        // Detect the installed Claude Code version once at launch so the real
        // `claude-code/<version>` User-Agent is sent (KTD1), not the pinned fallback.
        let claudeVersion = ClaudeVersion.detected()
        return [
            ClaudeProvider(credentials: credentials, version: { claudeVersion }),
            CodexProvider(credentials: credentials),
        ]
    }
}
