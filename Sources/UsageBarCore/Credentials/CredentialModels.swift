import Foundation

/// Claude Code OAuth credential as stored in the `Claude Code-credentials` login
/// Keychain item. Blob schema is from the Claude-Usage-Tracker precedent and must be
/// confirmed by the U9 spike (Q1/Q4).
public struct ClaudeCredential: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Codex credential from `~/.codex/auth.json` → `tokens`.
public struct CodexCredential: Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountID: String?
    public let lastRefresh: Date?
    public init(accessToken: String, refreshToken: String?, accountID: String?, lastRefresh: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.lastRefresh = lastRefresh
    }
}

/// Typed credential-access errors — distinct cases so the UI can tell "not logged
/// in / item absent" from "present but unreadable" (design + feasibility review).
public enum CredentialError: Error, Equatable {
    case notLoggedIn          // Keychain item / auth.json absent (errSecItemNotFound / ENOENT)
    case malformed            // present but unparseable
    case keychainStatus(Int32)
}

extension CredentialError {
    /// Decodes a credential JSON blob into a top-level object, or throws `.malformed`.
    static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CredentialError.malformed }
        return obj
    }
}
