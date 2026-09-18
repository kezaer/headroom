import Foundation

/// Official Cursor Agent browser-login handoff. Headroom observes only the wrapper's
/// redaction-safe exit marker and never reads or copies the stored credential.
public enum CursorCLI {
    public static let executableName = "cursor-agent"
    public static let loginCommand = "cursor-agent login"
    // Match the subscription probe and use the executable Headroom actually found.
    public static func manualLoginCommand(executablePath: String) -> String {
        "env -u CURSOR_API_KEY -u CURSOR_API_ENDPOINT \(shellQuoted(executablePath)) login"
    }

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
        unset CURSOR_API_KEY CURSOR_API_ENDPOINT
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

    /// Cursor's `--trust` flag does not skip the trust menu in interactive mode (it is
    /// an open Cursor feature request, forum.cursor.com/t/162011). The user makes that
    /// decision in the official CLI; Headroom only stages the same empty workspace used
    /// by its usage probe. The interactive CLI exits on `/quit` or a double Ctrl+C; a
    /// single Ctrl+C is swallowed, which is why the instructions name both.
    public static func workspaceTrustCommand(executablePath: String, workspaceDirectory: String) -> String {
        let workspace = shellQuoted(workspaceDirectory)
        return "unset CURSOR_API_KEY CURSOR_API_ENDPOINT; cd \(workspace) && \(shellQuoted(executablePath)) --mode ask --workspace \(workspace)"
    }

    public static func workspaceTrustScript(
        executablePath: String,
        workspaceDirectory: String,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        approvalScript(
            executablePath: executablePath,
            workspaceDirectory: workspaceDirectory,
            completionMarker: completionMarker,
            reason: "Headroom needs Cursor Agent to trust its empty usage workspace.",
            instruction: "Choose [a] Trust this workspace. When the prompt appears, type /quit and press Return (or press Ctrl+C twice)."
        )
    }

    public static func mcpApprovalScript(
        executablePath: String,
        workspaceDirectory: String,
        completionMarker: SetupCompletionMarker? = nil
    ) -> String {
        approvalScript(
            executablePath: executablePath,
            workspaceDirectory: workspaceDirectory,
            completionMarker: completionMarker,
            reason: "Cursor Agent wants approval for configured external tools.",
            instruction: "Review Cursor Agent’s external tools. Approve only ones you trust; then type /quit and press Return (or press Ctrl+C twice)."
        )
    }

    private static func approvalScript(
        executablePath: String,
        workspaceDirectory: String,
        completionMarker: SetupCompletionMarker?,
        reason: String,
        instruction: String
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
        echo "\(reason)"
        echo "\(instruction)"
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
