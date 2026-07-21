import Foundation

/// Inspectable production routing for one provider/account pair. The composition root
/// consumes this value to build concrete providers; tests can verify identity and exact
/// paths without spawning a CLI, touching Keychain, or making a network request.
public struct ProviderAccountConfiguration: Sendable, Equatable {
    public let accountKey: AccountKey
    public let claudeConfigDirectory: URL?
    public let claudeWorkspaceDirectory: URL?
    public let codexHomeDirectory: URL?
    public let codexAuthFile: URL?

    public static func make(
        for account: ProviderAccount,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        accountsBase: URL = AccountStorage.baseDirectoryURL,
        builtInClaudeWorkspace: URL = ClaudeUsageWorkspace.defaultDirectoryURL
    ) -> ProviderAccountConfiguration {
        switch account.providerID {
        case .claude:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: builtInClaudeWorkspace,
                    codexHomeDirectory: nil,
                    codexAuthFile: nil
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: root.appendingPathComponent("config", isDirectory: true),
                claudeWorkspaceDirectory: root.appendingPathComponent("workspace", isDirectory: true),
                codexHomeDirectory: nil,
                codexAuthFile: nil
            )
        case .codex:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: nil,
                    codexHomeDirectory: nil,
                    codexAuthFile: userHome.appendingPathComponent(".codex/auth.json")
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: root,
                codexAuthFile: root.appendingPathComponent("auth.json")
            )
        default:
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: nil,
                codexAuthFile: nil
            )
        }
    }
}
