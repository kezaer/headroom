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
        let root = try CredentialError.jsonObject(data)
        guard
            let tokens = root["tokens"] as? [String: Any],
            let access = tokens["access_token"] as? String
        else { throw CredentialError.malformed }
        let lastRefresh = DateParsing.iso8601(root["last_refresh"] as? String)
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
    private let readData: @Sendable (URL) throws -> Data
    private let permissionsAreSafe: @Sendable (URL) -> Bool

    public init(
        path: URL? = nil,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        permissionsAreSafe: @escaping @Sendable (URL) -> Bool = {
            AccountStorage.credentialFilePermissionsAreSafe(at: $0)
        }
    ) {
        self.path = path
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
        self.readData = readData
        self.permissionsAreSafe = permissionsAreSafe
    }

    public func readCodexCredential() throws -> CodexCredential {
        do {
            let data = try readData(path)
            guard permissionsAreSafe(path) else { throw CredentialError.unsafePermissions }
            return try CodexAuthBlob.parse(data)
        } catch let error as CredentialError {
            throw error
        } catch let error as CocoaError {
            switch error.code {
            case .fileNoSuchFile, .fileReadNoSuchFile:
                throw CredentialError.notLoggedIn
            case .fileReadNoPermission:
                throw CredentialError.permissionDenied
            default:
                throw CredentialError.ioFailure
            }
        } catch {
            throw CredentialError.ioFailure
        }
    }
}
