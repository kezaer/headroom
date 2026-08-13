public struct ClaudeSetupDescriptor: Sendable, Equatable {
    public let accountKey: AccountKey
    public let executablePath: String?
    public let loginPath: String
    public let workspaceDirectory: String
    public let configDirectory: String?
    public let completionMarker: SetupCompletionMarker?

    public init(
        accountKey: AccountKey,
        executablePath: String?,
        loginPath: String,
        workspaceDirectory: String,
        configDirectory: String?,
        completionMarker: SetupCompletionMarker? = nil
    ) {
        self.accountKey = accountKey
        self.executablePath = executablePath
        self.loginPath = loginPath
        self.workspaceDirectory = workspaceDirectory
        self.configDirectory = configDirectory
        self.completionMarker = completionMarker
    }
}

/// Pure, shell-safe command generation shared by the guided Claude handoff and its
/// clipboard fallback. Runtime values are limited to resolved executable/PATH and
/// Headroom-owned workspace/config paths.
public enum ClaudeSetupCommand {
    /// KTD5: no resolved executable means there is no valid manual command. Substituting
    /// bare `claude` handed the user the same bare-name lookup Headroom had already failed
    /// (`env: claude: No such file or directory`).
    public static func manualCommand(for descriptor: ClaudeSetupDescriptor) -> String? {
        guard let executablePath = descriptor.executablePath else { return nil }
        let home = descriptor.configDirectory.map {
            "CLAUDE_CONFIG_DIR=\(shellQuoted($0)) "
        } ?? "env -u CLAUDE_CONFIG_DIR "
        let workspace = shellQuoted(descriptor.workspaceDirectory)
        return "umask 077 && mkdir -p \(workspace) && cd \(workspace) && \(home)\(shellQuoted(executablePath))"
    }

    public static func script(for descriptor: ClaudeSetupDescriptor) -> String {
        let config = descriptor.configDirectory.map {
            "export CLAUDE_CONFIG_DIR=\(shellQuoted($0))"
        } ?? "unset CLAUDE_CONFIG_DIR"
        let accountGuidance = descriptor.configDirectory == nil
            ? "Sign in or approve the Headroom workspace when Claude asks."
            : "Sign in with the Claude account you want to add, then approve the Headroom workspace if asked."
        let introduction = """
        #!/bin/zsh
        clear
        export PATH=\(shellQuoted(descriptor.loginPath))
        \(config)
        cd \(shellQuoted(descriptor.workspaceDirectory)) || exit 1
        echo "Headroom is opening the official Claude CLI."
        echo "\(accountGuidance)"
        echo "The /usage status check does not spend model usage."
        echo "Headroom never receives your password or sign-in details."
        echo
        """

        guard let executablePath = descriptor.executablePath else {
            return introduction + "\n" + """
            echo "Claude Code CLI was not found. Install or update Claude Code, then reopen Headroom."
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation = "\(executable)"
        let launch = descriptor.completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: .standard)
        } ?? "exec \(invocation)"
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The Claude CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
