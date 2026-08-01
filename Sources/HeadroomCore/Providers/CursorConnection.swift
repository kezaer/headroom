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

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
