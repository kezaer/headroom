import Foundation

/// Official Cursor Agent browser-login handoff. Headroom observes only the wrapper's
/// redaction-safe exit marker and never reads or copies the stored credential.
public enum CursorCLI {
    public static let executableName = "cursor-agent"
    public static let loginCommand = "cursor-agent login"

    public static func resolveExecutable() -> String? {
        CursorUsageCLIProbe.resolveCursorPath()
    }

    public static func loginScript(
        executablePath: String?,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let introduction = """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        echo "Headroom is opening the official Cursor Agent sign-in flow."
        echo "Complete sign-in in the browser, then return to Headroom."
        echo "Headroom never receives your password or sign-in details."
        echo
        """

        guard let executablePath else {
            return introduction + "\n" + """
            echo "Cursor Agent was not found. Install or update it, then run: \(loginCommand)"
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        let invocation = "\(executable) login"
        let launch = completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: .standard)
        } ?? "exec \(invocation)"
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "Cursor Agent moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        \(launch)
        """
    }

    /// Cursor's `--trust` flag does not skip the trust menu in interactive mode.
    /// The user makes that decision in the official CLI; Headroom only stages the
    /// same empty workspace used by its usage probe.
    public static func workspaceTrustCommand(executablePath: String, workspaceDirectory: String) -> String {
        let workspace = shellQuoted(workspaceDirectory)
        return "unset CURSOR_API_KEY CURSOR_API_ENDPOINT; cd \(workspace) && \(shellQuoted(executablePath)) --mode ask --workspace \(workspace)"
    }

    public static func workspaceTrustScript(
        executablePath: String,
        workspaceDirectory: String,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        let executable = shellQuoted(executablePath)
        let invocation = workspaceTrustCommand(
            executablePath: executablePath,
            workspaceDirectory: workspaceDirectory
        )
        let launch = completionMarker.map {
            SetupCompletionCommand.wrap(invocation, marker: $0, mode: .standard)
        } ?? invocation
        return """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        unset CURSOR_API_KEY CURSOR_API_ENDPOINT
        echo "Headroom needs Cursor Agent to trust its empty usage workspace."
        echo "Choose [a] Trust this workspace, then quit Cursor Agent and return to Headroom."
        echo "Headroom will check your usage again after this window closes."
        echo
        if [[ ! -x \(executable) ]]; then
          echo "Cursor Agent moved or is no longer executable. Reopen Headroom and try again."
          exit 127
        fi
        \(launch)
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
