import Foundation

/// The email a Claude account is signed in as. Injected so the provider can be tested
/// against fixture JSON instead of a real `.claude.json`.
public protocol ClaudeAccountEmailReading: Sendable {
    /// The account email, or nil when the file is absent, unreadable, or carries no
    /// `oauthAccount.emailAddress`. Never throws: identity is display context, and a
    /// missing email must never downgrade an otherwise good usage capture (KTD7).
    func readAccountEmail() -> String?
}

/// Decodes **only** `oauthAccount.emailAddress` out of `.claude.json`. The decoder
/// declares that single field, so the rest of that file (project history, session state,
/// tips, MCP config) can never be read into Headroom by accident.
public enum ClaudeAccountBlob {
    private struct Root: Decodable {
        struct OAuthAccount: Decodable {
            let emailAddress: String?
        }
        let oauthAccount: OAuthAccount?
    }

    public static func email(in data: Data) -> String? {
        guard let root = try? JSONDecoder().decode(Root.self, from: data),
              let email = root.oauthAccount?.emailAddress?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else { return nil }
        return email
    }
}

/// Production reader for the account file the official `claude` CLI writes.
///
/// `.claude.json` sits at the *root* of the CLI's config home — `~/.claude.json` for the
/// built-in account (home root, **not** inside `~/.claude/`), and
/// `<CLAUDE_CONFIG_DIR>/.claude.json` for an extra account, the same directory the probe
/// points the CLI at. Read-only, like every other Claude path here: the official client
/// owns the file, Headroom only looks at one field of it.
public struct ClaudeAccountEmailFileReader: ClaudeAccountEmailReading {
    private let path: URL
    private let readData: @Sendable (URL) throws -> Data

    public init(
        path: URL,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.path = path
        self.readData = readData
    }

    /// `configDirectory` is the account's `CLAUDE_CONFIG_DIR`; nil means the built-in
    /// account, which uses the CLI's own default location.
    public init(
        configDirectory: URL?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) {
        self.init(
            path: Self.accountFileURL(configDirectory: configDirectory, userHome: userHome),
            readData: readData
        )
    }

    public static func accountFileURL(
        configDirectory: URL?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        (configDirectory ?? userHome).appendingPathComponent(".claude.json")
    }

    /// The reader for one account id, resolved the same way the probe resolves
    /// `CLAUDE_CONFIG_DIR`: `.primary` is the user's own CLI login, anything else is that
    /// account's Headroom-owned config home. Lets `ClaudeProvider` default correctly for
    /// both without the composition root threading a path through.
    public static func forAccount(_ accountID: AccountID) -> ClaudeAccountEmailFileReader {
        ClaudeAccountEmailFileReader(
            configDirectory: accountID == .primary
                ? nil
                : AccountStorage.claudeConfigDirectoryURL(forClaudeAccountID: accountID)
        )
    }

    /// Test seam: the resolved file path, so routing can be asserted without a filesystem.
    var accountFilePath: String { path.path }

    public func readAccountEmail() -> String? {
        guard let data = try? readData(path) else { return nil }
        return ClaudeAccountBlob.email(in: data)
    }
}
