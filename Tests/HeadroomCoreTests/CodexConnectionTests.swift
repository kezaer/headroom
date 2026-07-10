import Foundation
import Testing
@testable import HeadroomCore

struct CodexConnectionTests {
    @Test func missingCredentialsRequestInitialConnection() {
        let snapshot = UsageSnapshot.stale(
            for: .codex,
            reason: .notLoggedIn("Codex isn't logged in — run `codex login`")
        )

        #expect(snapshot.codexConnectionAction == .connect)
        #expect(CodexCLI.loginCommand == "codex login")
    }

    @Test func rejectedCredentialsRequestReconnectAndKeepWindows() {
        let window = UsageWindow(
            kind: .weekly,
            utilization: 42,
            resetsAt: Date(timeIntervalSince1970: 2_000_000)
        )
        let snapshot = UsageSnapshot(
            providerID: .codex,
            windows: [window],
            planLabel: "plus",
            capturedAt: Date(timeIntervalSince1970: 1_000_000),
            freshness: .stale(.needsReauth("Session expired — run `codex login` to reconnect"))
        )

        #expect(snapshot.codexConnectionAction == .reconnect)
        #expect(snapshot.windows == [window])
    }

    @Test func unrelatedStatesDoNotRequestCodexConnection() {
        let excluded: [UsageSnapshot] = [
            .pending(for: .codex),
            UsageSnapshot(
                providerID: .codex,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .live
            ),
            .stale(for: .codex, reason: .transient("Network unavailable")),
            .stale(for: .codex, reason: .decode("Couldn't decode")),
            .stale(for: .codex, reason: .scopeDenied("Scope unavailable")),
            .stale(for: .claude, reason: .notLoggedIn("Run Claude")),
        ]

        for snapshot in excluded {
            #expect(snapshot.codexConnectionAction == nil)
        }
    }

    @Test func selectsExecutableFromLoginShellIncludingVersionManagers() {
        let executablePaths: Set<String> = [
            "/opt/homebrew/bin/codex",
            "/Users/test/.local/bin/codex",
            "/Users/test/.nvm/versions/node/v24.18.0/bin/codex",
        ]

        for path in executablePaths {
            #expect(
                CLIExecutableResolver.selectExecutable(
                    loginShellOutput: "\(path)\n",
                    fallbackPaths: [],
                    isExecutable: executablePaths.contains
                ) == path
            )
        }
    }

    @Test func executableResolutionFallsBackAndFailsClosed() {
        let fallback = "/usr/local/bin/codex"
        #expect(
            CLIExecutableResolver.selectExecutable(
                loginShellOutput: "/missing/codex\n",
                fallbackPaths: ["/also/missing", fallback],
                isExecutable: { $0 == fallback }
            ) == fallback
        )
        #expect(
            CLIExecutableResolver.selectExecutable(
                loginShellOutput: "/missing/codex\n",
                fallbackPaths: ["/also/missing"],
                isExecutable: { _ in false }
            ) == nil
        )
    }

    @Test func generatedLoginScriptUsesOnlyQuotedExecutableAndAllowlistedArgument() {
        let script = CodexCLI.loginScript(executablePath: "/Users/Test User/bin/cod'ex")

        #expect(script.contains("exec '/Users/Test User/bin/cod'\\''ex' login"))
        #expect(script.contains("Headroom never receives your password or sign-in details"))
        #expect(!script.localizedCaseInsensitiveContains("access_token"))
        #expect(!script.localizedCaseInsensitiveContains("authorization"))
        #expect(!script.contains("backend-api"))
    }

    @Test func missingExecutableScriptFailsClearlyWithoutGuessingACommand() {
        let script = CodexCLI.loginScript(executablePath: nil)

        #expect(script.contains("Codex CLI was not found"))
        #expect(script.contains("exit 127"))
        #expect(!script.contains("exec codex"))
    }
}
