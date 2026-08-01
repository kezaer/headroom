import Foundation
import Testing
@testable import HeadroomCore

struct LargeWidgetDensityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func initFromRowCounts1p2m0sReturnsRoomy() {
        #expect(LargeWidgetDensity(providerCount: 1, meterCount: 2, hasSpend: false) == .roomy)
    }

    @Test func initFromRowCounts1p2m1sReturnsRoomy() {
        #expect(LargeWidgetDensity(providerCount: 1, meterCount: 2, hasSpend: true) == .roomy)
    }

    @Test func initFromRowCounts2p2m0sReturnsRegular() {
        #expect(LargeWidgetDensity(providerCount: 2, meterCount: 4, hasSpend: false) == .regular)
    }

    @Test func initFromRowCounts2p2m1sReturnsRegular() {
        #expect(LargeWidgetDensity(providerCount: 2, meterCount: 4, hasSpend: true) == .regular)
    }

    @Test func initFromRowCounts2p3m1sReturnsCompact() {
        #expect(LargeWidgetDensity(providerCount: 2, meterCount: 6, hasSpend: true) == .compact)
    }

    @Test func fourProvidersAndThreeSpendRowsUseUltraCompactTier() {
        #expect(
            LargeWidgetDensity(providerCount: 4, meterCount: 8, spendCount: 3)
                == .ultraCompact
        )
    }

    @Test func initFromEnvelopeWith2p2m1sReturnsRegular() {
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [provider(id: "claude"), provider(id: "codex")],
            apiSpendProviders: [spendProvider(id: "openai-api")]
        )

        #expect(LargeWidgetDensity(envelope: envelope) == .regular)
    }

    @Test func weeklyLabeledExtraWindowsCountAsRows() {
        let provider = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [
                weeklyWindow(),
                fiveHourWindow(),
                WidgetWindowSummary(
                    kind: .other("Weekly (Fable)"),
                    label: "Weekly (Fable)",
                    percentRemaining: 54,
                    resetsAt: now,
                    resetLabel: "Resets tomorrow",
                    severity: .healthy
                )
            ],
            renewalDate: nil
        )
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [provider]
        )

        // This provider has 2 subscription windows (weekly + 5h) + 1 extra weekly window
        #expect(provider.subscriptionWindows.count == 2)
        #expect(provider.extraWeeklyWindows.count == 1)
        // Total: 1 header + 3 meters + 0 spend = 4 rows = roomy tier
        #expect(LargeWidgetDensity(envelope: envelope) == .roomy)
    }

    @Test func nonWeeklyLabeledExtraWindowsDoNotCount() {
        let provider = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [
                weeklyWindow(),
                fiveHourWindow(),
                WidgetWindowSummary(
                    kind: .other("Sonnet burst"),
                    label: "Sonnet burst",
                    percentRemaining: 42,
                    resetsAt: now,
                    resetLabel: "Resets tomorrow",
                    severity: .healthy
                )
            ],
            renewalDate: nil
        )
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [provider]
        )

        // This provider has 2 subscription windows (weekly + 5h) + 0 extra weekly windows
        #expect(provider.subscriptionWindows.count == 2)
        #expect(provider.extraWeeklyWindows.count == 0)
        // Total: 1 header + 2 meters + 0 spend = 3 rows = roomy tier
        #expect(LargeWidgetDensity(envelope: envelope) == .roomy)
    }

    @Test func derivedValueOrderingAndProperties() {
        #expect(LargeWidgetDensity.roomy.gapFloor > LargeWidgetDensity.regular.gapFloor)
        #expect(LargeWidgetDensity.regular.gapFloor > LargeWidgetDensity.compact.gapFloor)
        #expect(LargeWidgetDensity.compact.gapFloor > LargeWidgetDensity.ultraCompact.gapFloor)
        #expect(LargeWidgetDensity.roomy.headerSpacing > LargeWidgetDensity.regular.headerSpacing)
        #expect(LargeWidgetDensity.regular.headerSpacing > LargeWidgetDensity.compact.headerSpacing)
        #expect(LargeWidgetDensity.roomy.meterSpacing > LargeWidgetDensity.regular.meterSpacing)
        #expect(LargeWidgetDensity.regular.meterSpacing > LargeWidgetDensity.compact.meterSpacing)
        #expect(LargeWidgetDensity.compact.meterSpacing > LargeWidgetDensity.ultraCompact.meterSpacing)
    }

    @Test func tokenValuesMatchEachTier() {
        let roomy = LargeWidgetDensity.roomy
        #expect(roomy.providerIconSize == 24)
        #expect(roomy.barHeight == 8)
        #expect(roomy.scale == .hero)
        #expect(roomy.glancePercentFontStep == .hero)
        #expect(roomy.windowTitleFontStep == .hero)
        #expect(roomy.providerHeaderFontStep == .hero)

        let regular = LargeWidgetDensity.regular
        #expect(regular.providerIconSize == 20)
        #expect(regular.barHeight == 6)
        #expect(regular.scale == .standard)
        #expect(regular.glancePercentFontStep == .standard)
        #expect(regular.windowTitleFontStep == .standard)
        #expect(regular.providerHeaderFontStep == .standard)

        let compact = LargeWidgetDensity.compact
        #expect(compact.providerIconSize == 18)
        #expect(compact.barHeight == 5)
        #expect(compact.scale == .dense)
        #expect(compact.glancePercentFontStep == .dense)
        #expect(compact.windowTitleFontStep == .dense)
        #expect(compact.providerHeaderFontStep == .dense)

        let ultraCompact = LargeWidgetDensity.ultraCompact
        #expect(ultraCompact.providerIconSize == 16)
        #expect(ultraCompact.barHeight == 4)
        #expect(ultraCompact.scale == .ultraDense)
    }

    @Test func scaleLevelTokenValues() {
        let hero = LargeWidgetDensity.Scale.hero
        #expect(hero.barHeight == 8)
        #expect(hero.meterSpacing == 7)

        let standard = LargeWidgetDensity.Scale.standard
        #expect(standard.barHeight == 6)
        #expect(standard.meterSpacing == 6)

        let dense = LargeWidgetDensity.Scale.dense
        #expect(dense.barHeight == 5)
        #expect(dense.meterSpacing == 4)

        let ultraDense = LargeWidgetDensity.Scale.ultraDense
        #expect(ultraDense.barHeight == 4)
        #expect(ultraDense.meterSpacing == 3)
    }

    @Test func tokenValuesStrictlyDecreaseWithDensity() {
        let roomy = LargeWidgetDensity.roomy
        let regular = LargeWidgetDensity.regular
        let compact = LargeWidgetDensity.compact
        let ultraCompact = LargeWidgetDensity.ultraCompact

        #expect(roomy.barHeight > regular.barHeight)
        #expect(regular.barHeight > compact.barHeight)
        #expect(roomy.providerIconSize > regular.providerIconSize)
        #expect(regular.providerIconSize > compact.providerIconSize)
        #expect(roomy.gapFloor > regular.gapFloor)
        #expect(regular.gapFloor > compact.gapFloor)
        #expect(compact.gapFloor > ultraCompact.gapFloor)
    }

    @Test func scaleMapsToEachDensityTier() {
        #expect(LargeWidgetDensity.roomy.scale == .hero)
        #expect(LargeWidgetDensity.regular.scale == .standard)
        #expect(LargeWidgetDensity.compact.scale == .dense)
    }

    private func provider(id: String) -> WidgetProviderSummary {
        WidgetProviderSummary(
            id: id,
            displayName: id.capitalized,
            planLabel: nil,
            freshness: .live,
            windows: [weeklyWindow(), fiveHourWindow()],
            renewalDate: nil
        )
    }

    private func spendProvider(id: String) -> WidgetAPISpendSummary {
        WidgetAPISpendSummary(
            id: id,
            displayName: "OpenAI API",
            amount: 12.34,
            currency: "USD",
            periodLabel: "This month",
            capturedAt: now,
            freshness: .live
        )
    }

    private func weeklyWindow() -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .weekly,
            label: "Weekly",
            percentRemaining: 60,
            resetsAt: now,
            resetLabel: "Resets tomorrow",
            severity: .healthy
        )
    }

    private func fiveHourWindow() -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .fiveHour,
            label: "5-hour",
            percentRemaining: 60,
            resetsAt: now,
            resetLabel: "Resets in 2h",
            severity: .healthy
        )
    }
}
