import Foundation

/// Paid turns use a separate entry point from the providers' usage readers.
public struct WarmUpCLISender: WarmUpSender {
    private enum LaunchResult: Sendable {
        case started(StdioChildProcess)
        case declined(WarmUpOutcome)
    }

    private let claudeLocator: any CLIExecutableLocating
    private let antigravity: AntigravityCLIUsageSource?
    private let userHome: URL
    private let accountsBase: URL
    private let loginPathOverride: String?
    private let timeout: TimeInterval

    public init(claudeLocator: any CLIExecutableLocating, antigravity: AntigravityCLIUsageSource? = nil) {
        self.init(
            claudeLocator: claudeLocator, userHome: FileManager.default.homeDirectoryForCurrentUser,
            accountsBase: AccountStorage.baseDirectoryURL, antigravity: antigravity
        )
    }

    init(
        claudeLocator: any CLIExecutableLocating, userHome: URL, accountsBase: URL,
        loginPathOverride: String? = nil, timeout: TimeInterval = 60, antigravity: AntigravityCLIUsageSource? = nil
    ) {
        self.claudeLocator = claudeLocator
        self.userHome = userHome
        self.accountsBase = accountsBase
        self.loginPathOverride = loginPathOverride
        self.timeout = timeout
        self.antigravity = antigravity
    }

    public func send(
        _ request: WarmUpRequest, mayLaunch: @MainActor @Sendable () -> Bool
    ) async -> WarmUpOutcome {
        let account = request.account
        let configuration = ProviderAccountConfiguration.make(for: account, userHome: userHome, accountsBase: accountsBase)
        guard let command = WarmUpCLICommand(account: account, configuration: configuration) else { return .skipped }
        if let borrowed = account.borrowedHome,
           BorrowedHomePaths.existingDirectory(borrowed.path.url) != borrowed.path { return .skipped }
        let agy: AntigravityCLIUsageSource.WarmUpLaunch?
        do {
            agy = account.providerID == .antigravity ? try await antigravity?.warmUpLaunch() : nil
        } catch {
            return .failed(.workspaceUnavailable)
        }
        if account.providerID == .antigravity, agy == nil { return .skipped }
        guard let location = await location(for: account, agy: agy) else { return .failed(.cliNotFound) }
        guard agy?.signedOut != true else { return .failed(.signedOut) }
        let directory = agy.map { URL(fileURLWithPath: $0.directory) } ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("Pacemark-WarmUp-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: agy != nil, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return .failed(.workspaceUnavailable)
        }
        defer { if agy == nil { try? FileManager.default.removeItem(at: directory) } }
        switch await launch(
            command, account: account, executable: location.executable, loginPath: location.path, agy: agy,
            directory: directory, mayLaunch: mayLaunch
        ) {
        case .declined(let outcome):
            return outcome
        case .started(let child):
            let deadline = Date().addingTimeInterval(timeout)
            let outcome: WarmUpOutcome = await CLIProcessThread.run {
                defer { child.terminate() }
                var scanner = AntigravitySignInPromptScanner()
                var showedAntigravitySignInPrompt = false
                var tail = Data()
                var failure: WarmUpFailure?
                child.drainError(until: deadline) { chunk in
                    if agy != nil {
                        showedAntigravitySignInPrompt = scanner.scan(chunk)
                        return !showedAntigravitySignInPrompt
                    }
                    tail.append(chunk)
                    let text = String(decoding: tail, as: UTF8.self).lowercased()
                    if text.contains("not logged in") || text.contains("please run /login") { failure = .signedOut }
                    if text.contains("unknown option") || text.contains("unexpected argument") { failure = .rejectedArguments }
                    tail = Data(tail.suffix(32))
                    return true
                }
                if showedAntigravitySignInPrompt {
                    return child.exitCode(within: 0) == 0 ? .sent : .failed(.signedOut)
                }
                if let code = child.exitCode(within: deadline.timeIntervalSinceNow) {
                    return code == 0 ? .sent : .failed(failure ?? .exitedNonZero(code))
                }
                return .failed(Date() < deadline ? .clientFailed : .timedOut)
            }
            if outcome == .failed(.signedOut), let agy { await antigravity?.markWarmUpSignedOut(agy.home) }
            return outcome
        }
    }

    public func diagnostic(for provider: ProviderID) async -> [String]? {
        let account = ProviderAccount.builtIn(for: provider)
        let configuration = ProviderAccountConfiguration.make(for: account, userHome: userHome, accountsBase: accountsBase)
        let agy = provider == .antigravity ? try? await antigravity?.diagnosticLaunch() : nil
        guard let command = WarmUpCLICommand(account: account, configuration: configuration),
              let location = await location(for: account, agy: agy) else { return nil }
        let keys = command.environment(userHome: userHome.path, loginPath: location.path, workingDirectory: agy?.directory ?? "<temporary>")
            .merging(agy?.environmentOverrides ?? [:]) { _, selected in selected }.keys.sorted()
        return ["Executable: " + location.executable, "Arguments: " + String(describing: command.arguments), "Environment keys: " + keys.joined(separator: ", ")]
    }

    private func location(for account: ProviderAccount, agy: AntigravityCLIUsageSource.WarmUpLaunch?) async -> (executable: String, path: String)? {
        if account.providerID == .antigravity { return agy.map { ($0.executable, $0.path) } }
        let executable: String?
        if account.providerID == .claude {
            executable = await claudeLocator.locate().path
        } else {
            executable = await CLIProcessThread.run {
                if let home = account.borrowedHome {
                    if let preferred = home.preferredExecutable {
                        return preferred.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: preferred)
                            ? preferred : nil
                    }
                    return CodexAppServerProvider.defaultExecutable(home)
                }
                return CLIExecutableResolver.resolve(named: "codex", fallbackPaths: [
                    "/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex",
                    "/Applications/Codex.app/Contents/Resources/codex",
                ])
            }
        }
        guard let executable else { return nil }
        let loginPath: String
        if let loginPathOverride {
            loginPath = loginPathOverride
        } else {
            loginPath = await CLIProcessThread.run {
                CLIExecutableResolver.resolveLoginPath(fallback: ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            }
        }
        return (executable, loginPath)
    }

    /// The usage and attachment checks share a main-actor turn with spawn.
    @MainActor
    private func launch(
        _ command: WarmUpCLICommand, account: ProviderAccount, executable: String, loginPath: String, agy: AntigravityCLIUsageSource.WarmUpLaunch?,
        directory: URL, mayLaunch: @MainActor @Sendable () -> Bool
    ) -> LaunchResult {
        guard mayLaunch(), command.selectedHomeExists,
              account.borrowedHome.map({ BorrowedHomePaths.existingDirectory($0.path.url) == $0.path }) != false
        else { return .declined(.skipped) }
        guard let child = StdioChildProcess.spawn(
            path: executable, arguments: [executable] + command.arguments,
            environment: command.environment(userHome: userHome.path, loginPath: loginPath, workingDirectory: directory.path).merging(agy?.environmentOverrides ?? [:]) { _, selected in selected },
            workingDirectory: directory.path, stdin: .nullDevice, stdout: .discard, stderr: .watch
        ) else { return .declined(.failed(.launchFailed)) }
        return .started(child)
    }
}

struct WarmUpCLICommand: Sendable {
    private let providerID: ProviderID
    private let homeOverrides: [String: String]
    let arguments: [String]

    init?(account: ProviderAccount, configuration: ProviderAccountConfiguration) {
        providerID = account.providerID
        switch providerID {
        case .claude:
            let config = configuration.claudeConfigDirectory
            guard account.isBuiltIn || config != nil else { return nil }
            homeOverrides = config.map { ["CLAUDE_CONFIG_DIR": $0.path] } ?? [:]
            // The installed help omits the turn cap. Keep the cap from the CLI research
            // and let clients without it fail without sending.
            arguments = [
                "--print", "--model", "haiku", "--max-turns", "1", "--no-session-persistence",
                "--safe-mode", "--restricted", "--strict-mcp-config", "--tools", "",
                "--disable-slash-commands", "--no-chrome", "--permission-prompts", "none",
                "--prompt-suggestions", "false", "--system-prompt-snapshot", "off",
                "--settings", #"{"disableAllHooks":true,"disableClaudeAiConnectors":true,"disableRemoteControl":true,"remoteControlAtStartup":false}"#,
                "--system-prompt", "Reply only with OK.", "--", "Reply with OK.",
            ]
        case .antigravity:
            guard account.isBuiltIn else { return nil }
            homeOverrides = [:]
            arguments = AntigravityWarmUpCommand.gemini.arguments
        case .codex:
            let home = configuration.borrowedCodexHome?.path.rawPath ?? configuration.codexHomeDirectory?.path
            guard account.isBuiltIn || home != nil else { return nil }
            homeOverrides = home.map { ["CODEX_HOME": $0] } ?? [:]
            arguments = [
                "exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral",
                "--ignore-user-config", "--ignore-rules", "--model", "gpt-6-luna",
                "-c", #"approval_policy="never""#, "-c", #"model_reasoning_effort="low""#,
                "-c", #"web_search="disabled""#, "-c", #"forced_login_method="chatgpt""#,
                "Reply only with OK. Do not use tools.",
            ]
        default:
            return nil
        }
    }

    var selectedHomeExists: Bool {
        guard let selected = homeOverrides.values.first else { return true }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: selected, isDirectory: &directory) && directory.boolValue
    }

    func environment(userHome: String, loginPath: String, workingDirectory: String) -> [String: String] {
        let minimal = ["HOME": userHome, "LANG": "en_US.UTF-8", "PATH": loginPath, "PWD": workingDirectory]
        if providerID == .claude {
            return ClaudeUsageCLIProbe.environment(
                inherited: minimal.merging(["USER": NSUserName()]) { _, user in user }, overrides: homeOverrides.merging(
                    ["CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1"], uniquingKeysWith: { _, control in control }
                ), loginPath: loginPath, workingDirectory: workingDirectory
            )
        }
        if providerID == .antigravity { return minimal.merging(["BROWSER": "/usr/bin/false", "AGY_CLI_DISABLE_AUTO_UPDATE": "true"]) { _, control in control } }
        return minimal.merging(homeOverrides, uniquingKeysWith: { _, selected in selected })
    }
}


enum AntigravityWarmUpCommand {
    case gemini

    var arguments: [String] {
        ["-p", "Reply only with OK. Do not use tools.", "--model", "Gemini 3.8 Flash",
         "--output-format", "json", "--mode", "plan", "--sandbox", "--disable-slash-commands", "--effort", "low"]
    }
}
