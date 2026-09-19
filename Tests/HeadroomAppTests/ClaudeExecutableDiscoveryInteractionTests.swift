import Foundation
import Testing
import HeadroomCore
@testable import Headroom

/// Claude CLI discovery and manual-command recovery at the app boundary: what the
/// capability recovery row offers for each discovery state, and which executable the
/// staged handoff, clipboard fallback, and legacy script actually launch.
@Suite struct ClaudeExecutableDiscoveryInteractionTests {
    /// AE5: confirmed absence routes to installation guidance plus a forced discovery
    /// check, with an accessibility label for each offered action.
    @MainActor @Test func confirmedAbsenceOffersInstallAndCheckAgainWithLabelledActions() {
        let presentation = capabilityRecoveryPresentation(
            state: .confirmedAbsent,
            hasActiveSetupSession: false
        )
        let recovery = presentation?.recovery
        let actions = AccountsSettingsInteractions.RecoveryRowActions(
            presentation: ProviderSetupOutcome.claudeCLIMissing.recoveryPresentation,
            accountLabel: "Personal"
        )

        #expect(recovery?.primaryAction == .installClaudeCLI)
        #expect(recovery?.secondaryAction == .checkNow)
        #expect(SetupSessions.recoveryRoute(for: recovery!.primaryAction)
            == .documentation(URL(string: "https://code.claude.com/docs/en/installation")!))
        #expect(SetupSessions.recoveryRoute(for: recovery!.secondaryAction!) == .checkNow)
        #expect(actions.primaryAccessibilityLabel == "Install Claude Code for Personal")
        #expect(actions.secondaryAccessibilityLabel == "Check Now for Personal")
        #expect(actions.usesSecondLine)
    }

    /// AE7: incomplete discovery keeps Check Now + Open Guided Setup and never shows
    /// confirmed-absence installation copy.
    @MainActor @Test func inconclusiveDiscoveryKeepsRetryActionsWithoutInstallCopy() {
        for issue in [CLIExecutableDiscoveryIssue.shellTimeout, .npmPrefixUnresolved] {
            let recovery = capabilityRecoveryPresentation(
                state: .inconclusive(issue),
                hasActiveSetupSession: false
            )?.recovery
            #expect(recovery?.primaryAction == .checkNow)
            #expect(recovery?.secondaryAction == .openClaudeSetup)
            #expect(recovery?.primaryLabel == "Check Now")
            #expect(recovery?.secondaryLabel == "Open Guided Setup")
            #expect(recovery?.status.localizedCaseInsensitiveContains("install") == false)
        }
    }

    /// AE6: an npm-derived absolute launcher reaches the staged handoff and its clipboard
    /// fallback with the extra account's isolated `CLAUDE_CONFIG_DIR` and marker.
    @MainActor @Test func npmDerivedLauncherStagesExtraAccountHandoffAndAbsolutePathFallback() async throws {
        let launcher = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-npm-prefix-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("claude")
        let account = ProviderAccount(
            id: AccountID("npm-extra-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        defer { try? AccountStorage.removeDirectories(for: account) }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-npm-handoff-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(
                location: .available(path: launcher.path, source: .npmGlobalPrefix)
            )
        )

        guard case .success(let handoff) = result else {
            Issue.record("Expected preparation to succeed for an npm-derived launcher")
            return
        }
        let staged = try #require(SetupSessions.stagedHandoff(for: handoff.accountKey))
        let script = try String(contentsOf: staged.scriptURL, encoding: .utf8)
        let configDirectory = AccountStorage.claudeConfigDirectoryURL(for: account).path

        #expect(script.contains("'\(launcher.path)'"))
        #expect(script.contains("export CLAUDE_CONFIG_DIR='\(configDirectory)'"))
        #expect(script.contains("'\(staged.completionMarker.completedPath)'"))
        #expect(!script.contains("exec claude"))
        // KTD3 (2026-09-19 sign-in plan): the manual command routes through the exported
        // subshell form, so every command in it binds to this account's config home.
        #expect(staged.manualCommand.contains("(export CLAUDE_CONFIG_DIR='\(configDirectory)' && "))
        #expect(staged.manualCommand.hasSuffix("'\(launcher.path)')"))
        #expect(!staged.manualCommand.hasSuffix(" claude"))

        await SetupSessions.discardPreparedHandoff(handoff)
    }

    /// R6/KTD5: the legacy render-harness handoff launches the same validated absolute
    /// executable, so an npm-prefix or legacy install is not lost to a bare-name lookup
    /// against a hardcoded PATH.
    @MainActor @Test func legacyStagedScriptLaunchesTheResolvedAbsoluteExecutable() throws {
        let script = ClaudeSetupSession.script(
            for: .builtIn(for: .claude),
            workspacePath: "/tmp/work space",
            executablePath: "/Users/Test User/.npm-global/bin/claude"
        )

        #expect(script.contains("exec '/Users/Test User/.npm-global/bin/claude'"))
        #expect(!script.contains("command -v claude"))
        #expect(!script.contains("exec claude"))
        #expect(script.contains("cd '/tmp/work space'"))
        #expect(script.contains("$HOME/.claude/local"))
        try expectZshParses(script)
    }

    /// R7: with no resolved executable the legacy script shows install guidance instead of
    /// staging another bare lookup, and keeps extra-account config isolation.
    @MainActor @Test func legacyStagedScriptWithoutResolutionStagesNoBareLookup() throws {
        let account = ProviderAccount(
            id: AccountID("legacy-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        let script = ClaudeSetupSession.script(
            for: account,
            workspacePath: "/tmp/work space",
            executablePath: nil
        )
        let configDirectory = AccountStorage.claudeConfigDirectoryURL(for: account).path

        #expect(script.contains("Claude Code CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("exec claude"))
        #expect(!script.contains("command -v claude"))
        #expect(script.contains("export CLAUDE_CONFIG_DIR='\(configDirectory)'"))
        #expect(script.contains("$HOME/.claude/local"))
        try expectZshParses(script)
    }

    /// AE3/KTD5: the approval handoff reaches the trust purpose at the app boundary, while
    /// Sign In keeps the ordinary setup route.
    @MainActor @Test func claudeWorkspaceApprovalRoutesToTheTrustHandoff() {
        #expect(SetupSessions.recoveryRoute(for: .openClaudeWorkspace) == .workspaceTrust)
        #expect(SetupSessions.recoveryRoute(for: .openClaudeSetup) == .setup(.standard))
        #expect(ProviderSetupOutcome.claudeTrustRequired.recoveryPresentation.primaryAction
            == .openClaudeWorkspace)
    }

    /// KTD1: a built-in account on a current CLI signs in without the user typing anything,
    /// and the version read carries no config override, so it reads the CLI's own default.
    @MainActor @Test func currentBuiltInCLIStagesTheSignInScript() async throws {
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let versions = ClaudeVersionReaderSpy("2.1.217 (Claude Code)")

        let staging = await stageClaudeHandoff(
            for: .builtIn(for: .claude),
            workspace: workspace,
            versions: versions
        )

        #expect(staging.handoff?.claudeScriptKind == .signIn)
        #expect(staging.staged?.claudeScriptKind == .signIn)
        let script = try #require(staging.script)
        #expect(script.contains("auth login"))
        #expect(script.contains("auth status --json"))
        #expect(staging.staged?.manualCommand.contains("auth login") == true)
        #expect(await versions.environments == [[:]])
        await staging.discard()
    }

    /// KTD1: a reset keeps its own script on a current CLI — the sign-in guard would skip
    /// the sign-out the reset exists to perform.
    @MainActor @Test func resetKeepsItsResetScriptOnACurrentCLI() async throws {
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let staging = await stageClaudeHandoff(
            for: .builtIn(for: .claude),
            purpose: .reset,
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.300 (Claude Code)")
        )

        let script = try #require(staging.script)
        #expect(script.contains("auth logout"))
        #expect(script.contains("auth login"))
        #expect(!script.contains("auth status --json"))
        await staging.discard()
    }

    /// AE7/KTD1: a never-onboarded extra account below the print-mode floor runs on the PTY
    /// path, where the bare launch shows the login selector and then the approval prompt in
    /// one Terminal trip. At the floor the same account stages the sign-in script. Both read
    /// the version through that account's own config home.
    @MainActor @Test func extraAccountBelowThePrintFloorStagesTheInteractiveLaunch() async throws {
        let account = ProviderAccount(
            id: AccountID("staging-extra-\(UUID().uuidString)"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )
        defer { try? AccountStorage.removeDirectories(for: account) }
        let configDirectory = AccountStorage.claudeConfigDirectoryURL(for: account).path

        for (version, expected) in [("2.1.100 (Claude Code)", ClaudeSetupScriptKind.interactive),
                                    ("2.1.217 (Claude Code)", .signIn)] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let versions = ClaudeVersionReaderSpy(version)

            let staging = await stageClaudeHandoff(
                for: account,
                workspace: workspace,
                versions: versions
            )

            #expect(staging.handoff?.claudeScriptKind == expected)
            let script = try #require(staging.script)
            #expect(script.contains("auth login") == (expected == .signIn))
            #expect(await versions.environments == [["CLAUDE_CONFIG_DIR": configDirectory]])
            await staging.discard()
        }
    }

    /// AE7/KTD1: the print-mode floor gates extra accounts only. A built-in account below it
    /// has already been onboarded in the CLI's own config, so it stages the sign-in script.
    @MainActor @Test func builtInAccountBelowThePrintFloorStillStagesTheSignInScript() async throws {
        let workspace = temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let staging = await stageClaudeHandoff(
            for: .builtIn(for: .claude),
            workspace: workspace,
            versions: ClaudeVersionReaderSpy("2.1.100 (Claude Code)")
        )

        #expect(staging.handoff?.claudeScriptKind == .signIn)
        await staging.discard()
    }

    /// R6/KTD1: a readable version below 2.1.41 refuses the handoff for sign-in and reset
    /// alike — those CLIs can sign in and never be confirmed, because every usage check
    /// reads `auth status`. Nothing is staged, so nothing can be opened.
    @MainActor @Test func versionBelowTheSignInFloorRefusesWithoutStagingAScript() async {
        for purpose in [SetupHandoffPurpose.setup, .reset] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let account = ProviderAccount.builtIn(for: .claude)

            let staging = await stageClaudeHandoff(
                for: account,
                purpose: purpose,
                workspace: workspace,
                versions: ClaudeVersionReaderSpy("2.1.40 (Claude Code)")
            )

            #expect(staging.result == .failure(.updateRequired))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
            #expect(stagedScriptFiles(besideWorkspace: workspace).isEmpty)
        }
    }

    /// R6: an unreadable version keeps today's interactive launch, so a change to the CLI's
    /// version format cannot lock every user out of sign-in.
    @MainActor @Test func unreadableVersionKeepsTheInteractiveLaunch() async throws {
        for version in [nil, "claude-code (unknown build)"] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }

            let staging = await stageClaudeHandoff(
                for: .builtIn(for: .claude),
                workspace: workspace,
                versions: ClaudeVersionReaderSpy(version)
            )

            #expect(staging.handoff?.claudeScriptKind == .interactive)
            #expect(try #require(staging.script).contains("auth login") == false)
            await staging.discard()
        }
    }

    /// AE3/KTD1: the approval handoff stages the interactive launch at any version — the
    /// approval prompt only appears there, and the sign-in script's guard would exit on an
    /// account that is already signed in.
    @MainActor @Test func workspaceApprovalStagesTheInteractiveLaunchAtEveryVersion() async throws {
        for version in ["2.1.40 (Claude Code)", "2.1.100 (Claude Code)", "2.1.300 (Claude Code)"] {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }

            let staging = await stageClaudeHandoff(
                for: .builtIn(for: .claude),
                purpose: .trust,
                workspace: workspace,
                versions: ClaudeVersionReaderSpy(version)
            )

            #expect(staging.handoff?.claudeScriptKind == .interactive)
            let script = try #require(staging.script)
            #expect(!script.contains("auth login"))
            #expect(!script.contains("auth logout"))
            await staging.discard()
        }
    }

    /// KTD5 of the 2026-08-12 plan: an unresolved executable still fails with the typed
    /// capability state and stages nothing, and the version gate never runs — there is no
    /// validated binary to ask.
    @MainActor @Test func unresolvedDiscoveryKeepsItsCapabilityFailuresAndSkipsTheVersionRead() async {
        let account = ProviderAccount.builtIn(for: .claude)
        let expectations: [(CLIExecutableLocation, SetupSessionFailure)] = [
            (.confirmedAbsent, .providerCapability(.confirmedAbsent)),
            (.inconclusive(.npmPrefixUnresolved), .providerCapability(.inconclusive(.npmPrefixUnresolved))),
        ]

        for (location, failure) in expectations {
            let workspace = temporaryWorkspace()
            defer { try? FileManager.default.removeItem(at: workspace) }
            let versions = ClaudeVersionReaderSpy("2.1.300 (Claude Code)")

            let result = await SetupSessions.prepareHandoff(
                for: account,
                mode: .standard,
                builtInClaudeWorkspace: workspace,
                claudeExecutableLocator: FixedExecutableLocator(location: location),
                claudeVersionReader: { path, overrides in
                    await versions.read(executablePath: path, environmentOverrides: overrides)
                }
            )

            #expect(result == .failure(failure))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
            #expect(await versions.executablePaths.isEmpty)
        }
    }

    private struct ClaudeStagingOutcome {
        let result: SetupPreparationResult
        let staged: SetupSessions.PreparedScript?
        let script: String?

        var handoff: PreparedSetupHandoff? {
            guard case .success(let handoff) = result else { return nil }
            return handoff
        }

        @MainActor func discard() async {
            guard let handoff else { return }
            await SetupSessions.discardPreparedHandoff(handoff)
        }
    }

    @MainActor private func stageClaudeHandoff(
        for account: ProviderAccount,
        purpose: SetupHandoffPurpose = .setup,
        workspace: URL,
        executablePath: String = "/opt/homebrew/bin/claude",
        versions: ClaudeVersionReaderSpy
    ) async -> ClaudeStagingOutcome {
        let result = await SetupSessions.prepareHandoff(
            for: account,
            mode: .standard,
            purpose: purpose,
            builtInClaudeWorkspace: workspace,
            claudeExecutableLocator: FixedExecutableLocator(
                location: .available(path: executablePath, source: .memoryHint)
            ),
            claudeVersionReader: { path, overrides in
                await versions.read(executablePath: path, environmentOverrides: overrides)
            }
        )
        let staged = SetupSessions.stagedHandoff(for: account.key)
        let script = staged.flatMap { try? String(contentsOf: $0.scriptURL, encoding: .utf8) }
        return ClaudeStagingOutcome(result: result, staged: staged, script: script)
    }

    private func temporaryWorkspace() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-staging-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
    }

    /// Staging writes its `.command` next to the workspace, so an empty listing is the
    /// evidence that a refusal wrote no script at all.
    private func stagedScriptFiles(besideWorkspace workspace: URL) -> [URL] {
        let setupDirectory = workspace
            .deletingLastPathComponent()
            .appendingPathComponent("Setup", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: setupDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "command" }
    }

    private func expectZshParses(_ script: String) throws {
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

    /// KTD5: unresolved discovery fails preparation, so no staged handoff — and therefore
    /// no Terminal-rejected clipboard fallback — can exist without a validated executable.
    @MainActor @Test func unresolvedDiscoveryStagesNoHandoffForTheClipboardFallback() async {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-unresolved-handoff-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let account = ProviderAccount.builtIn(for: .claude)

        for location in [CLIExecutableLocation.confirmedAbsent, .inconclusive(.npmPrefixUnresolved)] {
            let result = await SetupSessions.prepareHandoff(
                for: account,
                mode: .standard,
                builtInClaudeWorkspace: workspace,
                claudeExecutableLocator: FixedExecutableLocator(location: location)
            )
            #expect(result != .success(PreparedSetupHandoff(accountKey: account.key, mode: .standard)))
            #expect(SetupSessions.stagedHandoff(for: account.key) == nil)
        }
    }

    /// R6: a resolved locator yields a manual command naming the shell-quoted absolute
    /// executable, never a bare `claude` that would repeat the lookup that just failed.
    @MainActor @Test func resolvedCommandNamesTheLocatedAbsoluteExecutable() async throws {
        let path = "/Users/Test User/.npm-global/bin/claude"
        let command = try #require(await ClaudeSetupSession.resolvedCommand(
            locator: FixedExecutableLocator(location: .available(path: path, source: .npmGlobalPrefix))
        ))

        #expect(command.contains("'\(path)'"))
        // KTD3 (2026-09-19 sign-in plan): the executable is the last command inside the
        // routing subshell that every manual command now shares.
        #expect(command.hasSuffix("'\(path)')"))
        #expect(!command.hasSuffix(" claude"))
    }

    /// R6: the refusal names the product the user updates and leaks nothing about the
    /// version it read.
    @MainActor @Test func updateRequiredFailureCopyNamesTheProduct() {
        #expect(SetupSessions.failureMessage(for: .updateRequired, account: .builtIn(for: .claude))
            == "Update Claude Code, then try again.")
    }

    /// KTD5: without a resolved path there is no command at all — the nil branch must not
    /// fall back to a bare-name invocation.
    @MainActor @Test func resolvedCommandIsNilWhenDiscoveryYieldsNoPath() async {
        for location in [CLIExecutableLocation.confirmedAbsent, .inconclusive(.shellTimeout)] {
            let command = await ClaudeSetupSession.resolvedCommand(
                locator: FixedExecutableLocator(location: location)
            )
            #expect(command == nil)
        }
    }
}

/// KTD1/KTD4: a fixed `--version` capture in place of the real CLI, recording what staging
/// asked so account isolation is asserted without spawning anything.
private actor ClaudeVersionReaderSpy {
    private let output: String?
    private(set) var executablePaths: [String] = []
    private(set) var environments: [[String: String]] = []

    init(_ output: String?) {
        self.output = output
    }

    func read(executablePath: String, environmentOverrides: [String: String]) -> String? {
        executablePaths.append(executablePath)
        environments.append(environmentOverrides)
        return output
    }
}
