import Foundation
import Darwin

/// Resolves an installed CLI through the user's login shell so Finder-launched app
/// processes can find Homebrew and version-manager installs that are absent from their
/// inherited PATH. Callers supply only hard-coded executable names.
/// Extra candidate source a bounded search may consult after a direct `command -v` miss.
/// Claude-only today (KTD4): other providers' installer behavior is uncharacterized.
public enum CLIExecutableSupplementalStrategy: Sendable, Equatable {
    case none
    case npmGlobalPrefix
}

/// Typed provenance for the supplemental section of one bounded search (KTD2). The
/// difference between "the source said no" and "the source could not be read" is what
/// keeps incomplete discovery from becoming confirmed absence (R3).
public enum CLIExecutableSupplementalResult: Sendable, Equatable {
    case notAttempted
    case sourceUnavailable
    case candidate(String)
    case unresolved
}

/// Which syntax the login shell running our command understands. fish is not POSIX —
/// `var=$(…)` and `if …; then …; fi` are syntax errors there, which would abort the whole
/// command before the marker is ever printed and turn every search into `.invalidOutput`.
enum CLIShellDialect: Sendable, Equatable {
    case posix
    case fish

    static func forShell(atPath shellPath: String) -> CLIShellDialect {
        (shellPath as NSString).lastPathComponent == "fish" ? .fish : .posix
    }
}

public enum CLIExecutableResolver {
    private static let executableMarker = "__PACEMARK_EXECUTABLE__"
    private static let pathMarker = "__PACEMARK_PATH__"
    private static let npmPrefixMarker = "__PACEMARK_NPM_PREFIX__"
    private static let npmAbsentMarker = "__PACEMARK_NPM_ABSENT__"

    /// The one shell every part of a search agrees on: the command dialect and the process
    /// that runs it must never be chosen independently.
    static var loginShellPath: String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    /// Shell startup files and npm are both user-controlled; the whole search — direct
    /// lookup plus any supplemental query — shares this one deadline (R3, AE7).
    static let loginShellTimeout: TimeInterval = 5

    public static func resolve(
        named executableName: String,
        fallbackPaths: [String]
    ) -> String? {
        guard isValidExecutableName(executableName) else { return nil }

        // Interactive login mode loads version-manager initialization commonly kept in
        // .zshrc (NVM/asdf/mise). Login-only mode can instead select an older global shim.
        let shell = loginShellPath
        let output: String?
        switch runLoginShell(
            command: searchCommand(named: executableName, supplemental: .none, shellPath: shell),
            shell: shell
        ) {
        case .completed(let value): output = value
        case .timedOut, .spawnFailed: output = nil
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
        let output: String?
        switch runLoginShell(command: "printf '\\n\(pathMarker)%s' \"$PATH\"") {
        case .completed(let value): output = value
        case .timedOut, .spawnFailed: output = nil
        }
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

    /// Typed, off-main discovery for refreshable locators. Only a normally completed
    /// shell command with its marker intact is evidence that the shell found no path.
    public static func searchExecutable(
        named executableName: String,
        supplemental: CLIExecutableSupplementalStrategy = .none
    ) async -> CLIExecutableShellResult {
        guard isValidExecutableName(executableName) else { return .invalidOutput }
        return await Task.detached(priority: .utility) {
            let shell = loginShellPath
            switch runLoginShell(
                command: searchCommand(
                    named: executableName,
                    supplemental: supplemental,
                    shellPath: shell
                ),
                shell: shell
            ) {
            case .timedOut:
                return .timedOut
            case .spawnFailed:
                return .spawnFailed
            case .completed(let output):
                return parseSearchOutput(
                    output,
                    executableName: executableName,
                    supplemental: supplemental
                )
            }
        }.value
    }

    /// One bounded shell operation gathers both sections. The shell cannot see the
    /// locator's fixed-fallback filesystem checks, so it conditions the npm query on a
    /// direct `command -v` miss only; selection priority is the locator's job (KTD1a).
    static func searchCommand(
        named executableName: String,
        supplemental: CLIExecutableSupplementalStrategy,
        shellPath: String = loginShellPath
    ) -> String {
        // The direct-only form is already dialect-neutral, so every shell gets it verbatim.
        let direct = "printf '\\n\(executableMarker)\\n'; command -v -- \(executableName)"
        switch supplemental {
        case .none:
            return direct
        case .npmGlobalPrefix:
            // Prefix output is printed as data and never sourced, evaluated, or
            // concatenated into shell syntax (KTD2).
            switch CLIShellDialect.forShell(atPath: shellPath) {
            case .posix:
                return """
                printf '\\n\(executableMarker)\\n'; \
                __pacemark_found=$(command -v -- \(executableName) || true); \
                printf '%s\\n' "$__pacemark_found"; \
                if [ -z "$__pacemark_found" ]; then \
                if command -v npm >/dev/null 2>&1; then \
                printf '\\n\(npmPrefixMarker)\\n'; npm prefix -g 2>/dev/null; \
                else printf '\\n\(npmAbsentMarker)\\n'; fi; fi
                """
            case .fish:
                // Same markers and same gating, expressed in fish syntax: `set var (cmd)`
                // for assignment and `if …; …; else; …; end` for branching.
                return """
                printf '\\n\(executableMarker)\\n'; \
                set __pacemark_found (command -v -- \(executableName)); \
                printf '%s\\n' "$__pacemark_found"; \
                if test -z "$__pacemark_found"; \
                if command -v npm >/dev/null 2>&1; \
                printf '\\n\(npmPrefixMarker)\\n'; npm prefix -g 2>/dev/null; \
                else; printf '\\n\(npmAbsentMarker)\\n'; end; end
                """
            }
        }
    }

    static func parseSearchOutput(
        _ output: String,
        executableName: String,
        supplemental: CLIExecutableSupplementalStrategy
    ) -> CLIExecutableShellResult {
        // Markers are protocol records, matched as whole lines: a path or noise line that
        // merely *contains* the marker text is data and must not resection the output (R2).
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
        guard let markerIndex = lines.lastIndex(where: { isMarkerLine($0, executableMarker) }) else {
            return .invalidOutput
        }
        let tail = lines[lines.index(after: markerIndex)...]

        var directSection = tail
        var prefixSection: ArraySlice<Substring>?
        var npmAbsent = false
        if let prefixMarker = tail.firstIndex(where: { isMarkerLine($0, npmPrefixMarker) }) {
            directSection = tail[..<prefixMarker]
            prefixSection = tail[tail.index(after: prefixMarker)...]
        } else if let absentMarker = tail.firstIndex(where: { isMarkerLine($0, npmAbsentMarker) }) {
            directSection = tail[..<absentMarker]
            npmAbsent = true
        }

        let candidates = records(in: directSection)
        return .completed(
            candidates: candidates,
            supplemental: supplementalResult(
                strategy: supplemental,
                prefixSection: prefixSection,
                npmAbsent: npmAbsent,
                executableName: executableName
            )
        )
    }

    private static func supplementalResult(
        strategy: CLIExecutableSupplementalStrategy,
        prefixSection: ArraySlice<Substring>?,
        npmAbsent: Bool,
        executableName: String
    ) -> CLIExecutableSupplementalResult {
        // R5: only the Claude-only npm strategy has a supplemental source to report on.
        guard strategy == .npmGlobalPrefix else { return .notAttempted }
        if npmAbsent { return .sourceUnavailable }
        if let prefixSection {
            return derivedNpmCandidate(from: prefixSection, executableName: executableName)
        }
        // No npm marker means npm was never consulted — either the protocol broke, or the
        // shell skipped the query because `command -v` printed something (an alias
        // definition is printed but is not a launcher). Either way npm remains unread, so
        // this can never harden into confirmed absence (R3).
        return .unresolved
    }

    /// npm documents `{prefix}/bin` as the Unix global executable directory (KTD1). Only
    /// one structurally valid, absolute, control-character-free record is accepted (R2).
    private static func derivedNpmCandidate(
        from prefixSection: ArraySlice<Substring>,
        executableName: String
    ) -> CLIExecutableSupplementalResult {
        let prefixes = records(in: prefixSection)
        guard prefixes.count == 1, let prefix = prefixes.first else { return .unresolved }
        guard prefix.hasPrefix("/"),
              !prefix.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return .unresolved
        }
        let normalized = (prefix as NSString).standardizingPath
        guard normalized.hasPrefix("/") else { return .unresolved }
        let candidate = (normalized as NSString)
            .appendingPathComponent("bin")
            .appending("/\(executableName)")
        return .candidate(candidate)
    }

    private static func records(in section: ArraySlice<Substring>) -> [String] {
        section
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isMarkerLine(_ line: Substring, _ marker: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines) == marker
    }

    private enum LoginShellResult {
        case completed(String)
        case timedOut
        case spawnFailed
    }

    private static func isValidExecutableName(_ executableName: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return !executableName.isEmpty
            && executableName.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// Shell startup files are user-controlled and can hang. Bound discovery so a bad
    /// profile cannot freeze app launch or a setup action indefinitely.
    private static func runLoginShell(
        command: String,
        shell: String = loginShellPath,
        timeout: TimeInterval = loginShellTimeout
    ) -> LoginShellResult {
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
                return .timedOut
            }
            return .completed(String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "")
        } catch {
            return .spawnFailed
        }
    }
}
