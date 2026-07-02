import Foundation

/// Reads the Codex credential. Injected so tests use fixture data instead of the
/// real `~/.codex/auth.json`.
public protocol CodexAuthReading: Sendable {
    func readCodexCredential() throws -> CodexCredential
}

/// Parses `~/.codex/auth.json`. Structure:
/// `{ auth_mode, OPENAI_API_KEY, tokens: { access_token, id_token, refresh_token,
/// account_id }, last_refresh }`.
public enum CodexAuthBlob {
    public static func parse(_ data: Data) throws -> CodexCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CredentialError.malformed }
        guard
            let tokens = root["tokens"] as? [String: Any],
            let access = tokens["access_token"] as? String
        else { throw CredentialError.malformed }
        let lastRefresh = (root["last_refresh"] as? String)
            .flatMap { ISO8601DateFormatter().date(from: $0) }
        return CodexCredential(
            accessToken: access,
            refreshToken: tokens["refresh_token"] as? String,
            accountID: tokens["account_id"] as? String,
            lastRefresh: lastRefresh
        )
    }
}

/// Production reader for `~/.codex/auth.json` (filesystem-gated, non-sandboxed — KTD2).
public struct CodexAuthFileReader: CodexAuthReading {
    private let path: URL
    public init(path: URL? = nil) {
        self.path = path
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
    }

    public func readCodexCredential() throws -> CodexCredential {
        guard let data = try? Data(contentsOf: path) else { throw CredentialError.notLoggedIn }
        return try CodexAuthBlob.parse(data)
    }
}
