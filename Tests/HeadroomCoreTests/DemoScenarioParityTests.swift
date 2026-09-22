import Foundation
import Testing
@testable import HeadroomCore

struct DemoScenarioParityTests {
    @Test func iOSDemoCoversCurrentMacScenario() {
        let ios = DemoScreenshotData.envelope(for: "full")
        let projected = WidgetSnapshotProjector.project(
            snapshots: [
                .claude: DemoFixture.claudeSnapshot,
                .codex: DemoFixture.codexSnapshot,
            ],
            providerOrder: [.claude, .codex],
            displayNames: [.claude: "Claude", .codex: "Codex"],
            renewalDate: DemoFixture.renewalDate,
            widgetsEnabled: true,
            apiSpendSnapshots: [
                .claude: DemoFixture.anthropicSpend,
                .codex: DemoFixture.openAISpend,
            ],
            apiSpendProviderOrder: [.claude, .codex]
        )

        #expect(providerSignature(ios) == providerSignature(projected))
        #expect(spendSignature(ios) == spendSignature(projected))
    }

    @Test func iOSDemoIncludesEveryReviewableSection() {
        let envelope = DemoScreenshotData.envelope(for: "full")

        #expect(envelope.status == .enabled)
        #expect(envelope.providers.map(\.id) == [ProviderID.claude.raw, ProviderID.codex.raw])
        #expect(envelope.apiSpendProviders.map(\.id) == [ProviderID.claude.raw, ProviderID.codex.raw])
        #expect(envelope.providers.first?.windows.contains {
            $0.kind == .other("Weekly (Fable)") && $0.roundedPercentRemaining == 54
        } == true)
    }

    /// U12: the four-provider demo envelope's provider list is derived from — and equals —
    /// the registry order, so a screenshot/QA scenario exercises every registered provider
    /// rather than a Claude/Codex literal.
    @Test func fourProviderDemoEnvelopeCoversTheRegistry() {
        let envelope = DemoScreenshotData.envelope(for: "fourProviders")
        #expect(envelope.status == .enabled)
        #expect(envelope.providers.map(\.id) == DemoFixture.registeredProviderOrder.map(\.raw))
        // Grok/Cursor bill as period pools, which project to `.other` widget windows.
        let grok = envelope.providers.first { $0.id == ProviderID.grok.raw }
        let cursor = envelope.providers.first { $0.id == ProviderID.cursor.raw }
        #expect(grok?.windows.first?.label == "Weekly")
        #expect(grok?.windows.first?.isBillingPeriod == true)
        #expect(grok?.windows.first?.displayPercentRemaining == 56)
        #expect(grok?.primarySubscriptionWindow != nil)
        #expect(cursor?.windows.map(\.label) == ["Cursor Models", "Other Models"])
        #expect(cursor?.windows.allSatisfy(\.isBillingPeriod) == true)
        #expect(cursor?.windows.map(\.displayPercentRemaining) == [69, 37])
        #expect(cursor?.primarySubscriptionWindow?.label == "Other Models")
    }

    @Test func encodedIOSDemoContainsNoSensitiveSentinels() throws {
        let encoded = try JSONEncoder().encode(DemoScreenshotData.envelope(for: "full"))
        let text = String(decoding: encoded, as: UTF8.self).lowercased()

        for forbidden in [
            "bearer ",
            "api_key",
            "access_token",
            "auth.json",
            "claude code-credentials",
            "/users/",
        ] {
            #expect(!text.contains(forbidden))
        }
    }

    private func providerSignature(_ envelope: WidgetSnapshotEnvelope) -> [ProviderSignature] {
        envelope.providers.map { provider in
            ProviderSignature(
                id: provider.id,
                displayName: provider.displayName,
                planLabel: provider.planLabel,
                freshness: provider.freshness,
                windows: provider.windows.map {
                    WindowSignature(
                        kind: $0.kind,
                        label: $0.label,
                        percentRemaining: $0.roundedPercentRemaining,
                        resetLabel: $0.resetLabel,
                        severity: $0.severity
                    )
                }
            )
        }
    }

    private func spendSignature(_ envelope: WidgetSnapshotEnvelope) -> [SpendSignature] {
        envelope.apiSpendProviders.map {
            SpendSignature(
                id: $0.id,
                displayName: $0.displayName,
                amount: $0.amount,
                currency: $0.currency,
                periodLabel: $0.periodLabel,
                freshness: $0.freshness
            )
        }
    }
}

private struct ProviderSignature: Equatable {
    let id: String
    let displayName: String
    let planLabel: String?
    let freshness: WidgetProviderFreshness
    let windows: [WindowSignature]
}

private struct WindowSignature: Equatable {
    let kind: WidgetWindowKind
    let label: String
    let percentRemaining: Int
    let resetLabel: String?
    let severity: WidgetUsageSeverity
}

private struct SpendSignature: Equatable {
    let id: String
    let displayName: String
    let amount: Double?
    let currency: String?
    let periodLabel: String
    let freshness: WidgetProviderFreshness
}
