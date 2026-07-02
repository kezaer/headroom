import Testing
import Foundation
@testable import UsageBarCore

/// U4 test scenarios: Claude decode, lenient unknown fields, User-Agent format,
/// failure taxonomy (401→reauth, 403→scope, 429/network/decode→transient), and the
/// redirect-safety policy.
struct ClaudeProviderTests {
    private func storeWithValidToken() -> CredentialStore {
        CredentialStore(keychain: MockKeychain(claudeCode: .valid()),
                        ownStore: MockKeychain(), codexReader: MockCodexReader())
    }

    private func provider(_ fetcher: MockFetcher) -> ClaudeProvider {
        ClaudeProvider(credentials: storeWithValidToken(), http: fetcher,
                       version: { "2.0.0" }, now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    @Test func decodesLiveResponse() async {
        let json = """
        { "five_hour": {"utilization": 42.5, "resets_at": "2026-07-02T12:00:00Z"},
          "seven_day": {"utilization": 70, "resets_at": "2026-07-05T00:00:00Z"},
          "subscriptionType": "max" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "max")
        #expect(snap.windows.count == 2)
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 57.5)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 30)
    }

    @Test func toleratesUnknownWindowAndPlan() async {
        // Unknown extra window key + unknown subscriptionType still decodes known
        // windows (KTD6) — no total failure.
        let json = """
        { "five_hour": {"utilization": 10, "resets_at": "2026-07-02T12:00:00Z"},
          "seven_day": {"utilization": 20, "resets_at": "2026-07-05T00:00:00Z"},
          "seven_day_opus": {"utilization": 5, "resets_at": "2026-07-05T00:00:00Z"},
          "subscriptionType": "some_future_tier" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.count == 2)
        #expect(snap.planLabel == "some_future_tier")
    }

    @Test func sendsWellFormedUserAgent() async {
        let fetcher = MockFetcher(status: 200, body: """
        { "five_hour": {"utilization": 1, "resets_at": "2026-07-02T12:00:00Z"} }
        """)
        _ = await provider(fetcher).fetchSnapshot()
        let ua = fetcher.lastHeaders["User-Agent"] ?? ""
        #expect(ua.wholeMatch(of: /claude-code\/\d+\.\d+\.\d+/) != nil)
        #expect(fetcher.lastHeaders["anthropic-beta"] == "oauth-2025-04-20")
    }

    @Test func unauthorizedDegradesToReauth() async {
        // 401 → one refresh-and-retry; the default refresher can't safely refresh
        // (U9-pending), so it degrades to a permanent needs-reauth, not a retry loop.
        let snap = await provider(MockFetcher([
            .success(HTTPResult(status: 401, body: Data()))
        ])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason == .needsReauth("Session expired — run `claude` to re-login"))
        #expect(reason.isPermanent)
    }

    @Test func forbiddenIsScopeDenied() async {
        let snap = await provider(MockFetcher([
            .success(HTTPResult(status: 403, body: Data()))
        ])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        if case .scopeDenied = reason {} else { Issue.record("expected scopeDenied, got \(reason)") }
    }

    @Test func rateLimitedIsTransient() async {
        let snap = await provider(MockFetcher([
            .success(HTTPResult(status: 429, body: Data()))
        ])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(!reason.isPermanent)
    }

    @Test func malformedBodyIsDecodeStale() async {
        let snap = await provider(MockFetcher(status: 200, body: "not json at all")).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        if case .decode = reason {} else { Issue.record("expected decode, got \(reason)") }
    }

    @Test func networkErrorIsTransientStale() async {
        let snap = await provider(MockFetcher([.failure(.transient("Network unavailable"))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(!reason.isPermanent)
    }

    @Test func redirectsAreBlocked() {
        // R12: the client refuses redirects, so the Authorization header can never be
        // forwarded to another host.
        let client = RedirectBlockingHTTPClient()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://api.anthropic.com")!)
        let response = HTTPURLResponse(url: URL(string: "https://api.anthropic.com")!,
                                       statusCode: 302, httpVersion: nil, headerFields: nil)!
        var handed: URLRequest? = URLRequest(url: URL(string: "https://evil.example.com")!)
        client.urlSession(session, task: task, willPerformHTTPRedirection: response,
                          newRequest: URLRequest(url: URL(string: "https://evil.example.com")!)) { req in
            handed = req
        }
        #expect(handed == nil) // redirect refused
    }
}
