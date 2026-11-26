import Testing
import Foundation
@testable import PacemarkCore

private final class SequencedCodexReader: CodexAuthReading, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String]
    private let reloadFailure: CredentialError?
    private var reads = 0

    init(tokens: [String], reloadFailure: CredentialError? = nil) {
        self.tokens = tokens
        self.reloadFailure = reloadFailure
    }

    var readCount: Int { lock.withLock { reads } }

    func readCodexCredential() throws -> CodexCredential {
        try lock.withLock {
            reads += 1
            if reads > 1, let reloadFailure { throw reloadFailure }
            let token = tokens[0]
            if tokens.count > 1 { tokens.removeFirst() }
            return CodexCredential(
                accessToken: token, refreshToken: nil, accountID: "fixture", lastRefresh: nil,
                email: "\(token)@example.invalid"
            )
        }
    }
}

/// U5 test scenarios: Codex decode, unknown plan_type (#709 guard), additional
/// rate limits → `.other`, missing token, 401→reauth, network error.
struct CodexProviderTests {
    private func provider(_ fetcher: MockFetcher, credential: CodexCredential? = CodexCredential(accessToken: "at", refreshToken: "rt", accountID: "acc", lastRefresh: nil)) -> CodexProvider {
        let store = CredentialStore(codexReader: MockCodexReader(credential: credential))
        return CodexProvider(credentials: store, http: fetcher,
                             now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private func fixture(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // Shape mirrors a real chatgpt.com/backend-api/wham/usage capture: each window carries
    // `limit_window_seconds` (18000 = 5h, 604800 = 7d) and `reset_at` as an epoch number.
    @Test func decodesLiveResponse() async {
        let json = """
        { "rate_limit": {
            "primary_window": {"used_percent": 30, "limit_window_seconds": 18000, "reset_at": 1783023708},
            "secondary_window": {"used_percent": 55, "limit_window_seconds": 604800, "reset_at": "2026-07-08T00:00:00Z"} },
          "plan_type": "pro" }
        """
        let snap = await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "pro")
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 70)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 45)
    }

    // Regression (#codex-window-kind): the "prolite" plan returns its weekly window in
    // `primary_window` with `secondary_window: null`. Keying off the slot mislabeled it
    // "5-hour" and dropped the weekly row; keying off `limit_window_seconds` fixes it.
    @Test func realProliteCaptureLabelsPrimaryWindowAsWeekly() async throws {
        let body = try fixture(named: "codex-wham-usage-prolite")
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 200, body: body))])).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.planLabel == "prolite")
        #expect(snap.windows.count == 2)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 67)
        #expect(!snap.windows.contains { $0.kind == .fiveHour })
        #expect(snap.windows.contains { $0.kind == .other("GPT-5.3-Codex-Spark Weekly") })
        #expect(!snap.windows.contains { $0.kind == .other("GPT-5.3-Codex-Spark 5h") })
    }

    @Test func realProliteCaptureContainsOnlyRedactedIdentity() throws {
        let body = try fixture(named: "codex-wham-usage-prolite")
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["user_id"] as? String == "<REDACTED_USER_ID>")
        #expect(json["account_id"] as? String == "<REDACTED_ACCOUNT_ID>")
        #expect(json["email"] as? String == "redacted@example.invalid")
    }

    @Test func unknownDeclaredDurationIsNotForcedIntoKnownKind() {
        #expect(CodexWindowClassifier.kind(limitWindowSeconds: 21_600, positionalDefault: .fiveHour) == .other("6h"))
        #expect(CodexWindowClassifier.kind(limitWindowSeconds: 691_200, positionalDefault: .weekly) == .other("8d"))
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
        // No `limit_window_seconds` here → positional fallback; suffix comes from
        // `WindowKind.shortLabel` ("5h"/"Weekly"), consistent with the main windows.
        #expect(snap.windows.contains { $0.kind == .other("codex-spark 5h") })
        #expect(snap.windows.contains { $0.kind == .other("codex-spark Weekly") })
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

    @Test func unchangedUnauthorizedSessionRemainsRetryableWithManualSignInAvailable() async {
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 401, body: Data()))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .codexSessionUnverified)
        #expect(!reason.isPermanent)
        #expect(reason.providerSetupOutcome?.recoveryPresentation.primaryAction == .checkNow)
        #expect(reason.providerSetupOutcome?.recoveryPresentation.secondaryAction == .reconnectCodex)
    }

    @Test func unauthorizedReloadsSessionRenewedByOfficialClientBeforeRequestingSignIn() async {
        let reader = SequencedCodexReader(tokens: ["expired", "renewed"])
        let fetcher = MockFetcher([
            .success(HTTPResult(status: 401, body: Data())),
            .success(HTTPResult(status: 200, body: Data(#"{"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":18000,"reset_after_seconds":3600}}}"#.utf8))),
        ])
        let provider = CodexProvider(credentials: CredentialStore(codexReader: reader), http: fetcher)

        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "renewed@example.invalid")
        #expect(fetcher.requestCount == 2)
        #expect(fetcher.lastHeaders["Authorization"] == "Bearer renewed")
    }

    @Test func unauthorizedDoesNotRetryUnchangedSessionOrLoopOnAnotherRejection() async {
        for tokens in [["expired", "expired"], ["expired", "renewed", "third"]] {
            let fetcher = MockFetcher([.success(HTTPResult(status: 401, body: Data()))])
            let provider = CodexProvider(
                credentials: CredentialStore(codexReader: SequencedCodexReader(tokens: tokens)),
                http: fetcher
            )

            let snapshot = await provider.fetchSnapshot()

            let expected: ProviderSetupOutcome = tokens[1] == tokens[0] ? .codexSessionUnverified : .codexRejectedAuth
            #expect(snapshot.freshness == .stale(.providerSetup(expected)))
            #expect(fetcher.requestCount == (tokens[1] == tokens[0] ? 1 : 2))
        }
    }

    @Test func unauthorizedReloadPreservesCredentialFailureInsteadOfClaimingRevocation() async {
        let cases: [(CredentialError, ProviderSetupOutcome)] = [
            (.permissionDenied, .codexPermissionDenied),
            (.unsafePermissions, .codexUnsafePermissions),
            (.malformed, .codexMalformedAuth),
            (.ioFailure, .codexCredentialIO),
            (.notLoggedIn, .codexAuthAbsent),
        ]
        for (error, expected) in cases {
            let reader = SequencedCodexReader(tokens: ["expired"], reloadFailure: error)
            let fetcher = MockFetcher(status: 401, body: "{}")
            let provider = CodexProvider(credentials: CredentialStore(codexReader: reader), http: fetcher)

            let snapshot = await provider.fetchSnapshot()

            #expect(snapshot.freshness == .stale(.providerSetup(expected)))
            #expect(fetcher.requestCount == 1)
            #expect(reader.readCount == 2)
        }
    }

    @Test func failureAfterReloadRetainsItsMeaningAndDoesNotReadOrRetryAgain() async {
        let cases: [Result<HTTPResult, FailureReason>] = [
            .failure(.transient("Network unavailable")),
            .success(HTTPResult(status: 429, body: Data())),
            .success(HTTPResult(status: 503, body: Data())),
            .success(HTTPResult(status: 200, body: Data("not JSON".utf8))),
        ]
        for response in cases {
            let reader = SequencedCodexReader(tokens: ["expired", "renewed", "third"])
            let fetcher = MockFetcher([.success(HTTPResult(status: 401, body: Data())), response])
            let provider = CodexProvider(credentials: CredentialStore(codexReader: reader), http: fetcher)
            // The ordinary path is the semantic oracle for the same final result.
            let baseline = await self.provider(MockFetcher([response])).fetchSnapshot()

            let snapshot = await provider.fetchSnapshot()

            #expect(snapshot.freshness == baseline.freshness)
            #expect(fetcher.requestCount == 2)
            #expect(reader.readCount == 2)
            #expect(fetcher.lastHeaders["Authorization"] == "Bearer renewed")
        }
    }

    @Test func successfulAndNonUnauthorizedRequestsDoNotTriggerCredentialReload() async {
        for status in [200, 403, 429, 503] {
            let reader = SequencedCodexReader(tokens: ["current", "unused"])
            let fetcher = MockFetcher(status: status, body: "{}")
            let provider = CodexProvider(credentials: CredentialStore(codexReader: reader), http: fetcher)

            _ = await provider.fetchSnapshot()

            #expect(fetcher.requestCount == 1)
            #expect(reader.readCount == 1)
        }
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

    // MARK: - Banked resets (R1, R2, R3)

    @Test func proliteFixtureCarriesTwoBankedResetsWithoutChangingWindows() async throws {
        let body = try fixture(named: "codex-wham-usage-prolite")
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 200, body: body))])).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 2)
        #expect(snap.codexResetCreditsField == .count(2))
        #expect(snap.windows.count == 2)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 67)
        #expect(snap.codexBankedResetProbeLine == "banked resets: 2")
    }

    @Test func positiveCountOnlyUsesListEndpointOnceAcrossPolls() async throws {
        let usage = try fixture(named: "codex-wham-usage-prolite")
        let list = Data(#"{"credits":[{"expires_at":"2030-02-03T00:00:00.123456Z"},{}]}"#.utf8)
        let http = MockFetcher([usage, list, usage].map { .success(HTTPResult(status: 200, body: $0)) })
        let source = provider(http)
        let first = await source.fetchSnapshot()
        let second = await source.fetchSnapshot()
        #expect(first.bankedCreditDetails?.credits.count == 2)
        #expect(first.bankedCreditDetails?.credits.first?.expiresAt != nil)
        #expect(first.bankedCreditDetails == second.bankedCreditDetails)
        #expect(ResetCreditEndpoint.allCases.map(\.url.path) == ["/backend-api/wham/rate-limit-reset-credits"])
        #expect(http.requestedURLs == [CodexProvider.endpoint, ResetCreditEndpoint.list.url, CodexProvider.endpoint])
    }

    @Test func detailCacheThrottlesFailuresAndExpiresLastGoodDates() async {
        let cache = ResetCreditCache()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let credit = BankedCreditDetails.Credit(expiresAt: now.addingTimeInterval(100_000), grantedAt: nil)
        let first = await cache.read(count: 1, identity: nil, now: now) { [credit] }
        let unchanged = await cache.read(count: 1, identity: nil, now: now.addingTimeInterval(21599)) {
            Issue.record("Unchanged count fetched early")
            return nil
        }
        #expect(first == unchanged)
        let changed = await cache.read(count: 2, identity: nil, now: now.addingTimeInterval(21599)) { [credit, credit] }
        #expect(changed?.credits.count == 2)
        let latest = await cache.read(count: 2, identity: nil, now: now.addingTimeInterval(43199)) { nil }
        #expect(latest == changed)
        #expect(BankedCreditDetails.tip(count: 2, details: latest, now: now.addingTimeInterval(107999))
            == "2 banked resets\nExpiry not available yet.")
        let zero = await cache.read(count: 0, identity: nil, now: now) {
            Issue.record("Zero count fetched details")
            return nil
        }
        #expect(zero == nil)
    }

    @Test func countOnlyResetCreditsNeedNoExpirationDate() async {
        let snapshot = await live(credits: #"{ "available_count": 4, "applicable_available_count": 4 }"#)
        #expect(snapshot.bankedResets == 4)
        #expect(snapshot.freshness == .live)
    }

    @Test func nullResetCreditsObjectIsReportedZero() async {
        let snap = await live(credits: "null")
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 0)
        #expect(snap.codexResetCreditsField == .nullObject)
        #expect(snap.codexBankedResetProbeLine == "banked resets: null (reported zero)")
    }

    @Test func omittedResetCreditsKeyIsNotReported() async {
        let snap = await live()
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.codexResetCreditsField == .absent)
        #expect(snap.codexBankedResetProbeLine == "banked resets: absent (field not present)")
    }

    @Test func fractionalAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "available_count": 2.5 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.windows.isEmpty == false)
    }

    @Test func missingAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "limit_name": "spare" }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
    }

    @Test func zeroAvailableCountIsReportedZero() async {
        let snap = await live(credits: #"{ "available_count": 0 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 0)
        #expect(snap.codexResetCreditsField == .count(0))
        #expect(snap.codexBankedResetProbeLine == "banked resets: 0")
    }

    @Test func overflowingAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "available_count": 1e100 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.codexResetCreditsField == .notReported)
    }

    @Test func negativeAvailableCountIsNotReported() async {
        let snap = await live(credits: #"{ "available_count": -1 }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
    }

    @Test func stringAvailableCountDecodesFlexibly() async {
        let snap = await live(credits: #"{ "available_count": "2" }"#)
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == 2)
    }

    @Test func nonObjectResetCreditsDoesNotFailTheBody() async {
        let snap = await live(credits: "\"unexpected\"")
        #expect(snap.freshness == .live)
        #expect(snap.bankedResets == nil)
        #expect(snap.windows.contains { $0.kind == .fiveHour })
    }

    @Test func snapshotTransformsPreserveOrDropTheCount() {
        let live = UsageSnapshot(
            providerID: .codex,
            windows: [],
            planLabel: "plus",
            bankedResets: 2,
            capturedAt: Date(timeIntervalSince1970: 1),
            freshness: .live
        )
        let stale = live.markedStale(.transient("offline"))
        #expect(stale.bankedResets == 2)
        #expect(stale.freshness != .live)
        #expect(live.fiveHourFirst().bankedResets == 2)
        #expect(UsageSnapshot.pending(for: .codex).bankedResets == nil)
        #expect(UsageSnapshot.stale(for: .codex, reason: .transient("x")).bankedResets == nil)
    }

    @Test func unverifiedSessionCarriesNoCount() async {
        let snap = await provider(MockFetcher([.success(HTTPResult(status: 401, body: Data()))])).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .codexSessionUnverified)
        #expect(!reason.isPermanent)
        #expect(snap.bankedResets == nil)
    }

    private func live(credits: String? = nil) async -> UsageSnapshot {
        let field = credits.map { ", \"rate_limit_reset_credits\": \($0)" } ?? ""
        let json = """
        { "rate_limit": { "primary_window": {"used_percent": 30, "limit_window_seconds": 18000, "reset_at": 1783023708} },
          "plan_type": "plus"\(field) }
        """
        return await provider(MockFetcher(status: 200, body: json)).fetchSnapshot()
    }
}


struct BankedCreditTipTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [(59, "59m"), (60, "1h 0m"), (1439, "23h 59m"), (1440, "1d 0h")])
    func duration(_ example: (Int, String)) {
        let tip = render([now.addingTimeInterval(Double(example.0 * 60))])
        #expect(tip.hasPrefix("1 banked reset\nExpires in:\n"))
        #expect(tip.hasSuffix(" · " + example.1))
    }

    @Test func sortedCappedAndUnknown() {
        let dates = (1...10).map { now.addingTimeInterval(Double($0 * 60)) }
        let lines = render(Array(dates.reversed())).components(separatedBy: "\n")
        #expect(lines.count == 11)
        #expect(lines[2].hasSuffix(" · 1m"))
        #expect(lines[9].hasSuffix(" · 8m"))
        #expect(lines.last == "+2 more")
        #expect(render([nil]) == "1 banked reset\nExpiry not available yet.")
    }

    @Test func respectsLocaleHourCycle() {
        let date = Date(timeIntervalSince1970: 1_000_000 + 86400) // 13:46 UTC
        #expect(render([date], locale: "en_US").contains("1:46"))
        #expect(render([date], locale: "en_GB").contains("13:46"))
    }

    private func render(_ dates: [Date?], locale: String = "en_US") -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = .gmt
        let details = BankedCreditDetails(credits: dates.map { .init(expiresAt: $0, grantedAt: nil) }, observedAt: now)
        return BankedCreditDetails.tip(count: dates.count, details: details, now: now, calendar: calendar)
    }
}
