import Foundation

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

/// API/admin key providers for metered spend reports. These are app-owned secrets and
/// separate from subscription credentials or CLI login state.
public enum APIKeyProvider: String, Sendable, CaseIterable {
    case openAI
    case anthropic
    case xAI

    var keychainService: String {
        switch self {
        case .openAI: return "Headroom OpenAI Admin API Key"
        case .anthropic: return "Headroom Anthropic Admin API Key"
        case .xAI: return "Headroom xAI Management API Key"
        }
    }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .xAI: return "xAI API"
        }
    }

    public var providerID: ProviderID {
        switch self {
        case .openAI: return .codex
        case .anthropic: return .claude
        case .xAI: return .grok
        }
    }
}

public protocol APIKeyStoring: Sendable {
    func readAPIKey(for provider: APIKeyProvider) throws -> String
    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws
    func deleteAPIKey(for provider: APIKeyProvider) throws
}

/// Typed credential-access errors — distinct cases so the UI can tell "not logged
/// in / item absent" from "present but unreadable" (design + feasibility review).
public enum CredentialError: Error, Equatable {
    case notLoggedIn          // Keychain item / auth.json absent (errSecItemNotFound / ENOENT)
    case permissionDenied     // macOS denied access to an existing provider-owned file
    case unsafePermissions    // credential file is group/world-accessible
    case malformed            // present but unparseable
    case ioFailure            // present/unknown path state but another redacted read failure
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
