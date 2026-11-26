import Foundation
import Testing
@testable import PacemarkCore

struct MenuBarPaceTests {
    private let now = Date(timeIntervalSinceReferenceDate: 0)
    private let duration: TimeInterval = 18_000

    @Test func projectedBurnRateDefinesPace() {
        let reset = now.addingTimeInterval(duration * 0.75)
        let cases: [(Double, MenuBarPace.Tier)] = [
            (0.25, .onPace), (0.30, .ahead), (0.325, .ahead),
            (0.33, .wayAhead), (0.50, .wayAhead)
        ]
        for (used, tier) in cases {
            let pace = MenuBarPace(usedFraction: used, duration: duration, reset: reset, now: now)
            #expect(pace?.tier == tier)
            #expect(pace?.expectedRemaining == 0.75)
        }

        let resetAtFiftyFivePercentRemaining = now.addingTimeInterval(9_900)
        let onTrack = MenuBarPace(usedFraction: 0.45, duration: duration,
                                reset: resetAtFiftyFivePercentRemaining, now: now)
        #expect(onTrack?.tier == .onPace)
    }

    @Test func earlyWindowUsesDeltaBeforeTenPercentElapsed() {
        let earlyReset = now.addingTimeInterval(duration * 0.95)
        let cases: [(Double, MenuBarPace.Tier)] = [
            (0.10, .onPace), (0.21, .ahead), (0.41, .wayAhead)
        ]
        for (used, tier) in cases {
            let pace = MenuBarPace(usedFraction: used, duration: duration, reset: earlyReset, now: now)
            #expect(pace?.tier == tier)
        }
        let tenthReset = now.addingTimeInterval(duration * 0.90)
        #expect(MenuBarPace(usedFraction: 0.15, duration: duration, reset: tenthReset, now: now)?.tier == .wayAhead)
    }

    @Test func fillAndTickShareTheOpenClockwiseArc() throws {
        let layout = MenuBarRingLayout(requestedDiameter: 24, heightLimit: 39, ringWidth: 1,
                                       showsTick: true, labelWidth: 0, labelHeight: 0, logoScale: 0.70)
        let reset = now.addingTimeInterval(duration * 0.75)
        let pace = try #require(MenuBarPace(usedFraction: 0.25, duration: duration, reset: reset, now: now))
        let expected = try #require(pace.expectedRemaining)
        #expect(abs(layout.angle(at: 0) + 2 * .pi / 3) < 0.000_001)
        #expect(layout.angle(at: 0.5) == 0)
        #expect(abs(layout.angle(at: 1) - 2 * .pi / 3) < 0.000_001)
        #expect(abs(layout.angle(at: expected) - .pi / 3) < 0.000_001)
        #expect(layout.angle(at: -1) == layout.angle(at: 0))
        #expect(layout.angle(at: 2) == layout.angle(at: 1))
    }

    @Test func logoInkBoxKeepsClearOfTheArcAtEveryMenuBarScale() {
        let radii = [4.0, 5.5, 7.25, 9.25]
        let logoScales = [0.60, 0.70, 0.75, 0.80, 0.85]
        let providers: [ProviderID] = [.claude, .codex, .antigravity, .grok, .cursor, .copilot, .opencode]
        for provider in providers {
            for radius in radii {
                for scale in logoScales {
                    for offset in [0, radius / 2] {
                        let size = MenuBarGlyph.ringLogoSize(
                            of: .providerMark(provider), preferredSize: 2 * radius * scale,
                            innerRadius: radius, verticalOffset: offset)
                        let corner = hypot(size.width / 2, size.height / 2 + offset)
                        #expect(corner <= radius - 1.5 + 0.000_001)
                        #expect(size.width > 0)
                    }
                }
            }
        }

        let claude = MenuBarGlyph.ringLogoSize(of: .providerMark(.claude), preferredSize: 8, innerRadius: 9)
        let antigravity = MenuBarGlyph.ringLogoSize(of: .providerMark(.antigravity), preferredSize: 8, innerRadius: 9)
        #expect(claude.width == 8)
        #expect(abs(antigravity.width - 8 * 0.78) < 0.000_001)
        #expect(abs(antigravity.width / antigravity.height - PacemarkBrandMark.inkAspect(for: ProviderID.antigravity.raw)) < 0.000_001)

        let clamped = MenuBarGlyph.ringLogoSize(of: .providerMark(.claude), preferredSize: 20, innerRadius: 8)
        #expect(abs(hypot(clamped.width / 2, clamped.height / 2) - 6.5) < 0.000_001)
    }

    @Test func missingResetEvidenceLeavesSeverityFallback() {
        for unknownDuration in [nil, 0, .infinity] as [TimeInterval?] {
            let pace = MenuBarPace(usedFraction: 0.75, duration: unknownDuration, reset: now, now: now)
            #expect(pace?.tier == nil)
            #expect(pace?.expectedRemaining == nil)
            #expect(pace?.remaining == 0.25)
        }
        let missingReset = MenuBarPace(usedFraction: 0.75, duration: duration, reset: nil, now: now)
        #expect(missingReset?.tier == nil)
    }

    @Test func lowBalanceJustBeforeResetCanBeOnPace() {
        let window = UsageWindow(kind: .weekly, utilization: 95, resetsAt: now.addingTimeInterval(3600))
        #expect(MenuBarPace(window: window, now: now)?.tier == .onPace)
    }

    @Test func exhaustedBalanceIsAlwaysRed() {
        #expect(MenuBarPace(usedFraction: 1, duration: duration, reset: now, now: now)?.tier == .wayAhead)
        #expect(MenuBarPace(usedFraction: 1, duration: nil, reset: nil, now: now)?.tier == .wayAhead)
    }

    @Test func elapsedIsClampedAtBothEnds() {
        for (offset, expected) in [(-1.0, 0.0), (2 * duration, 1.0)] {
            let pace = MenuBarPace(usedFraction: 0.3, duration: duration,
                                   reset: now.addingTimeInterval(offset), now: now)
            #expect(pace?.expectedRemaining == expected)
        }
    }

    @Test func antigravityPoolsHavePaceForBothPeriods() {
        for (label, duration) in [
            ("Gemini 5h", 18_000.0), ("Other 5h", 18_000.0),
            ("Gemini weekly", 604_800.0), ("Other weekly", 604_800.0)
        ] {
            let window = UsageWindow(kind: .other(label), utilization: 60, resetsAt: now.addingTimeInterval(duration / 2))
            let pace = MenuBarPace(window: window, now: now)
            #expect(pace?.expectedRemaining == 0.5)
            #expect(pace?.tier == .ahead)
            #expect(pace?.expectedRemaining == 0.5)
        }
    }

    @Test(arguments: ["Current week (Fable)", "Weekly (Fable)", "Weekly (Sonnet)"])
    func claudeModelRowsUseTheirWeeklyDuration(label: String) throws {
        let reading = try #require(ClaudeUsageParser.parse("\(label): 60% used · resets Dec 2 at 10am").first)
        let reset = now.addingTimeInterval(302_400)
        for kind in [reading.kind, .other(label)] {
            #expect(MenuBarPace.duration(for: kind) == 604_800)
            let window = UsageWindow(kind: kind, utilization: reading.percentUsed, resetsAt: reset)
            let pace = try #require(MenuBarPace(window: window, now: now))
            #expect(pace.expectedRemaining == 0.5)
            #expect(pace.tier == .ahead)
            #expect(pace.expectedRemaining == 0.5)
        }
    }

    @Test func codexModelRowsUseTheirDeclaredPeriods() {
        let buckets = [CodexLimitBucket(
            label: "Codex Spark",
            primary: CodexLimitWindow(usedPercent: 60, windowSeconds: 604_800, resetsAt: now.addingTimeInterval(302_400)),
            secondary: CodexLimitWindow(usedPercent: 80, windowSeconds: 18_000, resetsAt: now.addingTimeInterval(9_000))
        )]
        let windows = CodexWindowMapping.windows(buckets)
        #expect(windows.map(\.kind) == [.other("Codex Spark Weekly"), .other("Codex Spark 5h")])
        #expect(windows.map { MenuBarPace(window: $0, now: now)?.expectedRemaining } == [0.5, 0.5])
        #expect(windows.map { MenuBarPace(window: $0, now: now)?.tier } == [.ahead, .wayAhead])
    }

    @Test func usesTheShownWindowKindAndDeclaredBillingDuration() {
        let kinds: [(WindowKind, TimeInterval)] = [
            (.fiveHour, 18_000), (.weekly, 604_800), (.billingPeriod(label: "Billing", duration: 864_000), 864_000)
        ]
        for (kind, duration) in kinds {
            let window = UsageWindow(kind: kind, utilization: 65, resetsAt: now.addingTimeInterval(duration / 2))
            let pace = MenuBarPace(window: window, now: now)
            #expect(pace?.expectedRemaining == 0.5)
            #expect(pace?.tier == .ahead)
        }
        let unknown = UsageWindow(kind: .other("Pool"), utilization: 65, resetsAt: now)
        #expect(MenuBarPace(window: unknown, now: now)?.tier == nil)
        #expect(MenuBarPace.duration(for: .other("Codex Spark 6h")) == nil)
        #expect(MenuBarPace.duration(for: .other("10d")) == nil)
    }
}
