import Foundation

/// The official Codex CLI handoff owned by Headroom. Keeping the executable and
/// arguments here prevents provider copy, Terminal execution, and clipboard fallback
/// from drifting onto different login commands.
public enum CodexCLI {
    public static let executableName = "codex"
    public static let loginArguments = ["login"]
    public static let loginCommand = "codex login"

    public static func resolveExecutable() -> String? {
        CLIExecutableResolver.resolve(
            named: executableName,
            fallbackPaths: [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "\(NSHomeDirectory())/.local/bin/codex",
            ]
        )
    }

    /// Static, redaction-safe Terminal content. The only runtime value is an absolute
    /// executable path returned by `CLIExecutableResolver`, quoted as one shell token.
    public static func loginScript(executablePath: String?) -> String {
        let introduction = """
        #!/bin/zsh
        clear
        export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
        echo "Headroom is opening the official Codex sign-in flow."
        echo "Complete sign-in in the browser, then return to Headroom."
        echo "Headroom never receives your password or sign-in details."
        echo
        """

        guard let executablePath else {
            return introduction + "\n" + """
            echo "Codex CLI was not found. Install or update Codex, then run: \(loginCommand)"
            echo
            echo "Press any key to close this window."
            read -k 1
            exit 127
            """
        }

        let executable = shellQuoted(executablePath)
        return introduction + "\n" + """
        if [[ ! -x \(executable) ]]; then
          echo "The Codex CLI moved or is no longer executable. Reopen Headroom and try again."
          echo
          echo "Press any key to close this window."
          read -k 1
          exit 127
        fi
        exec \(executable) \(loginArguments.joined(separator: " "))
        """
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public enum CodexConnectionAction: Sendable, Equatable {
    case connect
    case reconnect
}

public extension UsageSnapshot {
    /// Only typed Codex credential failures enter guided setup. Network, decoding,
    /// scope, pending, live, and other-provider states retain their normal UI.
    var codexConnectionAction: CodexConnectionAction? {
        guard providerID == .codex, case .stale(let reason) = freshness else { return nil }
        switch reason {
        case .notLoggedIn:
            return .connect
        case .needsReauth:
            return .reconnect
        case .transient, .scopeDenied, .decode:
            return nil
        }
    }
}
