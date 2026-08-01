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
    public let grokHomeDirectory: URL?
    public let grokAuthFile: URL?

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
                    codexAuthFile: nil,
                    grokHomeDirectory: nil,
                    grokAuthFile: nil
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: root.appendingPathComponent("config", isDirectory: true),
                claudeWorkspaceDirectory: root.appendingPathComponent("workspace", isDirectory: true),
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: nil,
                grokAuthFile: nil
            )
        case .codex:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: nil,
                    codexHomeDirectory: nil,
                    codexAuthFile: userHome.appendingPathComponent(".codex/auth.json"),
                    grokHomeDirectory: nil,
                    grokAuthFile: nil
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: root,
                codexAuthFile: root.appendingPathComponent("auth.json"),
                grokHomeDirectory: nil,
                grokAuthFile: nil
            )
        case .grok:
            if account.isBuiltIn {
                return .init(
                    accountKey: account.key,
                    claudeConfigDirectory: nil,
                    claudeWorkspaceDirectory: nil,
                    codexHomeDirectory: nil,
                    codexAuthFile: nil,
                    grokHomeDirectory: nil,
                    grokAuthFile: userHome.appendingPathComponent(".grok/auth.json")
                )
            }
            let root = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: accountsBase)
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: root,
                grokAuthFile: root.appendingPathComponent("auth.json")
            )
        default:
            return .init(
                accountKey: account.key,
                claudeConfigDirectory: nil,
                claudeWorkspaceDirectory: nil,
                codexHomeDirectory: nil,
                codexAuthFile: nil,
                grokHomeDirectory: nil,
                grokAuthFile: nil
            )
        }
    }
}
