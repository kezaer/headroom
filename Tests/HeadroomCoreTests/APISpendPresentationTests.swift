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
}
