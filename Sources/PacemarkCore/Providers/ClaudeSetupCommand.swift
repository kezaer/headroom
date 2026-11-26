/// KTD1 (2026-09-19 sign-in plan): what the handoff asks the official CLI to do.
/// `interactive` is the bare launch Pacemark has always used; `signIn` drives the
/// CLI's own sign-in command so the user types nothing.
public enum ClaudeSetupScriptKind: String, Sendable, Equatable, CaseIterable {
    case interactive
    case signIn
}

public struct ClaudeSetupDescriptor: Sendable, Equatable {
    public let accountKey: AccountKey
    public let executablePath: String?
    public let loginPath: String
    public let workspaceDirectory: String
    public let configDirectory: String?
    public let purpose: SetupHandoffPurpose
    public let completionMarker: SetupCompletionMarker?
    public let scriptKind: ClaudeSetupScriptKind

    public init(
        accountKey: AccountKey,
        executablePath: String?,
        loginPath: String,
        workspaceDirectory: String,
        configDirectory: String?,
        purpose: SetupHandoffPurpose = .setup,
        completionMarker: SetupCompletionMarker? = nil,
        scriptKind: ClaudeSetupScriptKind = .interactive
    ) {
        self.accountKey = accountKey
        self.executablePath = executablePath
        self.loginPath = loginPath
        self.workspaceDirectory = workspaceDirectory
        self.configDirectory = configDirectory
        self.purpose = purpose
        self.completionMarker = completionMarker
        self.scriptKind = scriptKind
    }
}

/// Pure, shell-safe command generation shared by the guided Claude handoff and its
/// clipboard fallback. Runtime values are limited to resolved executable/PATH and
/// Pacemark-owned workspace/config paths.
public enum ClaudeSetupCommand {
    /// KTD5: no resolved executable means there is no valid manual command. Substituting
    /// bare `claude` handed the user the same bare-name lookup Pacemark had already failed
    /// (`env: claude: No such file or directory`).
    public static func manualCommand(for descriptor: ClaudeSetupDescriptor) -> String? {
        guard let executablePath = descriptor.executablePath else { return nil }
        let executable = shellQuoted(executablePath)
        let workspace = shellQuoted(descriptor.workspaceDirectory)
        let commands: String
        switch (descriptor.purpose, descriptor.scriptKind) {
        case (.reset, _):
            commands = "\(executable) auth logout && \(executable) auth login"
        case (_, .signIn):
            // AE6: every command runs against this account's config home. Review
            // (2026-09-19 sign-in review): the copied line runs the script's own
            // `loggedIn` guard rather than a bare `auth status`, which would print the
            // signed-in email and organization into the user's terminal and then run
            // `auth login` regardless. `grep` decides, never the status exit code.
            commands = "\(signedInGuard(executable: executable)) || \(executable) auth login"
        case (_, .interactive):
            commands = executable
        }
        // KTD3: the exported subshell form, shared with the script. A one-command env
        // prefix binds only to the first command, so the two-command sign-in form
        // would run `auth login` against the default login instead.
        return "umask 077 && mkdir -p \(workspace) && cd \(workspace) && (\(accountRouting(for: descriptor)) && \(commands))"
    }

    public static func script(for descriptor: ClaudeSetupDescriptor) -> String {
        let config = accountRouting(for: descriptor)
        let accountGuidance: String
        switch (descriptor.purpose, descriptor.scriptKind) {
        case (.reset, _):
            accountGuidance = "Claude will sign out this CLI account, then ask you to sign in again."
        case (_, .signIn):
            accountGuidance = descriptor.configDirectory == nil
                ? "Claude will ask you to sign in. Finish it in your browser, then come back here."
                : "Claude will ask you to sign in. Use the account you want to add, then finish in your browser."
        case (_, .interactive):
            accountGuidance = descriptor.configDirectory == nil
                ? "Sign in or approve the Pacemark workspace when Claude asks."
                : "Sign in with the Claude account you want to add, then approve the Pacemark workspace if asked."
        }
        let introduction = """
        #!/bin/zsh
        clear
        export PATH=\(shellQuoted(descriptor.loginPath))
        \(config)
        cd \(shellQuoted(descriptor.workspaceDirectory)) || exit 1
        echo "Pacemark is opening the official Claude CLI."
        echo "\(accountGuidance)"
        echo "The /usage status check does not spend model usage."
        echo "Pacemark never receives your password or sign-in details."
        echo
        """

        guard let executablePath = descriptor.executablePath else {
            return introduction + "\n" + """
            echo "Claude Code CLI was not found. Install or update Claude Code, then reopen Pacemark."
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation: String
        switch (descriptor.purpose, descriptor.scriptKind) {
        case (.reset, _):
            invocation = resetInvocation(executable: executable)
        case (_, .signIn):
            invocation = signInInvocation(executable: executable)
        case (_, .interactive):
            invocation = executable
        }
        let launch: String
        if let completionMarker = descriptor.completionMarker {
            launch = SetupCompletionCommand.wrap(invocation, marker: completionMarker, mode: .standard)
        } else if descriptor.purpose == .setup, descriptor.scriptKind == .interactive {
            launch = "exec \(invocation)"
        } else {
            // A multi-line invocation has nothing for `exec` to replace the shell with.
            launch = invocation
        }
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The Claude CLI moved or is no longer executable. Reopen Pacemark and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    /// KTD3: the one routing construction. The script sets it at top level, the manual
    /// command wraps it in a subshell, and both bind it to every command that follows.
    private static func accountRouting(for descriptor: ClaudeSetupDescriptor) -> String {
        descriptor.configDirectory.map {
            "export CLAUDE_CONFIG_DIR=\(shellQuoted($0))"
        } ?? "unset CLAUDE_CONFIG_DIR"
    }

    /// KTD1/KTD2: guard on the `loggedIn` field of `auth status --json` — the one field
    /// every Pacemark usage check has always depended on — and treat only a literal
    /// true as signed in. Anything else, including a missing `grep`, continues to the
    /// official `auth login`. The status command's own exit code is unused: it was
    /// verified on one CLI version only. Its output reaches neither the window nor
    /// Pacemark, because it prints the signed-in email and organization.
    private static func signInInvocation(executable: String) -> String {
        """
        typeset pacemark_signin_status=0
        typeset pacemark_already_signed_in=0
        if \(signedInGuard(executable: executable)); then
          pacemark_already_signed_in=1
        else
          \(executable) auth login
          pacemark_signin_status=$?
        fi
        if (( pacemark_already_signed_in )); then
          echo "\(alreadySignedInLine)"
        elif (( pacemark_signin_status == 0 )); then
          echo "\(finishedLine)"
        else
          echo "\(unfinishedLine)"
        fi
        \(statusReturn)
        """
    }

    /// KTD2/Review (2026-09-19 sign-in review): the one signed-in guard. The script
    /// branches on it and the copied manual command short-circuits on it, so neither
    /// surface can drift back into showing `auth status`'s output — it names the
    /// signed-in email and organization. Only a literal `true` counts as signed in;
    /// anything else, including a missing `grep`, continues to `auth login`.
    private static func signedInGuard(executable: String) -> String {
        "\(executable) auth status --json 2>/dev/null | grep -qE '\(loggedInPattern)'"
    }

    private static let loggedInPattern = #""loggedIn"[[:space:]]*:[[:space:]]*true([[:space:]]*[,}]|$)"#

    private static func resetInvocation(executable: String) -> String {
        """
        typeset pacemark_signin_status=0
        \(executable) auth logout && \(executable) auth login
        pacemark_signin_status=$?
        if (( pacemark_signin_status == 0 )); then
          echo "\(finishedLine)"
        else
          echo "\(unfinishedLine)"
        fi
        \(statusReturn)
        """
    }

    /// R3: one line saying whether sign-in finished. It promises no usage, because a
    /// Console or API login has none.
    private static let finishedLine = "Sign-in finished. Pacemark is checking your Claude account."
    private static let unfinishedLine = "Sign-in didn’t finish. Return to Pacemark to try again."
    /// R2: the account was already signed in when the script ran, so no sign-in started.
    private static let alreadySignedInLine = "This account is already signed in. Pacemark is checking your Claude account."

    /// KTD2: `SetupCompletionCommand.wrap` appends `exit $?`, so the invocation's last
    /// command decides the recorded status. Returning sign-in's saved status keeps a
    /// failed sign-in from being recorded as `.succeeded` by the result line's echo.
    private static let statusReturn = "( exit $pacemark_signin_status )"

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
