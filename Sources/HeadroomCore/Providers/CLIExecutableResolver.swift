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

public enum CLIExecutableResolver {
    private static let executableMarker = "__HEADROOM_EXECUTABLE__"
    private static let pathMarker = "__HEADROOM_PATH__"
    private static let npmPrefixMarker = "__HEADROOM_NPM_PREFIX__"
    private static let npmAbsentMarker = "__HEADROOM_NPM_ABSENT__"

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
        let output: String?
        switch runLoginShell(command: searchCommand(named: executableName, supplemental: .none)) {
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
            switch runLoginShell(
                command: searchCommand(named: executableName, supplemental: supplemental)
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
        supplemental: CLIExecutableSupplementalStrategy
    ) -> String {
        let direct = "printf '\\n\(executableMarker)\\n'; command -v -- \(executableName)"
        switch supplemental {
        case .none:
            return direct
        case .npmGlobalPrefix:
            // Prefix output is printed as data and never sourced, evaluated, or
            // concatenated into shell syntax (KTD2).
            return """
            printf '\\n\(executableMarker)\\n'; \
            __headroom_found=$(command -v -- \(executableName) || true); \
            printf '%s\\n' "$__headroom_found"; \
            if [ -z "$__headroom_found" ]; then \
            if command -v npm >/dev/null 2>&1; then \
            printf '\\n\(npmPrefixMarker)\\n'; npm prefix -g 2>/dev/null; \
            else printf '\\n\(npmAbsentMarker)\\n'; fi; fi
            """
        }
    }

    static func parseSearchOutput(
        _ output: String,
        executableName: String,
        supplemental: CLIExecutableSupplementalStrategy
    ) -> CLIExecutableShellResult {
        guard let marker = output.range(of: executableMarker, options: .backwards) else {
            return .invalidOutput
        }
        let tail = output[marker.upperBound...]

        var directSection = tail
        var prefixSection: Substring?
        var npmAbsent = false
        if let prefixMarker = tail.range(of: npmPrefixMarker) {
            directSection = tail[..<prefixMarker.lowerBound]
            prefixSection = tail[prefixMarker.upperBound...]
        } else if let absentMarker = tail.range(of: npmAbsentMarker) {
            directSection = tail[..<absentMarker.lowerBound]
            npmAbsent = true
        }

        let candidates = records(in: directSection)
        return .completed(
            candidates: candidates,
            supplemental: supplementalResult(
                strategy: supplemental,
                directCandidates: candidates,
                prefixSection: prefixSection,
                npmAbsent: npmAbsent,
                executableName: executableName
            )
        )
    }

    private static func supplementalResult(
        strategy: CLIExecutableSupplementalStrategy,
        directCandidates: [String],
        prefixSection: Substring?,
        npmAbsent: Bool,
        executableName: String
    ) -> CLIExecutableSupplementalResult {
        guard strategy == .npmGlobalPrefix else { return .notAttempted }
        if npmAbsent { return .sourceUnavailable }
        if let prefixSection {
            return derivedNpmCandidate(from: prefixSection, executableName: executableName)
        }
        // The shell emits one npm marker whenever the direct lookup misses, so a missing
        // marker after a miss means the protocol broke — never confirmed absence (R3).
        return directCandidates.isEmpty ? .unresolved : .notAttempted
    }

    /// npm documents `{prefix}/bin` as the Unix global executable directory (KTD1). Only
    /// one structurally valid, absolute, control-character-free record is accepted (R2).
    private static func derivedNpmCandidate(
        from prefixSection: Substring,
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

    private static func records(in section: some StringProtocol) -> [String] {
        section
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        timeout: TimeInterval = loginShellTimeout
    ) -> LoginShellResult {
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
