import Foundation
import Testing
@testable import HeadroomCore

@Suite struct ClaudeSetupCommandTests {
    private let account = AccountKey(providerID: .claude, accountID: AccountID("extra"))

    @Test func builtInAndAdditionalDescriptorsUseExactRouting() {
        let builtIn = ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/Users/Test User/.local/bin/claude",
            loginPath: "/Users/Test User/.local/bin:/usr/bin:/bin",
            workspaceDirectory: "/Users/Test User/Library/Application Support/Headroom/ClaudeProbe",
            configDirectory: nil
        )
        let extra = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.nvm/bin/claude",
            loginPath: "/Users/Test User/.nvm/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space"
        )

        #expect(ClaudeSetupCommand.script(for: builtIn).contains("unset CLAUDE_CONFIG_DIR"))
        #expect(ClaudeSetupCommand.script(for: builtIn).contains("exec '/Users/Test User/.local/bin/claude'"))
        #expect(ClaudeSetupCommand.script(for: extra).contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(ClaudeSetupCommand.script(for: extra).contains("cd '/tmp/work space'"))
        #expect(ClaudeSetupCommand.script(for: extra).contains("exec '/Users/Test User/.nvm/bin/claude'"))
    }

    @Test func pathsWithQuotesStayOneShellTokenAndScriptsParse() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/tmp/o'brien/bin/claude",
            loginPath: "/tmp/o'brien/bin:/usr/bin",
            workspaceDirectory: "/tmp/o'brien/work space",
            configDirectory: "/tmp/o'brien/config space"
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        #expect(script.contains("'/tmp/o'\\''brien/bin/claude'"))
        #expect(script.contains("'/tmp/o'\\''brien/work space'"))

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n"]
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func missingExecutableFailsClearlyWithoutGuessing() {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: nil,
            loginPath: "/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config"
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        #expect(script.contains("Claude Code CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("exec claude"))
    }

    // KTD5: an unresolved executable has no valid manual launch command — substituting
    // bare `claude` would hand the user the lookup Headroom already failed.
    @Test func manualCommandIsUnavailableWithoutAResolvedExecutable() {
        let command = ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: nil,
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space"
        ))

        #expect(command == nil)
    }

    @Test func manualCommandQuotesResolvedPathsAndPreservesAccountRouting() throws {
        let extra = try #require(ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/o'brien/bin/claude",
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space"
        )))
        let builtIn = try #require(ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/Users/Test User/.npm-global/bin/claude",
            loginPath: "",
            workspaceDirectory: "/tmp/work space",
            configDirectory: nil
        )))

        #expect(extra == "umask 077 && mkdir -p '/tmp/work space' && cd '/tmp/work space' && CLAUDE_CONFIG_DIR='/tmp/config space' '/Users/Test User/.npm-global/o'\\''brien/bin/claude'")
        #expect(builtIn == "umask 077 && mkdir -p '/tmp/work space' && cd '/tmp/work space' && env -u CLAUDE_CONFIG_DIR '/Users/Test User/.npm-global/bin/claude'")
        for command in [extra, builtIn] {
            #expect(!command.hasSuffix(" claude"))
            #expect(!command.contains(account.accountID.raw))
        }
    }

    @Test func resetUsesOfficialLogoutThenLoginWithTheSameSafeAccountRouting() throws {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/o'brien/bin/claude",
            loginPath: "/Users/Test User/.npm-global/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space",
            purpose: .reset
        )

        let script = ClaudeSetupCommand.script(for: descriptor)
        let manual = try #require(ClaudeSetupCommand.manualCommand(for: descriptor))
        let executable = "'/Users/Test User/.npm-global/o'\\''brien/bin/claude'"

        #expect(script.contains("\(executable) auth logout && \(executable) auth login"))
        #expect(manual.contains("\(executable) auth logout && \(executable) auth login"))
        #expect(script.contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(manual.contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(!script.contains("api.anthropic.com"))
        #expect(!manual.contains("api.anthropic.com"))

        let builtIn = ClaudeSetupDescriptor(
            accountKey: AccountKey(providerID: .claude, accountID: .primary),
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/built-in work",
            configDirectory: nil,
            purpose: .reset
        )
        let builtInScript = ClaudeSetupCommand.script(for: builtIn)
        let builtInManual = try #require(ClaudeSetupCommand.manualCommand(for: builtIn))
        #expect(builtInScript.contains("unset CLAUDE_CONFIG_DIR"))
        #expect(builtInManual.contains("(unset CLAUDE_CONFIG_DIR && '/opt/homebrew/bin/claude' auth logout && '/opt/homebrew/bin/claude' auth login)"))
    }

    // AE6: an npm-derived launcher reaches the staged handoff with the account's
    // isolated config home, workspace, completion marker, and one-token quoting.
    @Test func npmDerivedLauncherKeepsExtraAccountIsolationInTheStagedScript() throws {
        let marker = SetupCompletionMarker(
            pendingPath: "/tmp/setup pending",
            completedPath: "/tmp/setup complete"
        )
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/Users/Test User/.npm-global/bin/claude",
            loginPath: "/Users/Test User/.npm-global/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work space",
            configDirectory: "/tmp/config space",
            completionMarker: marker
        )
        let script = ClaudeSetupCommand.script(for: descriptor)

        #expect(script.contains("export CLAUDE_CONFIG_DIR='/tmp/config space'"))
        #expect(script.contains("cd '/tmp/work space'"))
        #expect(script.contains("'/Users/Test User/.npm-global/bin/claude'"))
        #expect(script.contains("'/tmp/setup complete'"))
        #expect(!script.contains("exec claude"))

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n"]
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func generatedScriptContainsNoProviderPayloadOrIdentity() {
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config"
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        for forbidden in ["access_token", "Authorization", "backend-api", account.accountID.raw] {
            #expect(!script.localizedCaseInsensitiveContains(forbidden))
        }
    }

    @Test func completionMarkerWrapperIsRedactedAndZshValid() throws {
        let marker = SetupCompletionMarker(pendingPath: "/tmp/setup pending", completedPath: "/tmp/setup complete")
        let descriptor = ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/opt/homebrew/bin/claude",
            loginPath: "/opt/homebrew/bin:/usr/bin:/bin",
            workspaceDirectory: "/tmp/work",
            configDirectory: "/tmp/config",
            completionMarker: marker
        )
        let script = ClaudeSetupCommand.script(for: descriptor)
        #expect(script.contains("HEADROOM_SETUP_OWNER=\"${setup_purpose}:standard:${handoff_generation}:$$\""))
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(!script.contains(account.accountID.raw))

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n"]
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func completionWrapperRecordsExitAndDeletesPendingScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-wrapper-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("setup.command")
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let script = ClaudeSetupCommand.script(for: ClaudeSetupDescriptor(
            accountKey: account,
            executablePath: "/usr/bin/true",
            loginPath: "/usr/bin:/bin",
            workspaceDirectory: directory.path,
            configDirectory: directory.path,
            purpose: .reset,
            completionMarker: marker
        ))
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .standard,
            purpose: .reset
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.environment = ["TERM": "xterm-256color"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))
        #expect(!FileManager.default.fileExists(atPath: scriptURL.path))
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .succeeded)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .reset)
    }
}

@Suite struct ClaudeUsageWorkspaceTests {
    @Test func provisioningCreatesAnAbsentWorkspaceWithOwnerOnlyPermissions() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-claude-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)

        #expect(!FileManager.default.fileExists(atPath: workspace.path))

        let provisioned = try ClaudeUsageWorkspace.ensureDirectory(at: workspace)
        var isDirectory: ObjCBool = false
        #expect(provisioned == workspace)
        #expect(FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        let attributes = try FileManager.default.attributesOfItem(atPath: workspace.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o700)
    }

    @Test func provisioningDoesNotRechmodAnExistingUsableWorkspace() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-existing-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("ClaudeProbe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: workspace.path)

        #expect(try ClaudeUsageWorkspace.ensureDirectory(at: workspace) == workspace)
        let attributes = try FileManager.default.attributesOfItem(atPath: workspace.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.intValue & 0o777 == 0o755)
    }
}
