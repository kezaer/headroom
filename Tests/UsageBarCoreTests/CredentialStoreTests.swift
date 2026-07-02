import Testing
import Foundation
@testable import UsageBarCore

/// U3 test scenarios: credential parsing, token precedence, single-flight refresh,
/// absent-item handling, redaction.
struct CredentialStoreTests {
    // MARK: parsing

    @Test func codexAuthParsesTokens() throws {
        let json = """
        { "auth_mode": "chatgpt", "OPENAI_API_KEY": null,
          "tokens": { "access_token": "at", "id_token": "it",
                      "refresh_token": "rt", "account_id": "acc" },
          "last_refresh": "2026-07-01T13:44:00Z" }
        """
        let cred = try CodexAuthBlob.parse(Data(json.utf8))
        #expect(cred.accessToken == "at")
        #expect(cred.refreshToken == "rt")
        #expect(cred.accountID == "acc")
    }

    @Test func codexAuthMissingTokensThrowsMalformed() {
        let json = "{ \"auth_mode\": \"chatgpt\" }"
        #expect(throws: CredentialError.malformed) {
            try CodexAuthBlob.parse(Data(json.utf8))
        }
    }

    @Test func claudeBlobParsesNested() throws {
        let json = """
        { "claudeAiOauth": { "accessToken": "a", "refreshToken": "r",
          "expiresAt": 4102444800000 } }
        """
        let cred = try ClaudeCredentialBlob.parse(Data(json.utf8))
        #expect(cred.accessToken == "a")
        #expect(cred.refreshToken == "r")
        #expect(cred.expiresAt > Date(timeIntervalSince1970: 4_000_000_000))
    }

    @Test func claudeBlobMalformedThrows() {
        #expect(throws: CredentialError.malformed) {
            try ClaudeCredentialBlob.parse(Data("not json".utf8))
        }
    }

    // MARK: store behavior

    @Test func missingKeychainItemYieldsNotLoggedIn() async {
        // errSecItemNotFound surfaces as a typed notLoggedIn, distinct from malformed.
        let store = CredentialStore(keychain: MockKeychain(claudeCode: nil),
                                    ownStore: MockKeychain(),
                                    codexReader: MockCodexReader())
        let result = await store.claudeAccessToken()
        guard case .failure(let reason) = result else { Issue.record("expected failure"); return }
        #expect(reason == .notLoggedIn("Claude Code isn't logged in — run `claude`"))
    }

    @Test func validTokenReturnedWithoutRefresh() async {
        let kc = MockKeychain(claudeCode: .valid())
        let store = CredentialStore(keychain: kc, ownStore: MockKeychain(), codexReader: MockCodexReader())
        let result = await store.claudeAccessToken()
        #expect(result == .success("access-tok"))
    }

    @Test func tokenPrecedenceReadsBootstrapOnce() async {
        // After the first (bootstrap) read, the cached token serves subsequent calls
        // — the Claude Code item is not re-read on every cycle.
        let kc = MockKeychain(claudeCode: .valid())
        let store = CredentialStore(keychain: kc, ownStore: MockKeychain(), codexReader: MockCodexReader())
        _ = await store.claudeAccessToken()
        _ = await store.claudeAccessToken()
        let count = await store.bootstrapReadCount
        #expect(count == 1)
        #expect(kc.claudeCodeReadCount == 1)
    }

    @Test func concurrentExpiredTokenRefreshesOnce() async {
        // Single-flight: two concurrent callers with an expired token trigger exactly
        // one refresh against the (possibly single-use) refresh token.
        let refresher = MockRefresher(result: .failure(.needsReauth("re-login")))
        refresher.delay = .milliseconds(30)
        let store = CredentialStore(
            keychain: MockKeychain(claudeCode: .expired()),
            ownStore: MockKeychain(),
            codexReader: MockCodexReader(),
            refresher: refresher
        )
        async let a = store.claudeAccessToken()
        async let b = store.claudeAccessToken()
        _ = await (a, b)
        #expect(refresher.callCount == 1)
    }

    @Test func codexMissingCredentialYieldsNotLoggedIn() async {
        let store = CredentialStore(keychain: MockKeychain(), ownStore: MockKeychain(),
                                    codexReader: MockCodexReader(credential: nil))
        let result = await store.codexAccessToken()
        guard case .failure(let reason) = result else { Issue.record("expected failure"); return }
        #expect(reason.isPermanent) // notLoggedIn is permanent-until-login
    }

    // MARK: redaction

    @Test func redactionHidesTokens() {
        let leaked = "Authorization: Bearer sk-ant-sid01-abcDEF1234567890abcDEF1234567890xyz"
        let out = Redaction.redact(leaked)
        #expect(!out.contains("sk-ant-sid01-abcDEF1234567890abcDEF1234567890xyz"))
        #expect(out.contains("‹redacted›"))
    }
}
