import Foundation
import Testing
@testable import PacemarkCore

/// U1 of the 2026-09-19 polling plan: every cadence decision is a pure function of
/// records, a log, and an explicit `now` — no store, no clock waits.
struct LaneScheduleTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let chosen: TimeInterval = 5 * 60
    private let claude = AccountKey(providerID: .claude, accountID: .primary)
    private let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
    private let lab = AccountKey(providerID: .claude, accountID: AccountID("lab"))

    private func record(
        _ key: AccountKey,
        primary: Bool = false,
        lastAttempt: TimeInterval?,
        previousAttempt: TimeInterval? = nil,
        failures: Int = 0,
        neverSignedIn: Bool = false,
        resetDeadline: TimeInterval? = nil,
        lastGapOnCadence: Bool = true
    ) -> LaneSchedule.AccountRecord {
        LaneSchedule.AccountRecord(
            key: key,
            isPrimary: primary,
            lastAttempt: lastAttempt.map { now.addingTimeInterval($0) },
            previousAttempt: previousAttempt.map { now.addingTimeInterval($0) },
            consecutiveFailures: failures,
            isNeverSignedIn: neverSignedIn,
            forcedDue: false,
            resetDeadline: resetDeadline.map { now.addingTimeInterval($0) },
            lastGapOnCadence: lastGapOnCadence
        )
    }

    private func span(_ start: TimeInterval, _ end: TimeInterval) -> LaneSchedule.ProbeSpan {
        LaneSchedule.ProbeSpan(start: now.addingTimeInterval(start), end: now.addingTimeInterval(end))
    }

    // MARK: Ordering (AE1, KTD6, KTD7)

    @Test func overduePrimaryIsServedBeforeAnOverdueExtra() {
        let records = [
            record(work, lastAttempt: -20 * 60),
            record(claude, primary: true, lastAttempt: -6 * 60),
        ]
        let next = LaneSchedule.nextAccount(records: records, priority: [], now: now, chosen: chosen, effective: chosen)
        #expect(next == claude)
    }

    @Test func priorityRequestIsServedBeforeAnOverduePrimary() {
        let records = [
            record(claude, primary: true, lastAttempt: -6 * 60),
            record(work, lastAttempt: -60),
        ]
        let next = LaneSchedule.nextAccount(records: records, priority: [work], now: now, chosen: chosen, effective: chosen)
        #expect(next == work)
    }

    @Test func mostOverdueExtraIsServedWhenNoPrimaryIsDue() {
        let records = [
            record(claude, primary: true, lastAttempt: -60),
            record(work, lastAttempt: -7 * 60),
            record(lab, lastAttempt: -9 * 60),
        ]
        let next = LaneSchedule.nextAccount(records: records, priority: [], now: now, chosen: chosen, effective: chosen)
        #expect(next == lab)
    }

    @Test func nothingDueYieldsNoAccount() {
        let records = [record(claude, primary: true, lastAttempt: -60), record(work, lastAttempt: -120)]
        #expect(LaneSchedule.nextAccount(records: records, priority: [], now: now, chosen: chosen, effective: chosen) == nil)
    }

    @Test func aFreshRecordIsDueImmediately() {
        let fresh = LaneSchedule.AccountRecord(key: claude, isPrimary: true)
        #expect(LaneSchedule.isDue(fresh, now: now, chosen: chosen, effective: chosen))
    }

    @Test func concurrentLaneReturnsEveryDueAccountWithPriorityFirst() {
        let a = AccountKey(providerID: .codex, accountID: .primary)
        let b = AccountKey(providerID: .codex, accountID: AccountID("b"))
        let c = AccountKey(providerID: .codex, accountID: AccountID("c"))
        let records = [
            record(a, primary: true, lastAttempt: -6 * 60),
            record(b, lastAttempt: -60),
            record(c, lastAttempt: -7 * 60),
        ]
        let due = LaneSchedule.dueAccounts(records: records, priority: [b], now: now, chosen: chosen, effective: chosen)
        #expect(due.first == b)
        #expect(Set(due) == [a, b, c])
    }

    // MARK: Duty cycle (AE2, AE3, KTD4)

    @Test func gateRefusesATimerProbeAfterFortyThreeSecondProbesInFourMinutes() {
        let twoMinutes: TimeInterval = 2 * 60
        // 40 probes of 3 seconds back to back, ending now: 120s busy in a 240s window.
        var log: [LaneSchedule.ProbeSpan] = []
        for i in 0..<40 {
            let end = -Double(i) * 3
            log.append(span(end - 3, end))
        }
        // Exactly at the ceiling counts as open; one more second closes it.
        #expect(LaneSchedule.mayStartTimerProbe(log: log, now: now, chosen: twoMinutes))
        log.append(span(-125, -124))
        #expect(!LaneSchedule.mayStartTimerProbe(log: log, now: now, chosen: twoMinutes))
        // Two minutes on, the oldest probes have slid out of the window and it reopens.
        #expect(!LaneSchedule.mayStartTimerProbe(log: log, now: now.addingTimeInterval(60), chosen: twoMinutes))
        #expect(LaneSchedule.mayStartTimerProbe(log: log, now: now.addingTimeInterval(125), chosen: twoMinutes))
    }

    @Test func gateAllowsEveryProbeForThreeQuickAccounts() {
        let log = [span(-9, -6), span(-6, -3), span(-3, 0)]
        #expect(LaneSchedule.mayStartTimerProbe(log: log, now: now, chosen: chosen))
    }

    @Test func budgetReopensWhenEnoughBusyTimeFallsOutOfTheWindow() {
        let twoMinutes: TimeInterval = 2 * 60
        // One 180s probe ending now inside a 240s window: 60s over the 120s budget. The
        // window's left edge must pass 120s into the probe before only 120s remain inside.
        let log = [span(-180, 0)]
        let reopens = LaneSchedule.budgetReopens(log: log, now: now, chosen: twoMinutes)
        #expect(reopens == now.addingTimeInterval(120))
        #expect(LaneSchedule.budgetReopens(log: [span(-10, 0)], now: now, chosen: twoMinutes) == nil)
    }

    @Test func aLaneOfTimeoutsIsHeldAndRecoversAfterOneQuickPass() {
        let twoMinutes: TimeInterval = 2 * 60
        // Twenty 80-second timeouts: the gate closes and stays closed.
        var log: [LaneSchedule.ProbeSpan] = []
        for i in 0..<20 {
            let end = -Double(i) * 80
            log.append(span(end - 80, end))
        }
        #expect(!LaneSchedule.mayStartTimerProbe(log: log, now: now, chosen: twoMinutes))
        // The displayed interval is measured from attempt gaps, so one normal pass
        // (gaps back at the chosen interval) restores it.
        let stretched = LaneSchedule.effectiveInterval(chosen: twoMinutes, attemptGaps: [53 * 60])
        #expect(stretched == 53 * 60)
        let recovered = LaneSchedule.effectiveInterval(chosen: twoMinutes, attemptGaps: [twoMinutes, twoMinutes])
        #expect(recovered == twoMinutes)
    }

    @Test func effectiveIntervalIsTheLongestGapRoundedUpToWholeMinutes() {
        #expect(LaneSchedule.effectiveInterval(chosen: 2 * 60, attemptGaps: [4 * 60]) == 4 * 60)
        #expect(LaneSchedule.effectiveInterval(chosen: 5 * 60, attemptGaps: [3, 3, 3]) == 5 * 60)
        #expect(LaneSchedule.effectiveInterval(chosen: 5 * 60, attemptGaps: [7.2 * 60]) == 8 * 60)
        #expect(LaneSchedule.effectiveInterval(chosen: 5 * 60, attemptGaps: []) == 5 * 60)
    }

    @Test func wakeJitterAndOneProbeOfWaitNeverReadAsAStretchedLane() {
        // R10 / R12: a timer probe starts a few milliseconds after its due time, and a
        // sibling may wait one probe behind an in-flight one; neither breaks the promise.
        let chosen: TimeInterval = 5 * 60
        #expect(LaneSchedule.effectiveInterval(chosen: chosen, attemptGaps: [chosen + 0.004]) == chosen)
        #expect(LaneSchedule.cadenceTolerance(chosen: 60) == 30)
        #expect(LaneSchedule.cadenceTolerance(chosen: 120) == 60)
        #expect(LaneSchedule.effectiveInterval(chosen: chosen, attemptGaps: [chosen + LaneSchedule.cadenceTolerance(chosen: chosen)]) == chosen)
        #expect(LaneSchedule.effectiveInterval(chosen: chosen, attemptGaps: [chosen + LaneSchedule.cadenceTolerance(chosen: chosen) + 1]) == 7 * 60)
    }

    @Test func onlyOnCadenceAccountsContributeGaps() {
        let backingOff = record(work, lastAttempt: 0, previousAttempt: -40 * 60, failures: 2)
        let exempt = record(lab, lastAttempt: 0, previousAttempt: -20 * 60, neverSignedIn: true)
        let healthy = record(claude, primary: true, lastAttempt: 0, previousAttempt: -5 * 60)
        // A first success after backoff: healthy now, but its gap was scheduled stretched.
        let recovered = record(claude, primary: true, lastAttempt: 0, previousAttempt: -20 * 60, lastGapOnCadence: false)
        #expect(!backingOff.isOnCadence)
        #expect(!exempt.isOnCadence)
        #expect(healthy.isOnCadence)
        #expect(abs((healthy.attemptGap ?? 0) - chosen) < 0.001)
        #expect(!recovered.isOnCadence)
        #expect(recovered.scheduledOnCadence)
    }

    // MARK: Backoff (AE5, KTD5)

    @Test func transientFailuresDoubleFromTheChosenIntervalAndCap() {
        let one = record(work, lastAttempt: 0, failures: 1)
        let two = record(work, lastAttempt: 0, failures: 2)
        let three = record(work, lastAttempt: 0, failures: 3)
        #expect(LaneSchedule.nextDue(for: one, chosen: chosen, effective: chosen) == now.addingTimeInterval(10 * 60))
        #expect(LaneSchedule.nextDue(for: two, chosen: chosen, effective: chosen) == now.addingTimeInterval(20 * 60))
        #expect(LaneSchedule.nextDue(for: three, chosen: chosen, effective: chosen) == now.addingTimeInterval(30 * 60))
    }

    @Test func aFailingAccountIsNeverDueSoonerThanAHealthyOneInAStretchedLane() {
        // KTD5 / AE5: at a 53 minute effective interval one failure is due 53 minutes after
        // the attempt, never 10 and never 30 — otherwise the failing account would take the
        // lane's budget from the healthy ones it is already delaying.
        let one = record(work, lastAttempt: 0, failures: 1)
        let stretched: TimeInterval = 53 * 60
        let healthy = record(claude, primary: true, lastAttempt: 0)
        #expect(LaneSchedule.nextDue(for: one, chosen: chosen, effective: stretched) == now.addingTimeInterval(stretched))
        #expect(LaneSchedule.nextDue(for: one, chosen: chosen, effective: stretched)
            >= LaneSchedule.nextDue(for: healthy, chosen: chosen, effective: stretched))
        let four = record(work, lastAttempt: 0, failures: 4)
        #expect(LaneSchedule.nextDue(for: four, chosen: chosen, effective: stretched) == now.addingTimeInterval(stretched))
        // In a healthy lane the doubling stands: 10 minutes, then the 30 minute cap.
        #expect(LaneSchedule.nextDue(for: one, chosen: chosen, effective: chosen) == now.addingTimeInterval(10 * 60))
        #expect(LaneSchedule.nextDue(for: four, chosen: chosen, effective: chosen) == now.addingTimeInterval(30 * 60))
    }

    @Test func aSuccessResetsBackoffToOneInterval() {
        let recovered = record(work, lastAttempt: 0, failures: 0)
        #expect(LaneSchedule.nextDue(for: recovered, chosen: chosen, effective: chosen) == now.addingTimeInterval(chosen))
        #expect(LaneSchedule.consecutiveFailures(after: .success, previous: 3) == 0)
        #expect(LaneSchedule.consecutiveFailures(after: .transientFailure, previous: 3) == 4)
    }

    @Test func permanentSetupStatesDoNotBackOff() {
        let loginRequired = UsageProviderFetchResult(
            snapshot: .stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))
        )
        #expect(LaneSchedule.outcome(of: loginRequired) == .permanentState)
        #expect(LaneSchedule.consecutiveFailures(after: .permanentState, previous: 3) == 0)
        let transient = UsageProviderFetchResult(snapshot: .stale(for: .claude, reason: .transient("retry")))
        #expect(LaneSchedule.outcome(of: transient) == .transientFailure)
        let capabilityMiss = UsageProviderFetchResult(
            snapshot: .pending(for: .claude),
            capability: .confirmedAbsent
        )
        #expect(LaneSchedule.outcome(of: capabilityMiss) == .transientFailure)
    }

    @Test func aPermanentlyStalePrimaryStaysOnCadence() {
        // The count stays at zero for a permanent state, so the primary is due one interval on.
        let primary = record(claude, primary: true, lastAttempt: 0, failures: 0)
        #expect(LaneSchedule.nextDue(for: primary, chosen: chosen, effective: chosen) == now.addingTimeInterval(chosen))
    }

    @Test func neverSignedInExtraWaitsFourIntervalsAndIsNeverDoubled() {
        let extra = record(work, lastAttempt: 0, neverSignedIn: true)
        #expect(LaneSchedule.nextDue(for: extra, chosen: chosen, effective: chosen) == now.addingTimeInterval(4 * chosen))
        let primary = record(claude, primary: true, lastAttempt: 0, neverSignedIn: true)
        #expect(LaneSchedule.nextDue(for: primary, chosen: chosen, effective: chosen) == now.addingTimeInterval(chosen))
        #expect(LaneSchedule.isNeverSignedIn(.stale(.notLoggedIn("sign in"))))
        #expect(LaneSchedule.isNeverSignedIn(.stale(.providerSetup(.claudeLoginRequired))))
        #expect(!LaneSchedule.isNeverSignedIn(.stale(.needsReauth("again"))))
        #expect(!LaneSchedule.isNeverSignedIn(.live))
    }

    // MARK: Wake timer (KTD6)

    @Test func wakeDelayClampsBetweenOneSecondAndTheChosenInterval() {
        #expect(LaneSchedule.wakeDelay(candidates: [now.addingTimeInterval(-30)], now: now, chosen: chosen) == 1)
        #expect(LaneSchedule.wakeDelay(candidates: [now.addingTimeInterval(90)], now: now, chosen: chosen) == 90)
        #expect(LaneSchedule.wakeDelay(candidates: [now.addingTimeInterval(3_600)], now: now, chosen: chosen) == chosen)
        #expect(LaneSchedule.wakeDelay(candidates: [], now: now, chosen: chosen) == chosen)
    }

    @Test func resetDeadlineInsideTheIntervalPhasesTheAccountToJustAfterIt() {
        let phased = record(claude, primary: true, lastAttempt: 0, resetDeadline: 160)
        #expect(LaneSchedule.nextDue(for: phased, chosen: chosen, effective: chosen)
            == now.addingTimeInterval(160 + PollPhasing.postResetGrace))
        // A deadline sooner than the floor still respects the floor between attempts.
        let early = record(claude, primary: true, lastAttempt: 0, resetDeadline: 30)
        #expect(LaneSchedule.nextDue(for: early, chosen: chosen, effective: chosen) == now.addingTimeInterval(60))
        // Beyond the interval the ordinary due time stands.
        let far = record(claude, primary: true, lastAttempt: 0, resetDeadline: 4 * 3_600)
        #expect(LaneSchedule.nextDue(for: far, chosen: chosen, effective: chosen) == now.addingTimeInterval(chosen))
        // Already behind the last attempt: the attempt we made answered it.
        let behind = record(claude, primary: true, lastAttempt: 0, resetDeadline: -30)
        #expect(LaneSchedule.nextDue(for: behind, chosen: chosen, effective: chosen) == now.addingTimeInterval(chosen))
        // Just before the ordinary due time: overshooting by the grace is the point, since a
        // probe 15 s before the reset would re-read the pre-reset number.
        let late = record(claude, primary: true, lastAttempt: 0, resetDeadline: chosen - 15)
        #expect(LaneSchedule.nextDue(for: late, chosen: chosen, effective: chosen)
            == now.addingTimeInterval(chosen - 15 + PollPhasing.postResetGrace))
    }

    @Test func chosenIntervalHonorsTheOneMinuteFloor() {
        #expect(LaneSchedule.chosenInterval(minutes: 1) == 60)
        #expect(LaneSchedule.chosenInterval(minutes: 5) == 5 * 60)
    }
}
