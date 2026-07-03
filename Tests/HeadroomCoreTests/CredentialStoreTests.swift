import Testing
import Foundation
@testable import HeadroomCore

/// U3 test scenarios (Codex only — Claude no longer uses credentials): auth.json
/// parsing, absent-credential handling, redaction.
struct CredentialStoreTests {
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
        #expect(throws: CredentialError.malformed) {
            try CodexAuthBlob.parse(Data("{ \"auth_mode\": \"chatgpt\" }".utf8))
        }
    }

    @Test func codexTokenReturnedWhenPresent() async {
        let cred = CodexCredential(accessToken: "at", refreshToken: "rt", accountID: "acc", lastRefresh: nil)
        let store = CredentialStore(codexReader: MockCodexReader(credential: cred))
        #expect(await store.codexAccessToken() == .success("at"))
    }

    @Test func codexMissingCredentialYieldsNotLoggedIn() async {
        let store = CredentialStore(codexReader: MockCodexReader(credential: nil))
        let result = await store.codexAccessToken()
        guard case .failure(let reason) = result else { Issue.record("expected failure"); return }
        #expect(reason.isPermanent)
    }

    @Test func redactionHidesTokens() {
        let leaked = "Authorization: Bearer sk-ant-sid01-abcDEF1234567890abcDEF1234567890xyz"
        let out = Redaction.redact(leaked)
        #expect(!out.contains("sk-ant-sid01-abcDEF1234567890abcDEF1234567890xyz"))
        #expect(out.contains("‹redacted›"))
    }
}
