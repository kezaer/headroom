import Foundation
import Darwin

/// Resolves an installed CLI through the user's login shell so Finder-launched app
/// processes can find Homebrew and version-manager installs that are absent from their
/// inherited PATH. Callers supply only hard-coded executable names.
public enum CLIExecutableResolver {
    private static let executableMarker = "__HEADROOM_EXECUTABLE__"
    private static let pathMarker = "__HEADROOM_PATH__"

    public static func resolve(
        named executableName: String,
        fallbackPaths: [String]
    ) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !executableName.isEmpty,
              executableName.unicodeScalars.allSatisfy(allowed.contains) else { return nil }

        // Interactive login mode loads version-manager initialization commonly kept in
        // .zshrc (NVM/asdf/mise). Login-only mode can instead select an older global shim.
        let output = runLoginShell(
            command: "printf '\\n\(executableMarker)\\n'; command -v -- \(executableName)"
        )

        return selectExecutable(
            loginShellOutput: output,
            fallbackPaths: fallbackPaths,
            isExecutable: FileManager.default.isExecutableFile(atPath:)
        )
    }

    static func selectExecutable(
        loginShellOutput: String?,
        fallbackPaths: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        let rawOutput = loginShellOutput ?? ""
        let markedOutput = rawOutput.range(of: executableMarker, options: .backwards)
            .map { String(rawOutput[$0.upperBound...]) } ?? ""
        let shellCandidates = markedOutput
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return shellCandidates.last(where: isExecutable)
            ?? fallbackPaths.first(where: isExecutable)
    }

    public static func resolveLoginPath(fallback: String) -> String {
        let output = runLoginShell(command: "printf '\\n\(pathMarker)%s' \"$PATH\"")
        return selectLoginPath(loginShellOutput: output, fallback: fallback)
    }

    static func selectLoginPath(loginShellOutput: String?, fallback: String) -> String {
        guard let rawOutput = loginShellOutput,
              let markerRange = rawOutput.range(of: pathMarker, options: .backwards) else {
            return fallback
        }
        let marked = String(rawOutput[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !marked.isEmpty else { return fallback }
        return "\(marked):\(fallback)"
    }

    /// Shell startup files are user-controlled and can hang. Bound discovery so a bad
    /// profile cannot freeze app launch or a setup action indefinitely.
    private static func runLoginShell(command: String, timeout: TimeInterval = 5) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-lic", command]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = FileHandle.nullDevice

        do {
            try probe.run()
            let deadline = Date().addingTimeInterval(timeout)
            while probe.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            guard !probe.isRunning else {
                probe.terminate()
                let terminationDeadline = Date().addingTimeInterval(0.2)
                while probe.isRunning, Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if probe.isRunning {
                    kill(probe.processIdentifier, SIGKILL)
                    probe.waitUntilExit()
                }
                return nil
            }
            return String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )
        } catch {
            return nil
        }
    }
}
