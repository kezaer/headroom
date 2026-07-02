import Testing
import Foundation
@testable import UsageBarCore

/// U2 test scenarios: percent-remaining math and reset-countdown formatting (the
/// pure core-correctness surface), plus the `.pending` first-run distinction.
struct UsageMathTests {
    private func approx(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    @Test func percentRemainingCoversRange() {
        #expect(approx(UsageWindow(kind: .fiveHour, utilization: 0, resetsAt: .now).percentRemaining, 100))
        #expect(approx(UsageWindow(kind: .fiveHour, utilization: 100, resetsAt: .now).percentRemaining, 0))
        #expect(approx(UsageWindow(kind: .fiveHour, utilization: 73.4, resetsAt: .now).percentRemaining, 26.6))
    }

    @Test func percentRemainingClampsOverLimit() {
        // utilization > 100 (over-limit) clamps to 0, never negative.
        #expect(UsageWindow(kind: .weekly, utilization: 130, resetsAt: .now).percentRemaining == 0)
    }

    @Test func countdownFormatsAcrossRanges() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Countdown.string(to: now.addingTimeInterval(4 * 3600 + 59 * 60), now: now) == "4h 59m")
        #expect(Countdown.string(to: now.addingTimeInterval(90), now: now) == "1m")
        #expect(Countdown.string(to: now, now: now) == "resets now")
    }

    @Test func countdownNeverGoesNegative() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // A past reset renders "resets now", not a negative value.
        #expect(Countdown.string(to: now.addingTimeInterval(-500), now: now) == "resets now")
    }

    @Test func otherWindowKindRoundTripsLabel() {
        let w = UsageWindow(kind: .other("codex-spark"), utilization: 10, resetsAt: .now)
        #expect(w.kind == .other("codex-spark"))
        #expect(w.kind.shortLabel == "codex-spark")
    }

    @Test func pendingSnapshotHasNoCaptureTime() {
        let snap = UsageSnapshot.pending(for: .claude)
        // `.pending` is distinguishable from `.stale` and carries no timestamp,
        // so the UI shows a real first-run state, not "updated 0 min ago".
        #expect(snap.capturedAt == nil)
        #expect(snap.freshness == .pending)
        #expect(Countdown.updatedLabel(capturedAt: snap.capturedAt, now: .now) == nil)
    }

    @Test func failureReasonPermanenceIsTyped() {
        #expect(FailureReason.scopeDenied("x").isPermanent)
        #expect(FailureReason.needsReauth("x").isPermanent)
        #expect(!FailureReason.transient("x").isPermanent)
    }

    @Test func updatedLabelFormatsRelativeTimes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Countdown.updatedLabel(capturedAt: nil, now: now) == nil)
        #expect(Countdown.updatedLabel(capturedAt: now, now: now) == "just now")
        #expect(Countdown.updatedLabel(capturedAt: now.addingTimeInterval(-60), now: now) == "1 min ago")
        #expect(Countdown.updatedLabel(capturedAt: now.addingTimeInterval(-300), now: now) == "5 min ago")
        #expect(Countdown.updatedLabel(capturedAt: now.addingTimeInterval(-3600), now: now) == "1 hr ago")
    }
}
