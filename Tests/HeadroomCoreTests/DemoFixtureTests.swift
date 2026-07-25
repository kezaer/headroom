import Testing
import Foundation
@testable import HeadroomCore

struct DemoFixtureTests {
    @Test func claudeDemoSnapshotIncludesFableAllotment() {
        #expect(DemoFixture.claudeSnapshot.windows.contains {
            $0.kind == .other("Weekly (Fable)")
        })
    }

    private func remaining(_ snapshot: UsageSnapshot, _ kind: WindowKind) -> Int? {
        snapshot.windows.first { $0.kind == kind }
            .map { UsagePercentageMode.remaining.roundedPercentage(for: $0) }
    }

    /// The locked hero scenario (KTD5): Claude 5-hour 72% / Weekly 38% / Fable 54% left.
    @Test func claudeDemoMatchesHeroScenario() {
        let claude = DemoFixture.claudeSnapshot
        #expect(remaining(claude, .fiveHour) == 72)
        #expect(remaining(claude, .weekly) == 38)
        #expect(remaining(claude, .other("Weekly (Fable)")) == 54)
    }

    /// Codex Jul 2026 reality: weekly only (no 5-hour gate), 36% used = 64% left.
    @Test func codexDemoMatchesCurrentReality() {
        let codex = DemoFixture.codexSnapshot
        #expect(remaining(codex, .weekly) == 64)
        // Codex has no 5-hour window in current reality
        #expect(remaining(codex, .fiveHour) == nil)
    }

    /// The popover renders reset text from `resetsAt` via `Countdown.resetText`, NOT
    /// `resetLabel` (KTD5). Assert the computed relative durations match the artboard.
    /// The fixture's `soon(...)` buffer keeps truncation on the intended value.
    @Test func demoResetTextMatchesArtboard() {
        let now = Date()
        func resetText(_ snapshot: UsageSnapshot, _ kind: WindowKind) -> String? {
            snapshot.windows.first { $0.kind == kind }
                .map { Countdown.resetText(resetsAt: $0.resetsAt, now: now) }
        }
        #expect(resetText(DemoFixture.claudeSnapshot, .weekly) == "Resets in 4d")
        #expect(resetText(DemoFixture.claudeSnapshot, .fiveHour) == "Resets in 3h 15m")
        #expect(resetText(DemoFixture.claudeSnapshot, .other("Weekly (Fable)")) == "Resets in 4d")
        #expect(resetText(DemoFixture.codexSnapshot, .weekly) == "Resets in 6d 4h")
    }

    // MARK: - `--demo` scenario parsing (demo mode, Jul 2026)

    @Test func bareDemoRequestsSingleAccountFixtures() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo"]) == .singleAccount)
        // A following flag is not a scenario token — still a bare demo.
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "--verbose"]) == .singleAccount)
    }

    @Test func absentDemoFlagIsNotRequested() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom"]) == .notRequested)
    }

    @Test func knownScenarioTokensResolve() {
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            #expect(
                DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", scenario.rawValue])
                    == .multiAccount(scenario)
            )
        }
    }

    @Test func unknownScenarioTokenIsInvalid() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "multi-9"]) == .invalid("multi-9"))
    }

    @Test func multiFixtureAccountCountsMatchScenario() {
        #expect(DemoFixture.multiFixture(for: .multiTwo).accounts.count == 3)   // 2 Claude + 1 Codex
        #expect(DemoFixture.multiFixture(for: .multiThree).accounts.count == 5)
        #expect(DemoFixture.multiFixture(for: .multiFive).accounts.count == 8)  // 5 Claude + 3 Codex (past the cap for scroll)
        #expect(DemoFixture.multiFixture(for: .multiMixed).accounts.count == 4)
        // Provider instances are 1:1 with accounts.
        for scenario in DemoFixture.MultiAccountScenario.allCases {
            let fixture = DemoFixture.multiFixture(for: scenario)
            #expect(fixture.providers.count == fixture.accounts.count)
        }
    }
}
