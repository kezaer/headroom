import Foundation
import Testing
@testable import PacemarkCore

struct FeedbackEmailTests {
    private func macDiagnostics(accounts: [FeedbackDiagnostics.Account]? = nil) -> FeedbackDiagnostics {
        FeedbackDiagnostics(
            appVersion: "1.5.3 (53)",
            operatingSystem: "macOS 26.1",
            architecture: "arm64",
            cliVersions: [
                .init(providerID: .claude, version: .version("2.1.317")),
                .init(providerID: .codex, version: .version("0.155.1")),
                .init(providerID: .copilot, version: .notInstalled),
            ],
            providersOff: [.grok, .cursor],
            accounts: accounts ?? [
                .init(providerID: .claude, position: 1, status: .live),
                .init(providerID: .claude, position: 2, status: .stale("notLoggedIn")),
                .init(providerID: .codex, position: 1, status: .waiting),
            ]
        )
    }

    // MARK: Diagnostics lines

    @Test func macBlockListsVersionsProvidersOffAndAccountsByPosition() {
        #expect(macDiagnostics().lines == [
            "Pacemark 1.5.3 (53) · macOS 26.1 · arm64",
            "CLIs: Claude 2.1.317 · Codex 0.155.1 · Copilot not installed",
            "Off: Grok, Cursor",
            "Claude #1: live",
            "Claude #2: stale (notLoggedIn)",
            "Codex #1: waiting",
        ])
    }


    @Test func accountStatusUsesTheCaseNameNeverTheMessage() {
        let status = FeedbackAccountStatus(freshness: .stale(.notLoggedIn("Signed in as kyle@example.com")))
        #expect(status == .stale("notLoggedIn"))
        let text = FeedbackDiagnostics(
            appVersion: nil, operatingSystem: "macOS 26.1",
            accounts: [.init(providerID: .claude, position: 1, status: status)]
        ).lines.joined(separator: "\n")
        #expect(!text.contains("kyle@example.com"))
        #expect(!text.contains("Signed in"))
    }

    @Test func setupOutcomesReadAsPrefixedCaseNames() {
        #expect(FeedbackAccountStatus(freshness: .stale(.providerSetup(.copilotLogsUnreadable)))
            == .stale("setup.copilotLogsUnreadable"))
        #expect(FeedbackAccountStatus(freshness: .pending) == .waiting)
        #expect(FeedbackAccountStatus(freshness: .live) == .live)
    }

    // MARK: CLI versions

    @Test(arguments: [
        ("2.1.317 (Claude Code)", "2.1.317"),
        ("codex-cli 0.155.1", "0.155.1"),
        ("grok 1.0.70 (f50904eaee6c) [stable]", "1.0.70"),
        ("2026.10.18-ea085cb", "2026.10.18-ea085cb"),
        ("GitHub Copilot CLI 1.0.105.\nRun 'copilot update' to check.", "1.0.105"),
        ("v3.2.1", "3.2.1"),
    ])
    func versionShapesKeepOnlyTheVersion(output: String, expected: String) {
        #expect(FeedbackCLIVersion(versionOutput: output) == .version(expected))
    }

    @Test(arguments: [
        "/Users/example/.local/bin/claude 2.1.300",
        "C:\\Users\\kyle\\claude 2.1.300",
        "command not found",
        "",
    ])
    func outputWithAPathOrNoVersionIsUnknown(output: String) {
        #expect(FeedbackCLIVersion(versionOutput: output) == .unknown)
    }

    @Test func noOutputIsUnknown() {
        #expect(FeedbackCLIVersion(versionOutput: nil) == .unknown)
    }

}
