import Testing
import Foundation
@testable import HeadroomCore

struct APISpendProviderTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(_ provider: APIKeyProvider, key: String? = "key") -> CredentialStore {
        var keys: [APIKeyProvider: String] = [:]
        if let key { keys[provider] = key }
        return CredentialStore(
            codexReader: MockCodexReader(credential: nil),
            apiKeyStore: MockAPIKeyStore(keys: keys)
        )
    }

    @Test func openAISumsCostBuckets() async {
        let json = """
        { "object": "page", "data": [
          { "object": "bucket", "results": [
            { "object": "organization.costs.result", "amount": { "value": 0.06, "currency": "usd" } }
          ]},
          { "object": "bucket", "results": [
            { "object": "organization.costs.result", "amount": { "value": 1.25, "currency": "usd" } }
          ]}
        ] }
        """
        let fetcher = MockFetcher(status: 200, body: json)
        let provider = OpenAIAPISpendProvider(credentials: store(.openAI), http: fetcher, now: { now })
        let snap = await provider.fetchSpend(period: .currentMonth)
        #expect(snap.freshness == .live)
        #expect(snap.amount == 1.31)
        #expect(snap.currency == "usd")
        #expect(fetcher.lastHeaders["Authorization"] == "Bearer key")
        #expect(fetcher.lastURL?.query?.contains("bucket_width=1d") == true)
    }

    @Test func anthropicSumsCostReportRows() async {
        let json = """
        { "data": [
          { "results": [
            { "cost": { "amount": 2.5, "currency": "usd" } },
            { "amount": { "value": "0.50", "currency": "usd" } }
          ]}
        ] }
        """
        let fetcher = MockFetcher(status: 200, body: json)
        let provider = AnthropicAPISpendProvider(credentials: store(.anthropic), http: fetcher, now: { now })
        let snap = await provider.fetchSpend(period: .rolling30Days)
        #expect(snap.freshness == .live)
        #expect(snap.amount == 3.0)
        #expect(snap.currency == "usd")
        #expect(fetcher.lastHeaders["x-api-key"] == "key")
        #expect(fetcher.lastHeaders["anthropic-version"] == "2023-06-01")
        #expect(fetcher.lastURL?.query?.contains("starting_at=") == true)
    }

    @Test func missingAPIKeyIsPermanentStale() async {
        let provider = OpenAIAPISpendProvider(credentials: store(.openAI, key: nil), http: MockFetcher(status: 200, body: "{}"), now: { now })
        let snap = await provider.fetchSpend(period: .currentMonth)
        guard case .stale(let reason) = snap.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason.isPermanent)
    }

    @Test func explicitEmptyCostReportsAreZero() async {
        let openAI = OpenAIAPISpendProvider(
            credentials: store(.openAI),
            http: MockFetcher(status: 200, body: #"{"object":"page","data":[]}"#),
            now: { now }
        )
        let anthropic = AnthropicAPISpendProvider(
            credentials: store(.anthropic),
            http: MockFetcher(status: 200, body: #"{"data":[]}"#),
            now: { now }
        )

        let openAISnap = await openAI.fetchSpend(period: .currentMonth)
        let anthropicSnap = await anthropic.fetchSpend(period: .currentMonth)
        #expect(openAISnap.freshness == .live)
        #expect(openAISnap.amount == 0)
        #expect(anthropicSnap.freshness == .live)
        #expect(anthropicSnap.amount == 0)
    }

    @Test func permissionErrorsAreTyped() async {
        let provider = AnthropicAPISpendProvider(
            credentials: store(.anthropic),
            http: MockFetcher([.success(HTTPResult(status: 403, body: Data("secret body".utf8)))]),
            now: { now }
        )
        let snap = await provider.fetchSpend(period: .currentMonth)
        guard case .stale(let reason) = snap.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason == .scopeDenied("Anthropic key lacks cost report access"))
    }

    @Test func mixedCurrenciesDecodeAsStale() async {
        let json = """
        { "data": [ { "results": [
          { "amount": { "value": 1, "currency": "usd" } },
          { "amount": { "value": 1, "currency": "eur" } }
        ] } ] }
        """
        let provider = OpenAIAPISpendProvider(credentials: store(.openAI), http: MockFetcher(status: 200, body: json), now: { now })
        let snap = await provider.fetchSpend(period: .currentMonth)
        guard case .stale(let reason) = snap.freshness else {
            Issue.record("expected stale")
            return
        }
        #expect(reason == .decode("Couldn't read OpenAI cost response"))
    }
}
