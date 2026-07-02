import Foundation
import Security

/// Reads the Claude Code login-Keychain item. Injected so tests use fixtures and
/// never touch the real Keychain.
public protocol ClaudeCodeKeychainReading: Sendable {
    /// Reads `service = "Claude Code-credentials"`. Throws `.notLoggedIn` on
    /// `errSecItemNotFound`, `.malformed` on a bad blob.
    func readClaudeCodeCredential() throws -> ClaudeCredential
}

/// Reads/writes UsageBar's *own* Keychain item (the rotated-token store, KTD3).
public protocol OwnCredentialStoring: Sendable {
    func readOwnClaude() throws -> ClaudeCredential?
    func writeOwnClaude(_ credential: ClaudeCredential) throws
}

/// Parses the Claude Code credential JSON blob into a `ClaudeCredential`.
/// Shared by the real Keychain reader and tests. Tolerant of the two field-name
/// styles seen in the wild (`accessToken`/`access_token`).
public enum ClaudeCredentialBlob {
    public static func parse(_ data: Data) throws -> ClaudeCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw CredentialError.malformed }
        // The blob may nest under "claudeAiOauth" or sit at the root.
        let obj = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard
            let access = (obj["accessToken"] ?? obj["access_token"]) as? String,
            let refresh = (obj["refreshToken"] ?? obj["refresh_token"]) as? String
        else { throw CredentialError.malformed }
        let expiresAt = Self.expiry(from: obj["expiresAt"] ?? obj["expires_at"])
        return ClaudeCredential(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }

    /// `expiresAt` is commonly epoch-millis; also accept epoch-seconds and ISO strings.
    private static func expiry(from value: Any?) -> Date {
        if let ms = value as? Double {
            // Heuristic: values > ~10^12 are milliseconds.
            return ms > 1_000_000_000_000 ? Date(timeIntervalSince1970: ms / 1000)
                                          : Date(timeIntervalSince1970: ms)
        }
        if let s = value as? String {
            if let d = Double(s) {
                return d > 1_000_000_000_000 ? Date(timeIntervalSince1970: d / 1000)
                                             : Date(timeIntervalSince1970: d)
            }
            if let d = ISO8601DateFormatter().date(from: s) { return d }
        }
        return .distantPast // unknown → treat as expired, forces refresh/re-auth
    }
}

/// Production Keychain access via the Security framework. Non-sandboxed app (KTD8):
/// a first read of the Claude Code item triggers the macOS ACL prompt; a stable
/// Apple Development signature keeps "Always Allow" persistent across rebuilds.
public struct SystemKeychain: ClaudeCodeKeychainReading, OwnCredentialStoring {
    public static let claudeCodeService = "Claude Code-credentials"
    public static let ownService = "com.usagebar.claude-oauth"

    public init() {}

    public func readClaudeCodeCredential() throws -> ClaudeCredential {
        let data = try readData(service: Self.claudeCodeService)
        return try ClaudeCredentialBlob.parse(data)
    }

    public func readOwnClaude() throws -> ClaudeCredential? {
        do { return try ClaudeCredentialBlob.parse(readData(service: Self.ownService)) }
        catch CredentialError.notLoggedIn { return nil }
    }

    public func writeOwnClaude(_ credential: ClaudeCredential) throws {
        let payload: [String: Any] = [
            "accessToken": credential.accessToken,
            "refreshToken": credential.refreshToken,
            "expiresAt": credential.expiresAt.timeIntervalSince1970 * 1000,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        // Device-local, never iCloud-synced (security review): WhenUnlockedThisDeviceOnly
        // and no kSecAttrSynchronizable.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.ownService,
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.keychainStatus(status) }
    }

    private func readData(service: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw CredentialError.notLoggedIn }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CredentialError.keychainStatus(status)
        }
        return data
    }
}
