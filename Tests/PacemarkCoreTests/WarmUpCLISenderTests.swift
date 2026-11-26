import Darwin
import Foundation
import Testing
@testable import PacemarkCore

struct WarmUpCLISenderTests {
    @Test func timeoutKillsTheGrandchildProcessGroup() async throws {
        let fake = try FakeWarmUpCLI("""
        /bin/sh -c 'trap "" TERM; echo "$$" > "$HOME/worker.pid"; while :; do sleep 1; done' worker &
        wait
        """)
        defer { fake.remove() }
        let outcome = await fake.sender(timeout: 2).send(fake.claudeRequest()) { true }
        #expect(outcome == .failed(.timedOut))
        let pidFile = fake.directory.appendingPathComponent("worker.pid")
        let line = try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try #require(pid_t(line))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if kill(pid, 0) == -1 && errno == ESRCH { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Warm-up left its grandchild process running")
    }

    @Test func stdoutIsWritableAtTheNullDevice() async throws {
        let fake = try FakeWarmUpCLI("""
        /usr/bin/perl -e '
          my @null = stat("/dev/null");
          my @out = stat(STDOUT);
          exit 3 unless @null && @out && $out[0] == $null[0] && $out[1] == $null[1];
          print STDOUT "Unparsed client output";
          print STDERR "Unparsed diagnostic";
        '
        """)
        defer { fake.remove() }
        #expect(await fake.sender().send(fake.claudeRequest()) { true } == .sent)
    }

    @Test func nonzeroExitReportsClientFailure() async throws {
        let fake = try FakeWarmUpCLI("exit 19")
        defer { fake.remove() }
        #expect(await fake.sender().send(fake.claudeRequest()) { true } == .failed(.exitedNonZero(19)))
    }

    @Test(arguments: ["unknown option", "not logged in"])
    func classifiesFixedDiagnostics(_ message: String) async throws {
        let fake = try FakeWarmUpCLI("echo '\(message)' >&2; exit 1")
        defer { fake.remove() }
        let expected: WarmUpFailure = message == "unknown option" ? .rejectedArguments : .signedOut
        #expect(await fake.sender().send(fake.claudeRequest()) { true } == .failed(expected))
    }

    @Test func exitedLeaderDoesNotWaitForInheritedStderr() async throws {
        let fake = try FakeWarmUpCLI("/bin/sleep 30 &\nexit 0")
        defer { fake.remove() }
        let start = ContinuousClock.now
        #expect(await fake.sender(timeout: 10).send(fake.claudeRequest()) { true } == .sent)
        #expect(start.duration(to: .now) < .seconds(5))
    }

    @Test(arguments: [true, false])
    func antigravityUsesProtectedWorkspaceAndRecognizesOnlyItsSignInPrompt(prompt: Bool) async throws {
        let version = try #require(Bundle.module.url(forResource: "antigravity-version-live", withExtension: "stdout"))
        let usage = try #require(Bundle.module.url(forResource: "antigravity-usage-live", withExtension: "stdout"))
        let fake = try FakeWarmUpCLI("""
        case "$1:$2" in
            --version:) cat '\(version.path)'; exit 0;;
            -p:/usage) cat '\(usage.path)'; exit 0;;
            -p:/credits) exit 1;;
        esac
        test "$USER" = fixture && test "$TMPDIR" = /fixture-tmp || exit 14
        test "$BROWSER" = /usr/bin/false && test "$AGY_CLI_DISABLE_AUTO_UPDATE" = true || exit 10
        test "$(readlink "$(command -v open)")" = /usr/bin/false || exit 11
        test "$PWD" = "$HOME/work" || exit 12
        test "$1" = -p && test "$3" = --model && test "$4" = 'Gemini 3.8 Flash' || exit 13
        touch "$HOME/launched"
        echo '\(prompt ? "Authentication required" : "not logged in")' >&2
        \(prompt ? "sleep 15" : "exit 0")
        """)
        defer { fake.remove() }
        let source = AntigravityCLIUsageSource(resolveExecutable: { fake.executable },
            resolveLoginPath: { "/usr/bin:/bin" }, inheritedEnvironment: { ["USER": "fixture", "TMPDIR": "/fixture-tmp"] },
            workingDirectory: fake.directory.appendingPathComponent("work").path)
        let sender = fake.sender(antigravity: source)
        let request = fake.request(.builtIn(for: .antigravity))
        let diagnostic = try #require(await sender.diagnostic(for: .antigravity))
        #expect(diagnostic.last == "Environment keys: AGY_CLI_DISABLE_AUTO_UPDATE, BROWSER, HOME, LANG, PATH, PWD, TMPDIR, USER")
        #expect(await sender.send(request) { true } == .skipped)
        #expect(!fake.launched)
        guard case .usage = await source.capture() else { Issue.record("Expected fixture usage"); return }
        #expect(await sender.send(request) { true } == (prompt ? .failed(.signedOut) : .sent))
        #expect(fake.launched)
        if !prompt { return }
        try FileManager.default.removeItem(at: fake.directory.appendingPathComponent("launched"))
        #expect(await sender.send(request) { true } == .failed(.signedOut))
        #expect(!fake.launched)
    }

    @Test func missingExtraHomeSkipsWithoutLaunching() async throws {
        let fake = try FakeWarmUpCLI("touch \"$HOME/launched\"")
        defer { fake.remove() }
        let account = ProviderAccount(id: AccountID("missing"), providerID: .claude, label: "Missing")
        #expect(await fake.sender().send(fake.request(account)) { true } == .skipped)
        #expect(!fake.launched)
    }

    @Test func borrowedHomeReplacedWithASymlinkDuringLaunchCheckIsRejected() async throws {
        let fake = try FakeWarmUpCLI("touch \"$HOME/launched\"")
        defer { fake.remove() }
        let selected = fake.directory.appendingPathComponent("selected")
        let other = fake.directory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: false)
        let canonical = try #require(BorrowedHomePaths.existingDirectory(selected))
        let home = BorrowedHome(path: canonical, source: .manual, preferredExecutable: fake.executable)
        let account = ProviderAccount(borrowing: home, providerID: .codex, label: "Borrowed")
        let outcome = await fake.sender().send(fake.request(account)) {
            do {
                try FileManager.default.removeItem(at: selected)
                try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: other)
                return true
            } catch {
                Issue.record("Could not replace fixture home: \(error)")
                return false
            }
        }
        #expect(outcome == .skipped)
        #expect(!fake.launched)
    }
}

private struct FakeWarmUpCLI {
    let directory: URL
    let executable: String

    init(_ body: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WarmUpCLI-\(UUID())")
        let script = directory.appendingPathComponent("fake-client")
        executable = script.path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try ("#!/bin/sh\n" + body + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable)
        } catch {
            remove()
            throw error
        }
    }

    var launched: Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("launched").path)
    }

    func sender(timeout: TimeInterval = 5, antigravity: AntigravityCLIUsageSource? = nil) -> WarmUpCLISender {
        WarmUpCLISender(
            claudeLocator: FixtureLocator(path: executable), userHome: directory,
            accountsBase: directory.appendingPathComponent("accounts"),
            loginPathOverride: "/usr/bin:/bin", timeout: timeout, antigravity: antigravity
        )
    }

    func request(_ account: ProviderAccount) -> WarmUpRequest {
        var ledger = WarmUpLedger()
        return WarmUpRequest(
            account: account, attempt: ledger.reserve(account.key, identity: nil, at: .now),
            windowIDs: [WindowKind.weekly.persistentID], attachmentGeneration: 0
        )
    }

    func claudeRequest() -> WarmUpRequest { request(.builtIn(for: .claude)) }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    private struct FixtureLocator: CLIExecutableLocating {
        let path: String

        func locate(forceRefresh: Bool) async -> CLIExecutableLocation {
            .available(path: path, source: .fallback)
        }

        func invalidate(path: String, reason: CLIExecutableInvalidationReason) async {}
        func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent] { [] }
    }
}
