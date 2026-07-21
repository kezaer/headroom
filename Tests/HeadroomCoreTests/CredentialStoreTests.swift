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
        #expect(reason.providerSetupOutcome == .codexAuthAbsent)
    }

    @Test func codexFileReaderDistinguishesAbsentPermissionMalformedAndIO() throws {
        let path = URL(fileURLWithPath: "/redacted/auth.json")

        for (error, expected) in [
            (CocoaError(.fileNoSuchFile), CredentialError.notLoggedIn),
            (CocoaError(.fileReadNoPermission), CredentialError.permissionDenied),
            (CocoaError(.fileReadUnknown), CredentialError.ioFailure),
        ] {
            let reader = CodexAuthFileReader(path: path, readData: { _ in throw error })
            #expect(throws: expected) { try reader.readCodexCredential() }
        }

        let malformed = CodexAuthFileReader(
            path: path,
            readData: { _ in Data("{}".utf8) },
            permissionsAreSafe: { _ in true }
        )
        #expect(throws: CredentialError.malformed) { try malformed.readCodexCredential() }
    }

    @Test func codexFileReaderRejectsUnsafeCredentialPermissions() {
        let data = Data("""
        { "tokens": { "access_token": "sensitive" } }
        """.utf8)
        let reader = CodexAuthFileReader(
            path: URL(fileURLWithPath: "/redacted/auth.json"),
            readData: { _ in data },
            permissionsAreSafe: { _ in false }
        )

        #expect(throws: CredentialError.unsafePermissions) {
            try reader.readCodexCredential()
        }
    }

    @Test func credentialStoreMapsCodexFileFailuresToTypedSetupOutcomes() async {
        for (error, expected) in [
            (CredentialError.permissionDenied, ProviderSetupOutcome.codexPermissionDenied),
            (CredentialError.unsafePermissions, .codexUnsafePermissions),
            (CredentialError.malformed, .codexMalformedAuth),
            (CredentialError.ioFailure, .codexCredentialIO),
        ] {
            let store = CredentialStore(codexReader: ThrowingCodexReader(error: error))
            guard case .failure(let reason) = await store.codexAccessToken() else {
                Issue.record("expected failure")
                continue
            }
            #expect(reason.providerSetupOutcome == expected)
        }
    }

    @Test func redactionHidesTokens() {
        let leaked = "Authorization: Bearer sk-ant-sid01-abcDEF1234567890abcDEF1234567890xyz"
        let out = Redaction.redact(leaked)
        #expect(!out.contains("sk-ant-sid01-abcDEF1234567890abcDEF1234567890xyz"))
        #expect(out.contains("‹redacted›"))
    }

    @Test func apiKeysRoundTripThroughStore() async {
        let apiKeys = MockAPIKeyStore()
        let store = CredentialStore(codexReader: MockCodexReader(credential: nil), apiKeyStore: apiKeys)

        if case .failure(let reason) = await store.saveAPIKey(" sk-test ", for: .openAI) {
            Issue.record("save failed: \(reason.message)")
        }
        #expect(await store.apiKey(for: .openAI) == .success("sk-test"))
        if case .failure(let reason) = await store.deleteAPIKey(for: .openAI) {
            Issue.record("delete failed: \(reason.message)")
        }

        guard case .failure(let reason) = await store.apiKey(for: .openAI) else {
            Issue.record("expected missing API key")
            return
        }
        #expect(reason.isPermanent)
    }

    @Test func apiKeyStoreErrorsAreRedacted() async {
        let apiKeys = MockAPIKeyStore()
        apiKeys.shouldFail = true
        let store = CredentialStore(codexReader: MockCodexReader(credential: nil), apiKeyStore: apiKeys)
        guard case .failure(let reason) = await store.apiKey(for: .anthropic) else {
            Issue.record("expected failure")
            return
        }
        #expect(!reason.message.contains("sk-"))
    }
}

private struct ThrowingCodexReader: CodexAuthReading {
    let error: CredentialError
    func readCodexCredential() throws -> CodexCredential { throw error }
}
