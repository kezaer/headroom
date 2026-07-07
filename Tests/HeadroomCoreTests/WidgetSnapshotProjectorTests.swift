import Testing
import Foundation
@testable import HeadroomCore

struct WidgetSnapshotProjectorTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let reset = Date(timeIntervalSince1970: 2_100_000)

    @Test func liveProvidersProjectWeeklySummaries() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset),
                    UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
                ], plan: "max", at: now),
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                ], plan: "pro", at: now),
            ],
            providerOrder: [.claude, .codex],
            displayNames: [.claude: "Claude", .codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.status == .enabled)
        #expect(envelope.providers.count == 2)
        #expect(envelope.weeklyProviders[0].weeklyWindow?.percentRemaining == 60)
        #expect(envelope.weeklyProviders[1].weeklyWindow?.percentRemaining == 75)
    }

    @Test func missingWeeklyWindowOnlyAffectsThatProvider() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset),
                ], at: now),
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.claude, .codex],
            displayNames: [.claude: "Claude", .codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.weeklyProviders[0].weeklyWindow == nil)
        #expect(envelope.weeklyProviders[1].weeklyWindow?.percentRemaining == 70)
    }

    @Test func staleProviderCarriesSafeMessageAndPriorWindows() {
        let snapshot = UsageSnapshot(
            providerID: .claude,
            windows: [UsageWindow(kind: .weekly, utilization: 95, resetsAt: reset)],
            planLabel: nil,
            capturedAt: now,
            freshness: .stale(.needsReauth("Run `claude`"))
        )
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: snapshot],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        guard case .stale(let message, let needsAttention) = envelope.providers[0].freshness else {
            Issue.record("expected stale provider")
            return
        }
        #expect(message == "Run `claude`")
        #expect(needsAttention)
        #expect(envelope.providers[0].weeklyWindow?.severity == .critical)
    }

    @Test func disabledExportContainsNoProviderData() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: .live(.claude, windows: [UsageWindow(kind: .weekly, utilization: 5, resetsAt: reset)])],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: false,
            apiSpendSnapshots: [
                .codex: APISpendSnapshot(
                    providerID: .codex,
                    displayName: "OpenAI API",
                    amount: 12.34,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now,
                    freshness: .live
                ),
            ],
            apiSpendProviderOrder: [.codex],
            generatedAt: now
        )

        #expect(envelope.status == .disabled)
        #expect(envelope.providers.isEmpty)
        #expect(envelope.apiSpendProviders.isEmpty)
    }

    @Test func enabledAPISpendProjectsInProviderOrder() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .codex: APISpendSnapshot(
                    providerID: .codex,
                    displayName: "OpenAI API",
                    amount: 12.3,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now,
                    freshness: .live
                ),
                .claude: APISpendSnapshot(
                    providerID: .claude,
                    displayName: "Anthropic API",
                    amount: 4,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: now.addingTimeInterval(-60),
                    freshness: .live
                ),
            ],
            apiSpendProviderOrder: [.claude, .codex],
            generatedAt: now
        )

        #expect(envelope.apiSpendProviders.map(\.id) == ["claude", "codex"])
        #expect(envelope.apiSpendProviders[0].displayName == "Anthropic API")
        #expect(envelope.apiSpendProviders[0].amount == 4)
        #expect(envelope.apiSpendProviders[0].currency == "usd")
        #expect(envelope.apiSpendProviders[0].periodLabel == "Current month")
        #expect(envelope.apiSpendProviders[0].capturedAt == now.addingTimeInterval(-60))
        #expect(envelope.apiSpendProviders[0].freshness == .live)
    }

    @Test func staleAPISpendProjectsSafeFreshnessAndPriorAmount() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [:],
            providerOrder: [],
            displayNames: [:],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .codex: APISpendSnapshot(
                    providerID: .codex,
                    displayName: "OpenAI API",
                    amount: 12.3,
                    currency: "usd",
                    periodLabel: "Last 30 days",
                    capturedAt: now,
                    freshness: .stale(.notLoggedIn("Add API key on Mac"))
                ),
            ],
            apiSpendProviderOrder: [.codex],
            generatedAt: now
        )

        let spend = envelope.apiSpendProviders[0]
        #expect(spend.amount == 12.3)
        #expect(spend.periodLabel == "Last 30 days")
        guard case .stale(let message, let needsAttention) = spend.freshness else {
            Issue.record("expected stale API spend")
            return
        }
        #expect(message == "Add API key on Mac")
        #expect(needsAttention)
    }

    @Test func nonSubscriptionAllowanceWindowsAreFilteredOutOfWidgets() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                    UsageWindow(kind: .other("GPT-5.3"), utilization: 90, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.codex],
            displayNames: [.codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.map(\.kind) == [.weekly])
    }

    @Test func codexSparkWindowsCanBeIncludedInWidgetSnapshots() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .codex: .live(.codex, windows: [
                    UsageWindow(kind: .weekly, utilization: 25, resetsAt: reset),
                    UsageWindow(kind: .other("codex-spark 5h"), utilization: 40, resetsAt: reset),
                    UsageWindow(kind: .other("codex-spark weekly"), utilization: 60, resetsAt: reset),
                    UsageWindow(kind: .other("GPT-5.3"), utilization: 90, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.codex],
            displayNames: [.codex: "Codex"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            showsCodexSparkCounters: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.map(\.kind) == [
            .weekly,
            .other("codex-spark 5h"),
            .other("codex-spark weekly"),
        ])
        #expect(envelope.providers[0].extraCounterWindows.count == 2)
        #expect(envelope.providers[0].weeklyDisplayWindows.map(\.label) == ["Weekly", "codex-spark weekly"])
    }

    @Test func sparkWindowSettingDoesNotExposeNonCodexWindows() {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: .live(.claude, windows: [
                    UsageWindow(kind: .other("claude spark weekly"), utilization: 10, resetsAt: reset),
                ], at: now),
            ],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            showsCodexSparkCounters: true,
            generatedAt: now
        )

        #expect(envelope.providers[0].windows.isEmpty)
    }

    @Test func unknownProviderRoundTrips() throws {
        let other = ProviderID("other")
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [other: .live(other, windows: [UsageWindow(kind: .weekly, utilization: 20, resetsAt: reset)])],
            providerOrder: [other],
            displayNames: [other: "Other"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: data)
        #expect(decoded.providers[0].id == "other")
        #expect(decoded.providers[0].windows[0].kind == .weekly)
    }
}
