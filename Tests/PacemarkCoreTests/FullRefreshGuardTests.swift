import Foundation
import Testing

@testable import PacemarkCore

@MainActor
@Suite
struct FullRefreshGuardTests {
    private let reset = Date(timeIntervalSince1970: 3_000_000)
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    private let workID = AccountID("work")

    private struct Rig {
        let store: UsageStore
        let primary: LaneProbe
        let work: LaneProbe
        let clock: ManualClock
    }

    private func freshDefaults() -> UserDefaults {
        DemoMemoryDefaults()
    }

    private func rig() -> Rig {
        let clock = ManualClock(t0)
        let defaults = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let reset = self.reset
        let live: @Sendable () -> UsageProviderFetchResult = {
            .init(snapshot: UsageSnapshot(
                providerID: .claude, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset)],
                planLabel: "Max", capturedAt: clock.now, freshness: .live))
        }
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order, result: live)
        let work = LaneProbe(id: .claude, accountID: workID, lane: lane, order: order, result: live)
        let store = UsageStore(
            providers: [primary, work], preferences: preferences,
            accounts: [.builtIn(for: .claude), ProviderAccount(id: workID, providerID: .claude, label: "Work")],
            now: { clock.now })
        return Rig(store: store, primary: primary, work: work, clock: clock)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
    }


    // MARK: The guard (KTD14.4)

    /// Popover and launch triggers while one full refresh runs await it: one probe round,
    /// one start time, one completion time.
    @Test func aSecondFullRefreshAwaitsTheOneInFlight() async {
        let r = rig()
        r.primary.suspendNextFetch()
        let launch = Task { await r.store.refreshAll() }
        await r.primary.waitUntilStarted()
        #expect(r.store.fullRefreshStartedAt == t0)
        r.clock.advance(3)
        let popover = Task { await r.store.refreshAll() }
        let again = Task { await r.store.refreshAll() }
        await Task.yield()
        #expect(r.store.fullRefreshStartedAt == t0)
        r.primary.release()
        await launch.value
        await popover.value
        await again.value
        #expect(r.primary.fetchCount == 1 && r.work.fetchCount == 1)
        #expect(r.store.fullRefreshStartedAt == nil && r.store.lastFullRefreshCompletedAt == r.clock.now)
        #expect(!r.store.isRefreshing)
    }

    /// Timer passes stay out of `isRefreshing` and are not full refreshes.
    @Test func aTimerPassIsNeitherRefreshingNorAFullRefresh() async {
        let r = rig()
        r.primary.suspendNextFetch()
        r.store.dispatchDueNow()
        await r.primary.waitUntilStarted()
        #expect(!r.store.isRefreshing && r.store.fullRefreshStartedAt == nil)
        r.primary.release()
        await settle { r.store.probingAccounts.isEmpty && r.work.fetchCount == 1 }
        #expect(r.store.lastFullRefreshCompletedAt == nil)
    }

}

private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}
