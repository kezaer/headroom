import Foundation

/// Resolves an installed CLI through the user's login shell so Finder-launched app
/// processes can find Homebrew and version-manager installs that are absent from their
/// inherited PATH. Callers supply only hard-coded executable names.
public enum CLIExecutableResolver {
    public static func resolve(
        named executableName: String,
        fallbackPaths: [String]
    ) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !executableName.isEmpty,
              executableName.unicodeScalars.allSatisfy(allowed.contains) else { return nil }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        // Interactive login mode loads version-manager initialization commonly kept in
        // .zshrc (NVM/asdf/mise). Login-only mode can instead select an older global shim.
        probe.arguments = ["-lic", "command -v -- \(executableName)"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = Pipe()

        var output: String?
        do {
            try probe.run()
            probe.waitUntilExit()
            output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )
        } catch {
            output = nil
        }

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
        let shellCandidates = (loginShellOutput ?? "")
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (shellCandidates + fallbackPaths).first(where: isExecutable)
    }
}
