import Testing
import Foundation
@testable import UsageBarCore

/// U5 test scenarios: Codex decode, unknown plan_type (#709 guard), additional
/// rate limits → `.other`, missing token, 401→reauth, network error.
struct CodexProviderTests {
    private func provider(_ fetcher: MockFetcher, credential: CodexCredential? = CodexCredential(accessToken: "at", refreshToken: "rt", accountID: "acc", lastRefresh: nil)) -> CodexProvider {
        let store = CredentialStore(codexReader: MockCodexReader(credential: credential))
        return CodexProvider(credentials: store, http: fetcher,
                             now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    @Test func decodesLiveResponse() async {
        let json = """
        { "rate_limit": {
            "primary_window": {"used_percent": 30, "reset_at": 1783023708},
            "secondary_window": {"used_percent": 55, "reset_at": "2026-07-08T00:00:00Z"} },
          "plan_type": "pro" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "pro")
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 70)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 45)
    }

    @Test func unknownPlanTypeDecodesLeniently() async {
        // A new plan_type value (the CodexBar #709 break) passes through as a string
        // and does not fail the snapshot.
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 5, "reset_at": "2026-07-02T12:00:00Z"} },
          "plan_type": "prolite" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "prolite")
    }

    @Test func additionalRateLimitsSurfaceAsOther() async {
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 5, "reset_at": "2026-07-02T12:00:00Z"} },
          "additional_rate_limits": [ {"limit_name": "codex-spark", "rate_limit": {
              "primary_window": {"used_percent": 12, "reset_after_seconds": 3600},
              "secondary_window": {"used_percent": 22, "reset_at": 1783023708}
          }} ],
          "plan_type": "pro" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.windows.contains { $0.kind == .other("codex-spark 5h") })
        #expect(snap.windows.contains { $0.kind == .other("codex-spark weekly") })
    }

    @Test func legacyResetFieldNamesStillDecode() async {
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 5, "resets_at": "2026-07-02T12:00:00Z"} },
          "additional_rate_limits": [ {"label": "legacy", "utilization": 12, "resets_in_seconds": 3600} ] }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.contains { $0.kind == .other("legacy") })
    }

    @Test func missingTokenIsNotLoggedIn() async {
        let snap = await provider(MockFetcher(status: 200, body: "{}"), credential: nil).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.isPermanent)
    }

    @Test func unauthorizedSaysRunCodex() async {
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 401, body: Data()))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason == .needsReauth("Session expired — run `codex` to refresh"))
    }

    @Test func networkErrorIsTransient() async {
        let snap = await provider(MockFetcher([.failure(.transient("Network unavailable"))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(!reason.isPermanent)
    }

    @Test func redirectsAreBlocked() {
        // R12: the session delegate (used by the Codex HTTP client) refuses redirects,
        // so the Authorization header can never be forwarded to another host.
        let blocker = RedirectBlocker()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://chatgpt.com")!)
        let response = HTTPURLResponse(url: URL(string: "https://chatgpt.com")!,
                                       statusCode: 302, httpVersion: nil, headerFields: nil)!
        var handed: URLRequest? = URLRequest(url: URL(string: "https://evil.example.com")!)
        blocker.urlSession(session, task: task, willPerformHTTPRedirection: response,
                           newRequest: URLRequest(url: URL(string: "https://evil.example.com")!)) { req in
            handed = req
        }
        #expect(handed == nil)
    }
}
