import Foundation
import Testing
@testable import HeadroomCore

/// A real-shaped `.claude.json`: the official CLI writes `oauthAccount.emailAddress`
/// alongside a large amount of unrelated state, none of which Headroom decodes.
private let claudeAccountFileFixture = """
{
  "numStartups": 412,
  "installMethod": "native",
  "oauthAccount": {
    "accountUuid": "00000000-0000-0000-0000-000000000000",
    "emailAddress": "personal@example.com",
    "organizationName": "Personal"
  },
  "projects": { "/Users/test/repo": { "allowedTools": [] } }
}
"""

/// `tokens.id_token` from `~/.codex/auth.json`, header/payload/signature. The payload
/// segment is base64url with its padding stripped, exactly as a real JWT ships it.
private let codexIDTokenFixture =
    "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
    + ".eyJzdWIiOiJ1c2VyLTEyMyIsImVtYWlsIjoid29ya0BleGFtcGxlLmNvbSIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlfQ"
    + ".sig-not-verified"

/// Same token shape with no `email` claim.
private let codexIDTokenWithoutEmailFixture =
    "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyLTEyMyJ9.sig-not-verified"

private let usagePanel = """
Current session
██████ 12% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
███████████ 38% used
Resets Jul 2 at 10am (America/Los_Angeles)
"""

struct ClaudeAccountEmailTests {
    @Test func decodesOAuthAccountEmail() {
        #expect(ClaudeAccountBlob.email(in: Data(claudeAccountFileFixture.utf8)) == "personal@example.com")
    }

    @Test func missingOrBlankEmailYieldsNil() {
        for json in [
            "{}",                                        // no oauthAccount at all
            #"{ "oauthAccount": {} }"#,                  // signed out / key absent
            #"{ "oauthAccount": { "emailAddress": "  " } }"#,
            #"{ "oauthAccount": { "emailAddress": 42 } }"#,
            "not json at all",
        ] {
            #expect(ClaudeAccountBlob.email(in: Data(json.utf8)) == nil)
        }
    }

    @Test func fileReaderReturnsNilWhenFileIsMissing() {
        let reader = ClaudeAccountEmailFileReader(
            path: URL(fileURLWithPath: "/redacted/.claude.json"),
            readData: { _ in throw CocoaError(.fileNoSuchFile) }
        )
        #expect(reader.readAccountEmail() == nil)
    }

    @Test func fileReaderReadsTheAccountFileAtTheConfigHomeRoot() {
        // Built-in account: `~/.claude.json` at the home root, NOT inside `~/.claude/`.
        let home = URL(fileURLWithPath: "/Users/test")
        #expect(
            ClaudeAccountEmailFileReader.accountFileURL(configDirectory: nil, userHome: home).path
                == "/Users/test/.claude.json"
        )
        // Extra account: the root of its own CLAUDE_CONFIG_DIR.
        let configDirectory = URL(fileURLWithPath: "/Users/test/Accounts/claude/work/config")
        #expect(
            ClaudeAccountEmailFileReader.accountFileURL(configDirectory: configDirectory).path
                == "/Users/test/Accounts/claude/work/config/.claude.json"
        )
    }

    @Test func forAccountRoutesPrimaryToHomeRootAndExtrasToTheirConfigHome() {
        // `forAccount` is the one production resolver (ClaudeProvider's default
        // emailSource) — the branch below decides which account's email shows on
        // which card, so both sides are pinned.
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(
            ClaudeAccountEmailFileReader.forAccount(.primary).accountFilePath
                == home.appendingPathComponent(".claude.json").path
        )
        let extra = ClaudeAccountEmailFileReader.forAccount(AccountID("claude-work")).accountFilePath
        #expect(extra.hasSuffix("/Headroom/Accounts/claude/claude-work/config/.claude.json"))
    }

    @Test func providerPopulatesAccountEmailOnLiveSnapshots() async {
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .panel(text: usagePanel, planHint: "Max")),
            emailSource: StubClaudeEmailSource(email: "personal@example.com"),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "personal@example.com")
    }

    @Test func providerStillReportsUsageWhenTheEmailIsUnreadable() async {
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .panel(text: usagePanel, planHint: "Max")),
            emailSource: StubClaudeEmailSource(email: nil),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.windows.count == 2)
        #expect(snapshot.accountEmail == nil)
    }

    @Test func failedCaptureCarriesNoEmail() async {
        let provider = ClaudeProvider(
            source: MockClaudeSource(result: .loginRequired),
            emailSource: StubClaudeEmailSource(email: "personal@example.com")
        )
        #expect(await provider.fetchSnapshot().accountEmail == nil)
    }
}

struct CodexAccountEmailTests {
    @Test func decodesEmailClaimFromIDToken() throws {
        let json = """
        { "auth_mode": "chatgpt",
          "tokens": { "access_token": "at", "id_token": "\(codexIDTokenFixture)",
                      "refresh_token": "rt", "account_id": "acc" } }
        """
        let credential = try CodexAuthBlob.parse(Data(json.utf8))
        #expect(credential.accessToken == "at")
        #expect(credential.email == "work@example.com")
    }

    @Test func malformedOrClaimlessTokensYieldNilWithoutFailingTheCredential() throws {
        for token in [
            codexIDTokenWithoutEmailFixture,   // valid JWT, no email claim
            "not-a-jwt",                       // no segments
            "only.two",                        // wrong segment count
            "aaa.!!!not-base64!!!.bbb",        // payload isn't base64url
            "aaa.bm90IGpzb24.bbb",             // payload decodes but isn't JSON
            "aaa..bbb",                        // empty payload
        ] {
            let json = """
            { "tokens": { "access_token": "at", "id_token": "\(token)" } }
            """
            let credential = try CodexAuthBlob.parse(Data(json.utf8))
            #expect(credential.accessToken == "at")
            #expect(credential.email == nil)
        }
    }

    @Test func absentIDTokenYieldsNilEmail() throws {
        let credential = try CodexAuthBlob.parse(
            Data(#"{ "tokens": { "access_token": "at" } }"#.utf8)
        )
        #expect(credential.email == nil)
    }

    @Test func credentialStoreExposesEmailAlongsideTheToken() async {
        let store = CredentialStore(
            codexReader: MockCodexReader(
                credential: CodexCredential(
                    accessToken: "at", refreshToken: "rt", accountID: "acc",
                    lastRefresh: nil, email: "work@example.com"
                )
            )
        )
        #expect(
            await store.codexSession()
                == .success(CodexSession(accessToken: "at", accountEmail: "work@example.com"))
        )
        #expect(await store.codexAccessToken() == .success("at"))
    }

    @Test func providerPopulatesAccountEmailOnLiveSnapshots() async {
        let body = """
        { "plan_type": "prolite",
          "rate_limit": { "primary_window": { "used_percent": 10, "limit_window_seconds": 18000,
                                              "reset_at": 1783023708 } } }
        """
        let provider = CodexProvider(
            credentials: CredentialStore(
                codexReader: MockCodexReader(
                    credential: CodexCredential(
                        accessToken: "at", refreshToken: nil, accountID: nil,
                        lastRefresh: nil, email: "work@example.com"
                    )
                )
            ),
            http: MockFetcher(status: 200, body: body),
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.accountEmail == "work@example.com")
    }
}

struct AccountEmailContinuityTests {
    private let key = AccountKey(providerID: .claude, accountID: .primary)
    private let capturedAt = Date(timeIntervalSince1970: 2_000_000)

    private func priorSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            providerID: .claude,
            windows: [
                UsageWindow(
                    kind: .weekly,
                    utilization: 40,
                    resetsAt: Date(timeIntervalSince1970: 2_500_000),
                    resetLabel: "Resets Jul 2 at 10am"
                ),
            ],
            planLabel: "Max",
            accountEmail: "personal@example.com",
            capturedAt: capturedAt,
            freshness: .live
        )
    }

    @Test func staleMergePreservesLastKnownEmail() {
        let merged = UsageContinuityPolicy.mergedSnapshot(
            .stale(for: .claude, reason: .transient("Couldn't reach Claude")),
            with: priorSnapshot(),
            at: capturedAt.addingTimeInterval(300)
        )

        #expect(merged.planLabel == "Max")
        #expect(merged.accountEmail == "personal@example.com")
        #expect(merged.windows.count == 1)
    }

    /// Pins the settled semantics: identity mirrors `planLabel` exactly, so a live
    /// capture is always authoritative — a nil email on a good capture clears the
    /// line (rather than carrying a possibly signed-out address forward), and a
    /// fresh email always replaces the prior one.
    @Test func liveCaptureIsAuthoritativeForEmail() {
        let liveWithNilEmail = UsageSnapshot(
            providerID: .claude,
            windows: priorSnapshot().windows,
            planLabel: "Max",
            accountEmail: nil,
            capturedAt: capturedAt.addingTimeInterval(300),
            freshness: .live
        )
        let mergedNil = UsageContinuityPolicy.mergedSnapshot(
            liveWithNilEmail, with: priorSnapshot(), at: capturedAt.addingTimeInterval(300)
        )
        #expect(mergedNil.accountEmail == nil)

        let liveWithNewEmail = UsageSnapshot(
            providerID: .claude,
            windows: priorSnapshot().windows,
            planLabel: "Max",
            accountEmail: "work@example.com",
            capturedAt: capturedAt.addingTimeInterval(300),
            freshness: .live
        )
        let mergedNew = UsageContinuityPolicy.mergedSnapshot(
            liveWithNewEmail, with: priorSnapshot(), at: capturedAt.addingTimeInterval(300)
        )
        #expect(mergedNew.accountEmail == "work@example.com")
    }

    @Test func markedStalePreservesEmail() {
        #expect(priorSnapshot().markedStale(.transient("retrying")).accountEmail == "personal@example.com")
    }

    @Test func launchRestorationPreservesEmail() {
        let restored = UsageContinuityPolicy.restoredSnapshot(
            priorSnapshot(),
            for: .claude,
            at: capturedAt.addingTimeInterval(600)
        )
        #expect(restored.accountEmail == "personal@example.com")
    }

    @Test func cacheRoundTripPreservesEmail() {
        let defaults = UserDefaults(suiteName: "AccountEmailContinuityTests-\(UUID().uuidString)")!
        let cache = UsageContinuityCache(defaults: defaults)
        cache.save(priorSnapshot(), for: key)

        #expect(UsageContinuityCache(defaults: defaults).load()[key]?.accountEmail == "personal@example.com")
    }

    /// The widget schema stays single-account and identity-free: adding an email to
    /// `UsageSnapshot` must not leak into the exported widget payload.
    @Test func widgetProjectionCarriesNoEmail() throws {
        let envelope = WidgetSnapshotProjector.project(
            snapshots: [.claude: priorSnapshot()],
            providerOrder: [.claude],
            displayNames: [.claude: "Claude"],
            renewalDate: { _ in nil },
            widgetsEnabled: true
        )
        let encoded = try JSONEncoder().encode(envelope)

        #expect(envelope.providers.first?.planLabel == "Max")
        #expect(!String(decoding: encoded, as: UTF8.self).contains("personal@example.com"))
    }
}

/// Claude email-source double — keeps the provider tests off the real `.claude.json`.
private struct StubClaudeEmailSource: ClaudeAccountEmailReading {
    let email: String?
    func readAccountEmail() -> String? { email }
}
