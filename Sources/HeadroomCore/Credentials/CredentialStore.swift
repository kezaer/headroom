import Foundation

/// Codex credential access (U3). Claude no longer flows through here — it reads the
/// official `/usage` panel via the CLI (see `ClaudeProvider`), so the only remaining
/// credential is Codex's `~/.codex/auth.json` token. An `actor` for data-race-free
/// access under Swift 6 strict concurrency (KTD10).
public actor CredentialStore {
    private let codexReader: CodexAuthReading

    public init(codexReader: CodexAuthReading = CodexAuthFileReader()) {
        self.codexReader = codexReader
    }

    public func codexAccessToken() async -> Result<String, FailureReason> {
        do {
            return .success(try codexReader.readCodexCredential().accessToken)
        } catch CredentialError.notLoggedIn {
            return .failure(.notLoggedIn("Codex isn't logged in — run `codex`"))
        } catch {
            return .failure(.notLoggedIn("Codex credential unreadable"))
        }
    }
}
