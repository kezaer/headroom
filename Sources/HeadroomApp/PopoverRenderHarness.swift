import SwiftUI
import AppKit
import HeadroomCore

/// Hidden diagnostic (`--render-popover <dir>`): renders the real `PopoverView` — demo
/// fixture data, the current OS surface, real appearance — to PNGs for every onboarding state ×
/// appearance, headlessly. Exists so popover design changes can be visually reviewed
/// and diffed against the HTML design mockups without posing the live menu bar
/// (`Scripts/capture-demo-screenshots.sh` still covers the marketing hero shots).
@MainActor
enum PopoverRenderHarness {
    static func run(outputDirectory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outDir = URL(fileURLWithPath: (outputDirectory as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        Task { @MainActor in
            var failedPaths: [String] = []
            for state in State.allCases {
                let modes: [UsagePercentageMode] = state == .connected ? UsagePercentageMode.allCases : [.remaining]
                for mode in modes {
                    for dark in [false, true] {
                        let modeSuffix = mode == .used ? "-used" : ""
                        let name = "popover-\(state.rawValue)\(modeSuffix)-\(dark ? "dark" : "light").png"
                        let url = outDir.appendingPathComponent(name)
                        if await render(state: state, percentageMode: mode, dark: dark, to: url) {
                            print("✓ \(url.path)")
                        } else {
                            failedPaths.append(url.path)
                        }
                    }
                }
            }
            for scenario in MultiAccountScenario.allCases {
                for dark in [false, true] {
                    let name = "popover-\(scenario.rawValue)-\(dark ? "dark" : "light").png"
                    let url = outDir.appendingPathComponent(name)
                    if await renderMulti(scenario: scenario, dark: dark, to: url) {
                        print("✓ \(url.path)")
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            }
            for mode in UsagePercentageMode.allCases {
                for dark in [false, true] {
                    let modeSuffix = mode == .used ? "-used" : ""
                    let name = "settings\(modeSuffix)-\(dark ? "dark" : "light").png"
                    let url = outDir.appendingPathComponent(name)
                    if await renderSettings(percentageMode: mode, dark: dark, to: url) {
                        print("✓ \(url.path)")
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            }
            for dark in [false, true] {
                let name = "settings-accounts-\(dark ? "dark" : "light").png"
                let url = outDir.appendingPathComponent(name)
                if await renderSettings(percentageMode: .remaining, dark: dark, multiAccount: true, to: url) {
                    print("✓ \(url.path)")
                } else {
                    failedPaths.append(url.path)
                }
            }
            let heroURL = outDir.appendingPathComponent("hero-popover-dark.png")
            if await renderHero(to: heroURL) {
                print("✓ \(heroURL.path)")
            } else {
                failedPaths.append(heroURL.path)
            }
            for path in failedPaths {
                FileHandle.standardError.write(Data("✗ Failed to render \(path)\n".utf8))
            }
            exit(failedPaths.isEmpty ? 0 : 1)
        }
        app.run()
    }

    enum State: String, CaseIterable {
        case connect, waiting, connected
        case codexConnect, codexReconnect, codexWaiting, codexConnected
        case dualWaiting
    }

    /// Multi-account layouts under review: two accounts (regular density), three
    /// (compact threshold), five (max cap + popover scroll), and a mixed-health stack
    /// (one live, one waiting on sign-in, one transiently stale).
    enum MultiAccountScenario: String, CaseIterable {
        case multiTwo = "multi-2"
        case multiThree = "multi-3"
        case multiFive = "multi-5"
        case multiMixed = "multi-mixed"
    }

    private struct MultiAccountFixture {
        let accounts: [ProviderAccount]
        let providers: [any UsageProvider]
    }

    /// One deterministic account fixture: label + plan + varied utilizations so the
    /// severity ramp (healthy/low/critical) and plan pills all appear in review shots.
    private static func demoAccount(
        provider providerID: ProviderID,
        id: String,
        label: String,
        plan: String,
        fiveHour: Double,
        weekly: Double,
        freshness: Freshness = .live,
        builtIn: Bool = false
    ) -> (account: ProviderAccount, provider: any UsageProvider) {
        let accountID: AccountID = builtIn ? .primary : AccountID(id)
        let account = ProviderAccount(id: accountID, providerID: providerID, label: label, isBuiltIn: builtIn)
        let windows: [UsageWindow]
        switch freshness {
        case .stale(let reason) where reason.isPermanent:
            windows = []
        default:
            windows = [
                UsageWindow(kind: .fiveHour, utilization: fiveHour, resetsAt: Date().addingTimeInterval(3.2 * 3600), resetLabel: "Resets 2:15pm"),
                UsageWindow(kind: .weekly, utilization: weekly, resetsAt: Date().addingTimeInterval(4 * 86_400), resetLabel: "Resets Jul 20"),
            ]
        }
        let snapshot = UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: plan,
            capturedAt: Date().addingTimeInterval(-135),
            freshness: freshness
        )
        let displayName = providerID == .claude ? "Claude" : "Codex"
        return (account, DemoUsageProvider(id: providerID, displayName: displayName, snapshot: snapshot, accountID: accountID))
    }

    private static func multiFixture(for scenario: MultiAccountScenario) -> MultiAccountFixture {
        var pairs: [(account: ProviderAccount, provider: any UsageProvider)] = []
        switch scenario {
        case .multiTwo:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .codex, id: "codex-main", label: "Main", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
            ]
        case .multiThree:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .claude, id: "studio", label: "Studio", plan: "Max", fiveHour: 12, weekly: 41),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79),
            ]
        case .multiFive:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 71, weekly: 88),
                demoAccount(provider: .claude, id: "studio", label: "Studio", plan: "Max", fiveHour: 12, weekly: 41),
                demoAccount(provider: .claude, id: "agency", label: "Agency", plan: "Team", fiveHour: 47, weekly: 55),
                demoAccount(provider: .claude, id: "lab", label: "Lab", plan: "Pro", fiveHour: 93, weekly: 97),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79),
                demoAccount(provider: .codex, id: "codex-studio", label: "Studio", plan: "Plus", fiveHour: 22, weekly: 48),
            ]
        case .multiMixed:
            pairs = [
                demoAccount(provider: .claude, id: "personal", label: "Personal", plan: "Max", fiveHour: 28, weekly: 62, builtIn: true),
                demoAccount(provider: .claude, id: "work", label: "Work", plan: "Pro", fiveHour: 0, weekly: 0,
                            freshness: .stale(.notLoggedIn(UsageStore.finishSignInMessage))),
                demoAccount(provider: .codex, id: "codex-main", label: "Personal", plan: "Prolite", fiveHour: 9, weekly: 36, builtIn: true),
                demoAccount(provider: .codex, id: "codex-work", label: "Work", plan: "Pro", fiveHour: 54, weekly: 79,
                            freshness: .stale(.transient("Couldn't reach Codex — will retry"))),
            ]
        }
        return MultiAccountFixture(accounts: pairs.map(\.account), providers: pairs.map(\.provider))
    }

    private static func renderMulti(scenario: MultiAccountScenario, dark: Bool, to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        ClaudeSetupSession.openedSetupAt = nil
        CodexSetupSession.openedSetupAt = nil
        let fixture = multiFixture(for: scenario)
        let preferences = renderPreferences(mode: .remaining)
        let store = UsageStore(
            providers: fixture.providers,
            apiSpendProviders: [],
            preferences: preferences,
            accounts: fixture.accounts
        )
        store.refreshNow()
        try? await Task.sleep(for: .milliseconds(700))
        return await snapshotPopover(store: store, dark: dark, to: url)
    }

    private static func render(state: State, percentageMode: UsagePercentageMode, dark: Bool, to url: URL) async -> Bool {
        // App-wide appearance, not just window-level: SwiftUI's semantic styles
        // (.primary/.secondary/.quaternary) resolve against the app's effective
        // appearance in this offscreen path, so a window-only override leaves
        // light-mode ink in dark renders.
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Provider-scoped flags drive each Connect → Waiting → Connected flow.
        ClaudeSetupSession.openedSetupAt = switch state {
        case .waiting, .connected, .dualWaiting: Date()
        default: nil
        }
        CodexSetupSession.openedSetupAt = switch state {
        case .codexWaiting, .codexConnected, .dualWaiting: Date()
        default: nil
        }

        let preferences = renderPreferences(mode: percentageMode)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: claudeSnapshot(for: state)),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: codexSnapshot(for: state)),
            ],
            apiSpendProviders: spendProviders(for: state),
            preferences: preferences
        )
        store.refreshNow()
        // Demo providers resolve instantly; give the cycle + entrance animation a beat.
        try? await Task.sleep(for: .milliseconds(700))
        return await snapshotPopover(store: store, dark: dark, to: url)
    }

    /// Shared popover capture: hosts the real `PopoverView` over the desk backdrop,
    /// sizes to fit, and snapshots the compositor output.
    private static func snapshotPopover(store: UsageStore, dark: Bool, to url: URL) async -> Bool {
        let root = ZStack {
            // Desk backdrop so the system surface has something to sample (mirrors the mockup).
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.137, green: 0.137, blue: 0.169), Color(red: 0.078, green: 0.078, blue: 0.102)]
                    : [Color(red: 0.843, green: 0.827, blue: 0.800), Color(red: 0.725, green: 0.702, blue: 0.663)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            PopoverView(store: store, onOpenSettings: {})
                .padding(24)
        }
        .frame(width: 432)
        // Direct environment override (not the scene-level `preferredColorScheme`
        // preference) so semantic styles resolve for the right scheme in this
        // offscreen hosting context.
        .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 432, height: 10)
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: 0, width: 432, height: max(fitting.height, 200))

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.isOpaque = true
        window.orderFrontRegardless()
        window.displayIfNeeded()
        // Let the popover's one-shot entrance settle (0.22s curve) before snapshotting.
        try? await Task.sleep(for: .milliseconds(600))

        // Capture the compositor's actual output (correct dynamic-color resolution and
        // the real OS-selected surface) via `screencapture -l`. The offscreen `cacheDisplay` path
        // resolves semantic text colors against the wrong appearance, so it's only the
        // fallback when screen capture is unavailable (no Screen Recording permission).
        let captured = capture(window: window, to: url)
        window.orderOut(nil)
        return captured
    }

    /// Marketing hero for headroom.zantos.co (U4): the connected, dark popover with the
    /// API Spend section, rendered via `ImageRenderer` at 3× with a transparent
    /// background (rounded corners live in the PNG alpha) — no Screen Recording
    /// permission needed, unlike the compositor `screencapture` path above. Forces the
    /// solid surface branch (reduce-transparency), because `ImageRenderer` can't
    /// rasterize the live Liquid Glass material; the resulting flat shell + tiles match
    /// the design artboard (OQ1 resolved to the solid shell — see the plan).
    @MainActor
    private static func renderHero(to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Steady connected state: clear any setup-session flags the diagnostic render loop
        // left set, so the transient "✓ Connected" payoff chip doesn't appear (the design
        // artboard shows plain provider headers).
        ClaudeSetupSession.openedSetupAt = nil
        CodexSetupSession.openedSetupAt = nil
        let preferences = renderPreferences(mode: .remaining)
        let store = UsageStore(
            providers: [
                DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
            ],
            apiSpendProviders: [
                DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
            ],
            preferences: preferences
        )
        store.refreshNow()
        try? await Task.sleep(for: .milliseconds(400))

        let root = PopoverView(store: store, onOpenSettings: {}, forceVisible: true, forceSolidSurface: true)
            .environment(\.colorScheme, .dark)
            .focusEffectDisabled()
            // The popover's `WindowAccessor` background NSView renders as the system accent
            // under ImageRenderer, filling the rounded-corner cutouts with an opaque fringe.
            // Clip the whole export to the surface shape so those cutouts stay transparent.
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        let renderer = ImageRenderer(content: root)
        renderer.scale = 3
        renderer.isOpaque = false

        var pngData: Data?
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            guard let cgImage = renderer.cgImage else { return }
            pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }
        guard let data = pngData, data.count > 10_000 else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func captureWindow(number: Int, to url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-o", "-x", "-l", String(number), url.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        guard process.terminationStatus == 0,
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > 10_000 else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    /// Settings window, demo store, fixed 460×1240 — verifies the shared type hierarchy
    /// (22pt title / 15pt tile heads / 13pt controls / 11pt fine print) and the
    /// all-tiles material system across both windows.
    private static func renderSettings(percentageMode: UsagePercentageMode, dark: Bool, multiAccount: Bool = false, to url: URL) async -> Bool {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let preferences = renderPreferences(mode: percentageMode)
        let store: UsageStore
        if multiAccount {
            let fixture = multiFixture(for: .multiMixed)
            // A live registry + factory so account management renders enabled (the real
            // app always has both); seeded with the fixture accounts.
            let registry = AccountRegistry(defaults: UserDefaults(suiteName: "co.zantos.headroom.render.accounts.\(UUID().uuidString)") ?? .standard)
            registry.seed(fixture.accounts)
            store = UsageStore(
                providers: fixture.providers,
                apiSpendProviders: [
                    DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                    DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                ],
                preferences: preferences,
                accounts: fixture.accounts,
                accountRegistry: registry,
                providerFactory: { account in
                    DemoUsageProvider(
                        id: account.providerID,
                        displayName: account.providerID == .claude ? "Claude" : "Codex",
                        snapshot: .pending(for: account.providerID),
                        accountID: account.id
                    )
                }
            )
            store.refreshNow()
            try? await Task.sleep(for: .milliseconds(300))
        } else {
            store = UsageStore(
                providers: [
                    DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: DemoFixture.claudeSnapshot),
                    DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: DemoFixture.codexSnapshot),
                ],
                apiSpendProviders: [
                    DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
                    DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
                ],
                preferences: preferences
            )
        }
        let height: CGFloat = multiAccount ? 1500 : 1240
        let root = SettingsView(
            store: store,
            appearancePreference: .constant(dark ? .dark : .light),
            preferences: preferences
        )
            .frame(width: 460, height: height)
            .environment(\.colorScheme, dark ? .dark : .light)

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        hosting.frame = NSRect(x: 0, y: 0, width: 460, height: height)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        window.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        let captured = capture(window: window, to: url)
        window.orderOut(nil)
        return captured
    }

    private static func capture(window: NSWindow, to url: URL) -> Bool {
        if captureWindow(number: window.windowNumber, to: url) { return true }
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return false }
        (window.appearance ?? NSAppearance(named: .aqua))?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let data = rep.representation(using: .png, properties: [:]), data.count > 10_000 else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func renderPreferences(mode: UsagePercentageMode) -> Preferences {
        let suite = "co.zantos.headroom.render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: defaults)
        preferences.usagePercentageMode = mode
        // API spend surfaces are off by default (`isSurfaceEnabled` → `isSubscription`),
        // so the store's `apiSpendProviderOrder` is empty and the section renders nothing.
        // Enable both so the connected hero shows the API Spend section — wiring the
        // providers alone is not sufficient (mirrors AppComposition.demoStore()).
        preferences.setSurfaceEnabled(true, for: .anthropicAPI)
        preferences.setSurfaceEnabled(true, for: .openAIAPI)
        return preferences
    }

    /// Demo API-spend providers for a popover render. Only the connected hero carries
    /// spend — the setup/waiting states have no configured keys, so showing dollar
    /// totals there would be misleading. The surfaces themselves are enabled in
    /// `renderPreferences`.
    private static func spendProviders(for state: State) -> [any APISpendProvider] {
        guard state == .connected else { return [] }
        return [
            DemoSpendProvider(id: .claude, displayName: "Anthropic API", snapshot: DemoFixture.anthropicSpend),
            DemoSpendProvider(id: .codex, displayName: "OpenAI API", snapshot: DemoFixture.openAISpend),
        ]
    }

    private static func claudeSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .connect, .waiting, .dualWaiting:
            return UsageSnapshot(
                providerID: .claude,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .stale(.needsReauth(ClaudeUsageWorkspace.trustRequiredMessage))
            )
        case .connected, .codexConnect, .codexReconnect, .codexWaiting, .codexConnected:
            return DemoFixture.claudeSnapshot
        }
    }

    private static func codexSnapshot(for state: State) -> UsageSnapshot {
        switch state {
        case .codexConnect:
            return .stale(
                for: .codex,
                reason: .notLoggedIn("Codex isn't logged in — run `\(CodexCLI.loginCommand)`")
            )
        case .codexReconnect, .codexWaiting, .dualWaiting:
            return UsageSnapshot(
                providerID: .codex,
                windows: DemoFixture.codexSnapshot.windows,
                planLabel: DemoFixture.codexSnapshot.planLabel,
                capturedAt: DemoFixture.codexSnapshot.capturedAt,
                freshness: .stale(.needsReauth("Session expired — run `\(CodexCLI.loginCommand)` to reconnect"))
            )
        case .codexConnected, .connect, .waiting, .connected:
            return DemoFixture.codexSnapshot
        }
    }
}
