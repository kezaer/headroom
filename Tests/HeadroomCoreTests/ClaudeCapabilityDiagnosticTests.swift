import Foundation
import Testing
@testable import HeadroomCore

struct ClaudeCapabilityDiagnosticTests {
    @Test func reportUsesOnlyAllowlistedCategoriesAndEventAge() {
        let now = Date(timeIntervalSince1970: 10_000)
        let events = CLIExecutableDiagnosticCategory.allCases.enumerated().map { offset, category in
            CLIExecutableDiagnosticEvent(
                category: category,
                observedAt: now.addingTimeInterval(TimeInterval(-offset))
            )
        }

        for account in ClaudeCapabilityDiagnosticAccount.allCases {
            for band in ClaudeCLIVersionBand.allCases {
                for outcome in ClaudeCapabilityDiagnosticOutcome.allCases {
                    let output = ClaudeCapabilityDiagnostic.lines(
                        account: account,
                        versionBand: band,
                        outcome: outcome,
                        events: events,
                        now: now
                    ).joined(separator: "\n")

                    #expect(output.contains("account-category=\(account.rawValue)"))
                    #expect(output.contains("cli-version-band=\(band.rawValue)"))
                    #expect(output.contains("capability-outcome=\(outcome.rawValue)"))
                    #expect(output.contains("age-seconds="))
                }
            }
        }
    }

    @Test func reportCannotContainPathIdentityProviderOutputCredentialsOrRawErrors() {
        let output = ClaudeCapabilityDiagnostic.lines(
            account: .extra,
            versionBand: .printSupported,
            outcome: .trustRequired,
            events: [
                CLIExecutableDiagnosticEvent(
                    category: .hintInvalidated,
                    observedAt: Date(timeIntervalSince1970: 1)
                ),
            ],
            now: Date(timeIntervalSince1970: 2)
        ).joined(separator: "\n")

        for forbidden in [
            "/Users/example/.local/bin/claude",
            "/Users/example/.claude-extra",
            "example@example.com",
            "Personal Account",
            "sk-ant-secret",
            "oauthAccessToken",
            "Current week (all models)",
            "permission denied at /private/path",
        ] {
            #expect(!output.contains(forbidden))
        }
    }

    @Test func CLIOutputsMapToSafeVersionBands() {
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("2.1.217 (Claude Code)") == .printSupported)
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("2.1.216 (Claude Code)") == .ptyFallback)
        #expect(ClaudeUsageCLIProbe.classifyVersionBand("unexpected output") == .unknown)
    }
}
