#if DEBUG
import Foundation

/// DEBUG-only sample content so the companion can be driven in the Simulator without a
/// Mac syncing over iCloud. Enabled by launching with the `HEADROOM_PREVIEW=1`
/// environment variable (set in the scheme or via `simctl launch`). Never ships — the
/// whole file is compiled out of Release.
///
/// The numbers are the locked demo scenario shared with `DemoFixture` and
/// `DemoScreenshotData`, so the menu-bar popover, the macOS widgets, and the iPhone all
/// show the same moment. Unlike `--demo`, this path renders as ordinary *synced* content:
/// no Demo Mode banner, and Settings reports `Source: Mac snapshot`. That is what the
/// portfolio case-study phone pair needs — it illustrates the Mac→iPhone mirror, so a
/// "sample data / no accounts connected" banner would contradict the story it is proving.
/// See `Scripts/capture-case-study-shots.sh`.
enum CompanionPreviewSeed {
    enum UITestState: String {
        case waiting
        case content
        case stale
    }

    /// Screen the preview harness should open on launch (`HEADROOM_PREVIEW_SCREEN`).
    /// Lets the capture script shoot the Settings sheet headlessly, with no UI automation.
    enum PreviewScreen: String {
        case settings
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["HEADROOM_PREVIEW"] == "1"
    }

    static var previewScreen: PreviewScreen? {
        ProcessInfo.processInfo.environment["HEADROOM_PREVIEW_SCREEN"].flatMap(PreviewScreen.init(rawValue:))
    }

    static var uiTestState: UITestState? {
        ProcessInfo.processInfo.environment["HEADROOM_UI_TEST_STATE"].flatMap(UITestState.init(rawValue:))
    }

    static var shouldResetDemoForUITest: Bool {
        ProcessInfo.processInfo.environment["HEADROOM_UI_TEST_RESET_DEMO"] == "1"
    }

    static func envelope(now: Date = Date()) -> WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: now.addingTimeInterval(-4 * 60),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: ProviderID.claude.raw,
                    displayName: "Claude",
                    planLabel: "max",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 38,
                            resetsAt: now.addingTimeInterval(3 * 86_400),
                            resetLabel: "Resets Jul 9",
                            severity: .low
                        ),
                        WidgetWindowSummary(
                            kind: .fiveHour,
                            label: "5h",
                            percentRemaining: 72,
                            resetsAt: now.addingTimeInterval(3 * 3600),
                            resetLabel: "Resets 2:15pm",
                            severity: .healthy
                        ),
                        WidgetWindowSummary(
                            kind: .other("Weekly (Fable)"),
                            label: "Weekly (Fable)",
                            percentRemaining: 54,
                            resetsAt: now.addingTimeInterval(3 * 86_400),
                            resetLabel: "Resets Jul 9",
                            severity: .healthy
                        )
                    ],
                    renewalDate: nil
                ),
                WidgetProviderSummary(
                    id: ProviderID.codex.raw,
                    displayName: "Codex",
                    planLabel: "prolite",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 64,
                            resetsAt: now.addingTimeInterval((6 * 86_400) + (4 * 3600)),
                            resetLabel: "Resets in 6d 4h",
                            severity: .healthy
                        ),
                        WidgetWindowSummary(
                            kind: .fiveHour,
                            label: "5h",
                            percentRemaining: 91,
                            resetsAt: now.addingTimeInterval((3 * 3600) + (12 * 60)),
                            resetLabel: "Resets in 3h 12m",
                            severity: .healthy
                        )
                    ],
                    renewalDate: nil
                )
            ],
            apiSpendProviders: [
                WidgetAPISpendSummary(
                    id: ProviderID.claude.raw,
                    displayName: "Anthropic API",
                    amount: 142.67,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now.addingTimeInterval(-6 * 60),
                    freshness: .live
                ),
                WidgetAPISpendSummary(
                    id: ProviderID.codex.raw,
                    displayName: "OpenAI API",
                    amount: 58.90,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now.addingTimeInterval(-9 * 60),
                    freshness: .live
                ),
            ]
        )
    }

    static func envelope(for state: UITestState, now: Date = Date()) -> WidgetSnapshotEnvelope? {
        switch state {
        case .waiting:
            return nil
        case .content:
            return envelope(now: now)
        case .stale:
            let content = envelope(now: now)
            return WidgetSnapshotEnvelope(
                generatedAt: content.generatedAt,
                status: content.status,
                providers: content.providers.map { provider in
                    WidgetProviderSummary(
                        id: provider.id,
                        displayName: provider.displayName,
                        planLabel: provider.planLabel,
                        freshness: .stale(message: "Using last snapshot", needsAttention: false),
                        windows: provider.windows,
                        renewalDate: provider.renewalDate
                    )
                },
                apiSpendProviders: content.apiSpendProviders
            )
        }
    }
}
#endif
