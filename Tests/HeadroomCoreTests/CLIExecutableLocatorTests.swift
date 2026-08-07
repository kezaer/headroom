import Foundation
import Testing
@testable import HeadroomCore

struct CLIExecutableLocatorTests {
    @Test func validPersistedHintAvoidsLoginShellAndIsRevalidated() async {
        let hints = TestExecutableHintStore(["claude": "/persisted/claude"])
        let shell = ShellSearchRecorder(result: .completed(candidates: ["/shell/claude"]))
        let validation = CandidateValidationRecorder(statuses: ["/persisted/claude": .executable])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { validation.status(for: $0) }
        )

        #expect(await locator.locate() == .available(path: "/persisted/claude", source: .persistedHint))
        #expect(await shell.count == 0)
        #expect(validation.paths == ["/persisted/claude"])
    }

    @Test func invalidatedHintRediscoveriesOnceAndCachesReplacement() async {
        let hints = TestExecutableHintStore(["claude": "/moved/claude"])
        let shell = ShellSearchRecorder(result: .completed(candidates: ["/new/claude"]))
        let validation = CandidateValidationRecorder(statuses: [
            "/moved/claude": .missing,
            "/new/claude": .executable,
        ])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: hints,
            shellSearch: { await shell.search() },
            validate: { validation.status(for: $0) }
        )

        #expect(await locator.locate() == .available(path: "/new/claude", source: .loginShell))
        #expect(await locator.locate() == .available(path: "/new/claude", source: .memoryHint))
        #expect(await shell.count == 1)
        #expect(hints.hint(for: "claude") == "/new/claude")
        #expect(await locator.recentDiagnosticEvents().map(\.category) == [
            .hintInvalidated,
            .loginShellResolved,
            .memoryHintValidated,
        ])
    }

    @Test func onlyCompletedSearchWithoutCandidatesConfirmsAbsence() async {
        for result in [
            CLIExecutableShellResult.timedOut,
            .spawnFailed,
            .invalidOutput,
        ] {
            let locator = makeLocator(shellResult: result)
            guard case .inconclusive = await locator.locate() else {
                Issue.record("Expected \(result) to remain inconclusive")
                continue
            }
        }

        let absent = makeLocator(shellResult: .completed(candidates: []))
        #expect(await absent.locate() == .confirmedAbsent)
    }

    @Test func inaccessibleCandidateIsInconclusiveButMissingFallbackConfirmsAbsence() async {
        let inaccessible = makeLocator(
            shellResult: .completed(candidates: ["/private/claude"]),
            validation: ["/private/claude": .inaccessible]
        )
        #expect(await inaccessible.locate() == .inconclusive(.inaccessibleCandidate))

        let absent = makeLocator(
            shellResult: .completed(candidates: []),
            fallbackPaths: ["/opt/homebrew/bin/claude"],
            validation: ["/opt/homebrew/bin/claude": .missing]
        )
        #expect(await absent.locate() == .confirmedAbsent)
    }

    @Test func fallbackCanRecoverFromLoginShellFailure() async {
        let locator = makeLocator(
            shellResult: .timedOut,
            fallbackPaths: ["/opt/homebrew/bin/claude"],
            validation: ["/opt/homebrew/bin/claude": .executable]
        )

        #expect(await locator.locate() == .available(path: "/opt/homebrew/bin/claude", source: .fallback))
        #expect(await locator.recentDiagnosticEvents().last?.category == .fallbackResolved)
    }

    @Test func concurrentCallersShareDiscoveryAndCancelledWaiterDoesNotCancelIt() async {
        let shell = SuspendedShellSearch()
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { $0 == "/shell/claude" ? .executable : .missing }
        )

        let cancelled = Task { await locator.locate() }
        let surviving = Task { await locator.locate() }
        while await shell.count == 0 { await Task.yield() }
        cancelled.cancel()
        await shell.resume(with: .completed(candidates: ["/shell/claude"]))

        #expect(await surviving.value == .available(path: "/shell/claude", source: .loginShell))
        #expect(await shell.count == 1)
    }

    @Test func invalidationAllowsLaterCycleToFindNewInstall() async {
        let shell = ShellSearchRecorder(result: .completed(candidates: ["/old/claude"]))
        let validation = CandidateValidationRecorder(statuses: [
            "/old/claude": .executable,
            "/new/claude": .executable,
        ])
        let locator = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(),
            shellSearch: { await shell.search() },
            validate: { validation.status(for: $0) }
        )
        #expect(await locator.locate() == .available(path: "/old/claude", source: .loginShell))

        await locator.invalidate(path: "/old/claude", reason: .launchNotFound)
        await shell.setResult(.completed(candidates: ["/new/claude"]))

        #expect(await locator.locate() == .available(path: "/new/claude", source: .loginShell))
        #expect(await shell.count == 2)
        #expect(await locator.recentDiagnosticEvents().map(\.category).contains(.launchRace))
    }

    @Test func diagnosticsDistinguishValidHintTimeoutAndSupportedLocationMiss() async {
        let clock = Date(timeIntervalSince1970: 20_000)
        let hinted = CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [],
            hintStore: TestExecutableHintStore(["claude": "/hint/claude"]),
            shellSearch: { .completed(candidates: []) },
            validate: { $0 == "/hint/claude" ? .executable : .missing },
            now: { clock }
        )
        _ = await hinted.locate()
        #expect(await hinted.recentDiagnosticEvents() == [
            CLIExecutableDiagnosticEvent(category: .persistedHintValidated, observedAt: clock),
        ])

        let timedOut = makeLocator(shellResult: .timedOut)
        _ = await timedOut.locate()
        #expect(await timedOut.recentDiagnosticEvents().last?.category == .shellTimeout)

        let absent = makeLocator(shellResult: .completed(candidates: []))
        _ = await absent.locate()
        #expect(await absent.recentDiagnosticEvents().last?.category == .supportedLocationMiss)
    }

    private func makeLocator(
        shellResult: CLIExecutableShellResult,
        fallbackPaths: [String] = [],
        validation: [String: CLIExecutableCandidateStatus] = [:]
    ) -> CLIExecutableLocator {
        CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: fallbackPaths,
            hintStore: TestExecutableHintStore(),
            shellSearch: { shellResult },
            validate: { validation[$0] ?? .missing }
        )
    }
}

private final class TestExecutableHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var hints: [String: String]

    init(_ hints: [String: String] = [:]) { self.hints = hints }

    func hint(for executableName: String) -> String? {
        lock.withLock { hints[executableName] }
    }

    func setHint(_ path: String?, for executableName: String) {
        lock.withLock { hints[executableName] = path }
    }
}

private actor ShellSearchRecorder {
    private(set) var count = 0
    private var result: CLIExecutableShellResult

    init(result: CLIExecutableShellResult) { self.result = result }

    func search() -> CLIExecutableShellResult {
        count += 1
        return result
    }

    func setResult(_ result: CLIExecutableShellResult) { self.result = result }
}

private actor SuspendedShellSearch {
    private(set) var count = 0
    private var continuation: CheckedContinuation<CLIExecutableShellResult, Never>?

    func search() async -> CLIExecutableShellResult {
        count += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func resume(with result: CLIExecutableShellResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private final class CandidateValidationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let statuses: [String: CLIExecutableCandidateStatus]
    private var recordedPaths: [String] = []

    init(statuses: [String: CLIExecutableCandidateStatus]) { self.statuses = statuses }

    var paths: [String] { lock.withLock { recordedPaths } }

    func status(for path: String) -> CLIExecutableCandidateStatus {
        lock.withLock {
            recordedPaths.append(path)
            return statuses[path] ?? .missing
        }
    }
}
