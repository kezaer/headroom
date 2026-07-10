import Foundation
import Darwin

/// The source of Claude usage text — injected so the provider can be tested with a
/// fixture panel instead of spawning the real CLI.
public protocol ClaudeUsageSource: Sendable {
    /// Returns the ANSI-stripped text of Claude Code's `/usage` panel, or nil when the
    /// CLI is missing / not logged in / the capture failed.
    func capturePanel() async -> ClaudePanelResult
}

/// Outcome of a capture attempt — lets the provider distinguish "no CLI" from a
/// transient read failure so it can show the right degrade message.
public enum ClaudePanelResult: Sendable, Equatable {
    case panel(String)
    case cliNotFound
    case failed
}

/// Drives the interactive `claude` CLI in a pseudo-terminal, sends `/usage`, and
/// returns the rendered panel text. This is the compliant path to the real 5-hour /
/// weekly windows: the official client makes the request (a free status fetch, no model
/// call), and this only reads what it prints.
///
/// Robustness is the whole point here — a TUI scrape is inherently fragile, so every
/// failure mode is contained: a hard wall-clock deadline, a guaranteed process-group
/// kill in all exit paths, "quiet-period" capture that survives the panel's multiple
/// re-renders, and login-shell PATH resolution so it finds `claude` even when launched
/// from Finder with a bare environment.
public struct ClaudeUsageCLIProbe: ClaudeUsageSource {
    public let claudePath: String?
    public let workingDirectory: String
    public let bootTimeout: TimeInterval
    public let panelTimeout: TimeInterval

    public init(
        claudePath: String? = ClaudeUsageCLIProbe.resolveClaudePath(),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        bootTimeout: TimeInterval = 30,
        panelTimeout: TimeInterval = 26
    ) {
        self.claudePath = claudePath
        self.workingDirectory = workingDirectory
        self.bootTimeout = bootTimeout
        self.panelTimeout = panelTimeout
    }

    public func capturePanel() async -> ClaudePanelResult {
        guard let claudePath, FileManager.default.isExecutableFile(atPath: claudePath) else {
            return .cliNotFound
        }
        // Run the blocking pty work off the cooperative pool.
        return await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let raw = Self.runBlocking(
                    claudePath: claudePath,
                    workingDirectory: workingDirectory,
                    boot: bootTimeout,
                    panel: panelTimeout
                )
                guard let raw, !raw.isEmpty else {
                    continuation.resume(returning: .failed); return
                }
                continuation.resume(returning: .panel(ANSI.strip(raw)))
            }
        }
    }

    /// Resolve `claude` via the user's login shell so a Finder-launched app (bare PATH)
    /// still finds an nvm/homebrew install. Falls back to common locations.
    public static func resolveClaudePath() -> String? {
        CLIExecutableResolver.resolve(
            named: "claude",
            fallbackPaths: [
                "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                "\(NSHomeDirectory())/.local/bin/claude",
            ]
        )
    }

    /// The user's real PATH via a login shell, so a Finder-launched app (bare PATH)
    /// still resolves node/nvm the way the terminal does. Falls back to a sane default.
    private static func loginPath() -> String {
        let fallback = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-lic", "printf %s \"$PATH\""]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = Pipe()
        do {
            try probe.run()
            probe.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let out, !out.isEmpty { return "\(out):\(fallback)" }
        } catch {}
        return fallback
    }

    // MARK: pty mechanics

    private static func runBlocking(
        claudePath: String,
        workingDirectory: String,
        boot: TimeInterval,
        panel: TimeInterval
    ) -> String? {
        var master: Int32 = -1
        var slave: Int32 = -1
        var win = winsize(ws_row: 45, ws_col: 140, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &win) == 0 else { return nil }

        var fileActions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&fileActions)
        // Darwin exposed the chdir spawn action as `_np` from macOS 10.15 through
        // Sequoia, then standardized the unsuffixed symbol in Tahoe. Keep the working
        // directory as a spawn action on both paths so the child never races a
        // process-wide chdir and Finder-launched probes retain their stable workspace.
        if #available(macOS 26.0, *) {
            posix_spawn_file_actions_addchdir(&fileActions, workingDirectory)
        } else {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
        }
        posix_spawn_file_actions_adddup2(&fileActions, slave, 0)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
        posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
        posix_spawn_file_actions_addclose(&fileActions, master)

        var attr = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attr)
        // New session so the child leads its own process group (clean group-kill) and
        // the pty becomes its controlling terminal — the TUI needs a tty to render.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        // Inherit the user's environment (so a node-based `claude` shim finds `node`),
        // augmenting PATH via the login shell, and force a real TERM for TUI rendering.
        var envDict = ProcessInfo.processInfo.environment
        envDict["TERM"] = "xterm-256color"
        envDict["COLUMNS"] = "140"
        envDict["LINES"] = "45"
        envDict["LANG"] = envDict["LANG"] ?? "en_US.UTF-8"
        envDict["PATH"] = loginPath()
        envDict["PWD"] = workingDirectory
        let env = envDict.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let argv = [claudePath]
        let cEnv = env.map { strdup($0) } + [nil]
        let cArgv = argv.map { strdup($0) } + [nil]
        defer {
            cEnv.forEach { free($0) }
            cArgv.forEach { free($0) }
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attr)
        }

        let spawnResult = posix_spawn(&pid, claudePath, &fileActions, &attr, cArgv, cEnv)
        close(slave)
        guard spawnResult == 0 else { close(master); return nil }

        // Guaranteed teardown regardless of how we leave.
        func teardown() {
            _ = write(master, "\u{03}", 1) // Ctrl-C
            kill(-pid, SIGTERM)
            // Reap with a short grace period, then SIGKILL.
            var status: Int32 = 0
            for _ in 0..<50 {
                if waitpid(pid, &status, WNOHANG) == pid { break }
                usleep(20_000)
            }
            kill(-pid, SIGKILL)
            waitpid(pid, &status, 0)
            close(master)
        }

        var buffer = Data()
        drain(master: master, maxSeconds: boot, quiet: 2.5, into: &buffer) // boot + prompt
        if let bootText = String(data: buffer, encoding: .utf8),
           ANSI.strip(bootText).localizedCaseInsensitiveContains("Quick safety check") {
            teardown()
            return bootText
        }
        usleep(800_000) // let the input box settle before typing
        _ = "/usage".withCString { write(master, $0, strlen($0)) }
        usleep(500_000) // gap so the slash-command autocomplete resolves before Enter
        // Claude Code 2.1.200 can consume the first Enter to accept the `/usage`
        // autocomplete row; the second Enter executes the accepted command.
        _ = "\r".withCString { write(master, $0, strlen($0)) }
        usleep(250_000)
        _ = "\r".withCString { write(master, $0, strlen($0)) }
        // Longer quiet window than boot: the panel renders the primary limits first, then
        // pauses to compute the model-specific weekly sub-limits ("Current week (Fable)")
        // before painting the settled panel. On a cold start (e.g. right after an app
        // update) that pause can exceed a short quiet window, so a 2.5s drain concluded
        // before the sub-limit line rendered — the parser needs the clean line, so Fable
        // went missing until the next poll. 4s bridges that settle pause.
        drain(master: master, maxSeconds: panel, quiet: 4.0, into: &buffer) // the panel
        teardown()

        return String(data: buffer, encoding: .utf8) ?? String(decoding: buffer, as: UTF8.self)
    }

    /// Read from the pty until `quiet` seconds pass with no new bytes, or `maxSeconds`
    /// elapse — captures the panel across its several re-renders without hanging.
    private static func drain(master: Int32, maxSeconds: TimeInterval, quiet: TimeInterval, into buffer: inout Data) {
        let deadline = Date().addingTimeInterval(maxSeconds)
        var lastData = Date()
        var pfd = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 65536)
        while Date() < deadline {
            let ready = poll(&pfd, 1, 200)
            if ready > 0, pfd.revents & Int16(POLLIN) != 0 {
                let n = read(master, &chunk, chunk.count)
                if n > 0 { buffer.append(contentsOf: chunk[0..<n]); lastData = Date() }
                else { break } // EOF / EIO — child gone
            } else if Date().timeIntervalSince(lastData) > quiet {
                break
            }
        }
    }
}

/// Strips ANSI/VT control sequences so the panel text can be parsed.
enum ANSI {
    static func strip(_ text: String) -> String {
        var out = text
        // ICU regex escapes use \xHH (not Swift's \u{..}). CSI sequences, charset
        // selects, OSC strings, and stray control bytes.
        for pattern in [
            #"\x1B\[[0-9;?]*[ -/]*[@-~]"#,
            #"\x1B[()][A-Za-z0-9]"#,
            #"\x1B[=>]"#,
            #"\x1B\][^\x07]*\x07"#,
            #"[\x00-\x08\x0B\x0C\x0E-\x1F]"#,
        ] {
            out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return out
    }
}
