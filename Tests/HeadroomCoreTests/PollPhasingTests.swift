import Foundation
import Testing
@testable import HeadroomCore

/// R2M2 / R2M3: when the one scheduled poll happens, and when opening the popover is
/// allowed to move it. Nothing here raises the cadence — every case is the same poll at a
/// different moment, bounded by the enforced interval floor.
struct PollPhasingTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let interval: TimeInterval = 5 * 60

    @Test func noDeadlineSleepsAFullInterval() {
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: nil, now: now
        ) == interval)
    }

    @Test func deadlineInsideTheIntervalMovesThePollToJustAfterIt() {
        let deadline = now.addingTimeInterval(3 * 60)
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: deadline, now: now
        ) == 3 * 60 + PollPhasing.postResetGrace)
    }

    @Test func deadlineOutsideTheIntervalLeavesTheFixedTickAlone() {
        // Later than this interval: a subsequent cycle phases itself onto it.
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: now.addingTimeInterval(interval + 1), now: now
        ) == interval)
        // Already behind us: the poll we're waiting on answers it.
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: now.addingTimeInterval(-30), now: now
        ) == interval)
    }

    @Test func aDeadlineNearTheEndOfTheIntervalIsStillWorthWaitingFor() {
        // Overshooting the fixed tick by the grace period is the point: polling 15s *before*
        // the reset would just re-read the pre-reset number.
        let deadline = now.addingTimeInterval(interval - 15)
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: deadline, now: now
        ) == interval - 15 + PollPhasing.postResetGrace)
    }

    @Test func anImminentDeadlineNeverPollsBelowTheEnforcedFloor() {
        let floor = Double(Preferences.minimumIntervalMinutes) * 60
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: now.addingTimeInterval(10), now: now
        ) == floor)
        // And the interval itself still clamps to the floor when a preference undercuts it.
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 1, nextDeadline: nil, now: now
        ) == floor)
    }

    @Test func popoverOpenGateComparesTheOldestLiveCaptureToTheInterval() {
        // Nothing live: no capture to freshen, and probing on every open would burn a CLI
        // session per open.
        #expect(UsageStore.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: nil, now: now, intervalMinutes: 5
        ) == false)
        #expect(UsageStore.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: now.addingTimeInterval(-interval + 1), now: now, intervalMinutes: 5
        ) == false)
        #expect(UsageStore.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: now.addingTimeInterval(-interval), now: now, intervalMinutes: 5
        ))
        // The floor applies here too, so a sub-minimum preference can't shorten the gate.
        #expect(UsageStore.shouldRefreshOnPopoverOpen(
            oldestLiveCapture: now.addingTimeInterval(-90), now: now, intervalMinutes: 1
        ) == false)
    }
}

@MainActor
struct PollPhasingStoreTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func popoverOpenSkipsTheRefreshWhileTheCaptureIsStillFresh() async {
        let clock = MutableDateSource(start)
        let provider = ClockedCountingProvider(clock: clock, deadline: start.addingTimeInterval(3_600))
        let store = UsageStore(providers: [provider], preferences: isolatedPreferences(), now: clock.now)

        await store.start()
        #expect(provider.fetchCount == 1)
        let startsAfterLaunch = store.engine?.startCount ?? 0

        clock.set(start.addingTimeInterval(60))
        store.refreshOnPopoverOpen()
        await settle()

        #expect(provider.fetchCount == 1)
        #expect(store.engine?.startCount == startsAfterLaunch)
    }

    @Test func popoverOpenRefreshesAndRephasesOnceTheCaptureAgedPastTheInterval() async {
        let clock = MutableDateSource(start)
        let provider = ClockedCountingProvider(clock: clock, deadline: start.addingTimeInterval(3_600))
        let preferences = isolatedPreferences()
        let store = UsageStore(providers: [provider], preferences: preferences, now: clock.now)

        await store.start()
        let startsAfterLaunch = store.engine?.startCount ?? 0

        clock.set(start.addingTimeInterval(Double(preferences.pollIntervalMinutes) * 60))
        store.refreshOnPopoverOpen()
        await settle { provider.fetchCount == 2 }
        // The re-phase happens after the poll lands, so let that continuation run too.
        await settle()

        #expect(provider.fetchCount == 2)
        // The cadence is re-phased behind the off-cadence poll, so the timer does not fire on
        // top of data it just got — at most one extra poll per interval.
        #expect(store.engine?.startCount == startsAfterLaunch + 1)

        // Immediately reopening costs nothing: the capture is fresh again.
        store.refreshOnPopoverOpen()
        await settle()
        #expect(provider.fetchCount == 2)
    }

    @Test func theEngineWakesJustAfterTheNextTrackedResetDeadline() async {
        let clock = MutableDateSource(start)
        let deadline = start.addingTimeInterval(2 * 60 + 40)
        let provider = ClockedCountingProvider(clock: clock, deadline: deadline)
        let store = UsageStore(providers: [provider], preferences: isolatedPreferences(), now: clock.now)

        await store.start()

        #expect(store.nextTrackedResetDeadline() == deadline)
        #expect(store.engine?.secondsUntilNextPoll == 2 * 60 + 40 + PollPhasing.postResetGrace)
    }

    @Test func unavailableAndElapsedWindowsDoNotPhaseThePoll() async {
        let clock = MutableDateSource(start)
        let observedAt = start.addingTimeInterval(-3_600)
        let provider = StubProvider(
            id: .claude,
            displayName: "Claude",
            snapshot: UsageSnapshot(
                providerID: .claude,
                windows: [
                    // Retired row: its retained deadline is no longer evidence of anything.
                    UsageWindow(
                        kind: .other("Weekly (Fable)"),
                        utilization: 40,
                        resetsAt: start.addingTimeInterval(60),
                        freshness: .unavailable(since: observedAt)
                    ),
                    // Already elapsed: the poll we're waiting on answers it.
                    UsageWindow(kind: .fiveHour, utilization: 20, resetsAt: start.addingTimeInterval(-30)),
                    UsageWindow(kind: .weekly, utilization: 30, resetsAt: start.addingTimeInterval(4 * 3_600)),
                ],
                planLabel: nil,
                capturedAt: start,
                freshness: .live
            )
        )
        let store = UsageStore(providers: [provider], preferences: isolatedPreferences(), now: clock.now)

        await store.refreshAll()

        #expect(store.nextTrackedResetDeadline() == start.addingTimeInterval(4 * 3_600))
        // Four hours out is past this interval, so the fixed tick stands.
        #expect(PollPhasing.secondsUntilNextPoll(
            intervalMinutes: 5, nextDeadline: store.nextTrackedResetDeadline(), now: start
        ) == 5 * 60)
    }

    @Test func theEngineWakesForTheEarliestDueAccountInAnIdleLane() async {
        // KTD6 (2026-09-19 polling plan): two accounts on one lane, one refreshed later by a
        // user action, so their due times differ; the sleep targets the earlier one.
        let clock = MutableDateSource(start)
        let extraID = AccountID("work")
        let primary = ClockedCountingProvider(clock: clock, deadline: start.addingTimeInterval(3_600))
        let extra = ClockedCountingProvider(clock: clock, deadline: start.addingTimeInterval(3_600), accountID: extraID)
        let store = UsageStore(
            providers: [primary, extra],
            preferences: isolatedPreferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")],
            now: clock.now
        )
        await store.start()

        clock.set(start.addingTimeInterval(150))
        await store.refreshAccount(AccountKey(providerID: .claude, accountID: extraID))
        clock.set(start.addingTimeInterval(210))

        // Primary due at +300 (90s away); the extra at +450 after its own refresh.
        #expect(store.engine?.secondsUntilNextPoll == 90)
    }

    @Test func overdueAccountsInADrainingLaneDoNotShortenTheWakeAndThePassEndRephasesOnce() async {
        let clock = MutableDateSource(start)
        let primary = SuspendableClockedProvider(clock: clock)
        let store = UsageStore(providers: [primary], preferences: isolatedPreferences(), now: clock.now)
        await store.start()
        let startsAfterLaunch = store.engine?.startCount ?? 0

        clock.set(start.addingTimeInterval(5 * 60 + 1))
        primary.suspendNextFetch()
        store.dispatchDueNow()
        await primary.waitUntilStarted()

        // The only lane is draining, so nothing shortens the sleep to one second.
        #expect(store.engine?.secondsUntilNextPoll == 5 * 60)

        primary.release()
        await settle { (store.engine?.startCount ?? 0) == startsAfterLaunch + 1 }
        #expect(store.engine?.startCount == startsAfterLaunch + 1)
    }

    private func isolatedPreferences() -> Preferences {
        let suite = "headroom.pollphasing.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
    }

    /// `refreshOnPopoverOpen()` spawns a detached refresh, so tests yield until it lands
    /// (or until it's clear it never will).
    private func settle(until condition: () -> Bool = { false }) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }
}

/// Counting provider whose capture time comes from the test's clock, so capture *age* —
/// the thing R2M2 gates on — is deterministic.
private final class ClockedCountingProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .claude
    let accountID: AccountID
    let displayName = "Claude"
    let pollingLane: ProviderPollingLane = .serial("claude-cli")
    private let clock: MutableDateSource
    private let deadline: Date
    private let lock = NSLock()
    private var _count = 0

    var fetchCount: Int { lock.withLock { _count } }

    init(clock: MutableDateSource, deadline: Date, accountID: AccountID = .primary) {
        self.clock = clock
        self.deadline = deadline
        self.accountID = accountID
    }

    func fetchSnapshot() async -> UsageSnapshot {
        lock.withLock { _count += 1 }
        return UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: deadline)],
            planLabel: nil,
            capturedAt: clock.now(),
            freshness: .live
        )
    }
}

/// Clocked provider whose next fetch can be held open, so a lane can be observed draining.
private final class SuspendableClockedProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID = .claude
    let displayName = "Claude"
    let pollingLane: ProviderPollingLane = .serial("claude-cli")
    private let clock: MutableDateSource
    private let lock = NSLock()
    private var suspendNext = false
    private var didStart = false
    private var started: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var shouldRelease = false

    init(clock: MutableDateSource) { self.clock = clock }

    func suspendNextFetch() {
        lock.withLock { suspendNext = true; shouldRelease = false; didStart = false }
    }

    func waitUntilStarted() async {
        if lock.withLock({ didStart }) { return }
        await withCheckedContinuation { continuation in
            var resumeNow = false
            lock.withLock { if didStart { resumeNow = true } else { started = continuation } }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            shouldRelease = true
            let pending = release
            release = nil
            return pending
        }
        pending?.resume()
    }

    func fetchSnapshot() async -> UsageSnapshot {
        let (suspend, started) = lock.withLock { () -> (Bool, CheckedContinuation<Void, Never>?) in
            didStart = true
            let pending = self.started
            self.started = nil
            let suspend = suspendNext
            suspendNext = false
            return (suspend, pending)
        }
        started?.resume()
        if suspend, !lock.withLock({ shouldRelease }) {
            await withCheckedContinuation { continuation in
                var resumeNow = false
                lock.withLock { if shouldRelease { resumeNow = true } else { release = continuation } }
                if resumeNow { continuation.resume() }
            }
        }
        return UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: clock.now().addingTimeInterval(3_600))],
            planLabel: nil,
            capturedAt: clock.now(),
            freshness: .live
        )
    }
}
