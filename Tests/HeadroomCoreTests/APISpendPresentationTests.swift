import Foundation
import Testing
@testable import HeadroomCore

struct APISpendPresentationTests {
    private let now = Date(timeIntervalSince1970: 2_000)

    @Test func usdAmountFormatsWithTwoDecimals() {
        #expect(APISpendPresentation.amountText(amount: 12.3, currency: "usd") == "$12.30")
    }

    @Test func unknownCurrencyFormatsWithCodeFallback() {
        let text = APISpendPresentation.amountText(amount: 12.3, currency: "xyz")

        #expect(text?.contains("XYZ") == true)
        #expect(text?.contains("12.30") == true)
    }

    @Test func missingAmountReturnsNil() {
        #expect(APISpendPresentation.amountText(amount: nil, currency: "usd") == nil)
        #expect(APISpendPresentation.amountText(amount: 12.3, currency: nil) == nil)
    }

    @Test func addCreditsURLTargetsProviderBillingPages() {
        #expect(APISpendPresentation.addCreditsURL(for: .claude)?.absoluteString == "https://platform.claude.com/settings/billing")
        #expect(APISpendPresentation.addCreditsURL(for: .codex)?.absoluteString == "https://platform.openai.com/settings/organization/billing/overview")
        #expect(APISpendPresentation.addCreditsURL(for: .grok)?.absoluteString == "https://console.x.ai")
        #expect(APISpendPresentation.addCreditsURL(for: ProviderID("someday")) == nil)
    }

    @Test func balancePresentationReadsAsRemainingWithoutChangingSpendCopy() {
        let balance = WidgetAPISpendSummary(
            id: ProviderID.grok.raw,
            displayName: "xAI API",
            amount: 42.1,
            currency: "usd",
            periodLabel: "Prepaid balance",
            kind: .balance,
            capturedAt: now,
            freshness: .live
        )
        let spend = WidgetAPISpendSummary(
            id: ProviderID.codex.raw,
            displayName: "OpenAI API",
            amount: 12.3,
            currency: "usd",
            periodLabel: "Current month",
            capturedAt: now,
            freshness: .live
        )

        #expect(APISpendPresentation.amountText(balance) == "$42.10 left")
        #expect(APISpendPresentation.contextLabel(kind: .balance, periodLabel: balance.periodLabel) == "Remaining balance")
        #expect(APISpendPresentation.amountText(spend) == "$12.30")
        #expect(APISpendPresentation.contextLabel(kind: .periodSpend, periodLabel: spend.periodLabel) == "Current month")
    }

    @Test func statusTextUsesFreshness() {
        #expect(APISpendPresentation.statusText(freshness: WidgetProviderFreshness.pending, capturedAt: nil, now: now) == "Waiting for cost data")
        #expect(APISpendPresentation.statusText(freshness: WidgetProviderFreshness.live, capturedAt: now.addingTimeInterval(-60), now: now) == "Updated 1 min ago")
        #expect(APISpendPresentation.statusText(
            freshness: WidgetProviderFreshness.stale(message: "Add API key", needsAttention: true),
            capturedAt: now,
            now: now
        ) == "Set up on Mac")
        #expect(APISpendPresentation.statusText(
            freshness: WidgetProviderFreshness.stale(message: "Temporary issue", needsAttention: false),
            capturedAt: now.addingTimeInterval(-120),
            now: now
        ) == "Updated 2 min ago")
        #expect(APISpendPresentation.statusText(
            freshness: WidgetProviderFreshness.stale(message: "Temporary issue", needsAttention: false),
            capturedAt: nil,
            now: now
        ) == "Not updated")
    }

    @Test func companionStatusMatchesCurrentMacRows() {
        #expect(APISpendPresentation.companionStatusText(freshness: .pending) == "Waiting for cost data")
        #expect(APISpendPresentation.companionStatusText(freshness: .live) == nil)
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Add API key", needsAttention: true)
        ) == "Needs setup")
        #expect(APISpendPresentation.companionStatusText(
            freshness: .stale(message: "Temporary issue", needsAttention: false)
        ) == "Stale")
    }
}
