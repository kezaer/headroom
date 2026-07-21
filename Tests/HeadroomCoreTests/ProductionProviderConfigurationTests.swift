import Foundation
import Testing
@testable import HeadroomCore

@Suite struct ProductionProviderConfigurationTests {
    private let home = URL(fileURLWithPath: "/Users/test")
    private let accounts = URL(fileURLWithPath: "/Users/test/Library/Application Support/Headroom/Accounts")
    private let workspace = URL(fileURLWithPath: "/Users/test/Library/Application Support/Headroom/ClaudeProbe")

    @Test func builtInAccountsUseOnlyProviderDefaultsAndPreserveIdentity() {
        let claude = ProviderAccountConfiguration.make(
            for: .builtIn(for: .claude), userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let codex = ProviderAccountConfiguration.make(
            for: .builtIn(for: .codex), userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )

        #expect(claude.accountKey == AccountKey(providerID: .claude, accountID: .primary))
        #expect(claude.claudeConfigDirectory == nil)
        #expect(claude.claudeWorkspaceDirectory == workspace)
        #expect(codex.accountKey == AccountKey(providerID: .codex, accountID: .primary))
        #expect(codex.codexHomeDirectory == nil)
        #expect(codex.codexAuthFile?.path == "/Users/test/.codex/auth.json")
    }

    @Test func additionalAccountsUseTheirExactIsolatedPathsAndIDs() {
        let claudeAccount = ProviderAccount(id: AccountID("claude-work"), providerID: .claude, label: "Work")
        let codexAccount = ProviderAccount(id: AccountID("codex-work"), providerID: .codex, label: "Work")
        let claude = ProviderAccountConfiguration.make(
            for: claudeAccount, userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )
        let codex = ProviderAccountConfiguration.make(
            for: codexAccount, userHome: home, accountsBase: accounts, builtInClaudeWorkspace: workspace
        )

        #expect(claude.accountKey == claudeAccount.key)
        #expect(claude.claudeConfigDirectory?.path.hasSuffix("/claude/claude-work/config") == true)
        #expect(claude.claudeWorkspaceDirectory?.path.hasSuffix("/claude/claude-work/workspace") == true)
        #expect(codex.accountKey == codexAccount.key)
        #expect(codex.codexHomeDirectory?.path.hasSuffix("/codex/codex-work") == true)
        #expect(codex.codexAuthFile?.path.hasSuffix("/codex/codex-work/auth.json") == true)
    }
}
