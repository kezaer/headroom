import Foundation
import Testing
@testable import HeadroomCore

/// U2 of the 2026-09-19 polling plan: the per-lane due-queue through the store's public
/// surface — ordering, priority requests, backoff, the user-only refreshing flag, and
/// provider-scoped dispatch. All providers are doubles; nothing waits on a real clock.
@MainActor
struct AccountProbeSchedulerTests {
    private let reset = Date(timeIntervalSince1970: 3_000_000)
    private let t0 = Date(timeIntervalSince1970: 2_000_000_000)

    private func preferences() -> Preferences {
        let suite = "headroom.scheduler.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Preferences(defaults: defaults)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<400 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func liveSnapshot(_ id: ProviderID, at capturedAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            providerID: id,
            windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: reset)],
            planLabel: nil,
            capturedAt: capturedAt ?? Date(),
            freshness: .live
        )
    }

    // MARK: Ordering (AE1, AE4)

    @Test func primaryIsProbedBeforeAnOverdueExtraInASerialLane() async {
        let order = ProbeOrder()
        let extraID = AccountID("work")
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: .serial("claude-cli"), order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        // Providers listed extra-first so registry order, not array order, must decide.
        let store = UsageStore(
            providers: [extra, primary],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )

        await store.refreshAll()

        #expect(order.keys.first == primary.accountKey)
        #expect(order.keys.count == 2)
    }

    @Test func priorityRequestIsServedRightAfterTheInFlightProbe() async {
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let ids = ["a", "b", "c"].map(AccountID.init)
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        primary.suspendNextFetch()
        let extras = ids.map { id in
            LaneProbe(id: .claude, accountID: id, lane: lane, order: order,
                      result: { .init(snapshot: self.liveSnapshot(.claude)) })
        }
        let accounts: [ProviderAccount] = [.builtIn(for: .claude)]
            + ids.map { ProviderAccount(id: $0, providerID: .claude, label: $0.raw) }
        let store = UsageStore(providers: [primary] + extras, preferences: preferences(), accounts: accounts)

        let refresh = Task { await store.refreshAll() }
        await primary.waitUntilStarted()
        let requested = AccountKey(providerID: .claude, accountID: ids[2])
        store.refreshAccountNow(requested)
        primary.release()
        await refresh.value

        #expect(order.keys.first == primary.accountKey)
        #expect(order.keys.dropFirst().first == requested)
        #expect(order.keys.count == 4)
    }

    // MARK: Concurrent lane and backoff (AE8)

    @Test func codexAccountsFetchConcurrentlyAndOnlyTheFailingOneBacksOff() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let healthyID = AccountID("healthy")
        let failingID = AccountID("failing")
        let primary = LaneProbe(id: .codex, accountID: .primary, lane: .concurrent, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.codex, at: clock.now())) })
        let healthy = LaneProbe(id: .codex, accountID: healthyID, lane: .concurrent, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.codex, at: clock.now())) })
        let failing = LaneProbe(id: .codex, accountID: failingID, lane: .concurrent, order: order,
                                result: { .init(snapshot: .stale(for: .codex, reason: .transient("retry"))) })
        primary.suspendNextFetch()
        healthy.suspendNextFetch()
        let store = UsageStore(
            providers: [primary, healthy, failing],
            preferences: preferences(),
            accounts: [
                .builtIn(for: .codex),
                ProviderAccount(id: healthyID, providerID: .codex, label: "Healthy"),
                ProviderAccount(id: failingID, providerID: .codex, label: "Failing"),
            ],
            now: clock.now
        )

        let refresh = Task { await store.refreshAll() }
        // Both suspended fetches are in flight at once: the HTTP lane does not serialize.
        await primary.waitUntilStarted()
        await healthy.waitUntilStarted()
        #expect(primary.fetchCount == 1 && healthy.fetchCount == 1)
        primary.release()
        healthy.release()
        await refresh.value
        #expect(failing.fetchCount == 1)

        // One interval on: the healthy accounts are due, the failing one is backing off.
        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await settle { healthy.fetchCount == 2 && primary.fetchCount == 2 }
        #expect(healthy.fetchCount == 2)
        #expect(failing.fetchCount == 1)

        // Two intervals on (5 × 2¹ = 10 min): the failing account is due again.
        clock.set(t0.addingTimeInterval(10 * 60 + 1))
        store.dispatchDueNow()
        await settle { failing.fetchCount == 2 }
        #expect(failing.fetchCount == 2)
    }

    @Test func neverSignedInExtraWaitsFourIntervalsWhileThePrimaryStaysOnCadence() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let lane = ProviderPollingLane.serial("claude-cli")
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: .stale(for: .claude, reason: .notLoggedIn("sign in"))) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")],
            now: clock.now
        )
        await store.refreshAll()
        #expect(primary.fetchCount == 1 && extra.fetchCount == 1)

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        store.dispatchDueNow()
        await settle { primary.fetchCount == 2 }
        #expect(primary.fetchCount == 2)
        #expect(extra.fetchCount == 1)

        clock.set(t0.addingTimeInterval(20 * 60 + 1))
        store.dispatchDueNow()
        await settle { extra.fetchCount == 2 }
        #expect(extra.fetchCount == 2)
    }

    // MARK: Refreshing flag and spend refreshes (KTD2)

    @Test func timerPassLeavesIsRefreshingFalseButAUserRefreshSetsIt() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                 result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let store = UsageStore(providers: [provider], preferences: preferences(), now: clock.now)
        await store.refreshAll()

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        provider.suspendNextFetch()
        store.dispatchDueNow()
        await provider.waitUntilStarted()
        #expect(!store.isRefreshing)

        let refresh = Task { await store.refreshAll() }
        await settle { store.isRefreshing }
        #expect(store.isRefreshing)
        provider.release()
        await refresh.value
        #expect(!store.isRefreshing)
    }

    @Test func spendOnlyRefreshRunsWhileAClaudeLaneIsDraining() async {
        let order = ProbeOrder()
        let provider = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                 result: { .init(snapshot: self.liveSnapshot(.claude)) })
        provider.suspendNextFetch()
        let spend = StubSpendProvider(id: .claude)
        let prefs = preferences()
        prefs.setSurfaceEnabled(true, for: .anthropicAPI)
        let store = UsageStore(providers: [provider], apiSpendProviders: [spend], preferences: prefs)

        let refresh = Task { await store.refreshAll() }
        await provider.waitUntilStarted()
        await store.refreshAPISpendOnly()
        #expect(spend.fetchCount == 1)

        provider.release()
        await refresh.value
    }

    // MARK: Provider-scoped dispatch (KTD11)

    @Test func enablingASurfaceDispatchesOnlyThatProvider() async {
        let order = ProbeOrder()
        let claude = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                               result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let grok = LaneProbe(id: .grok, accountID: .primary, lane: .serial("grok-cli"), order: order,
                             result: { .init(snapshot: self.liveSnapshot(.grok)) })
        let store = UsageStore(providers: [claude, grok], preferences: preferences())
        await store.refreshAll()
        #expect(claude.fetchCount == 1)
        #expect(grok.fetchCount == 0)

        store.setSurfaceEnabled(true, for: .grokSubscription)
        store.dispatchDueNow(for: .grok)
        await settle { grok.fetchCount == 1 }
        #expect(grok.fetchCount == 1)
        #expect(claude.fetchCount == 1)
    }

    @Test func fullRefreshExportsOnceAndAPrimaryTimerMergeExportsAtOnce() async {
        let clock = MutableDateSource(t0)
        let order = ProbeOrder()
        let exporter = SpyWidgetExporter()
        let extraID = AccountID("work")
        let lane = ProviderPollingLane.serial("claude-cli")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: lane, order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: lane, order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude, at: clock.now())) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")],
            now: clock.now,
            widgetExporter: exporter
        )
        await store.refreshAll()
        #expect(exporter.exports.count == 1)

        clock.set(t0.addingTimeInterval(5 * 60 + 1))
        extra.suspendNextFetch()
        store.dispatchDueNow()
        await extra.waitUntilStarted()
        // The primary merged first and exported without waiting for the extra (R19).
        #expect(exporter.exports.count == 2)
        extra.release()
        await settle { store.scheduler.allLanesIdle }
        #expect(exporter.exports.count == 2)
    }

    @Test func pollCadenceReportsChosenIntervalAndAccountCount() async {
        let order = ProbeOrder()
        let extraID = AccountID("work")
        let primary = LaneProbe(id: .claude, accountID: .primary, lane: .serial("claude-cli"), order: order,
                                result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let extra = LaneProbe(id: .claude, accountID: extraID, lane: .serial("claude-cli"), order: order,
                              result: { .init(snapshot: self.liveSnapshot(.claude)) })
        let store = UsageStore(
            providers: [primary, extra],
            preferences: preferences(),
            accounts: [.builtIn(for: .claude), ProviderAccount(id: extraID, providerID: .claude, label: "Work")]
        )
        await store.refreshAll()
        let cadence = store.pollCadence(for: .claude)
        #expect(cadence.chosenInterval == 5 * 60)
        #expect(cadence.effectiveInterval == 5 * 60)
        #expect(cadence.accountCount == 2)
        #expect(!cadence.isStretched)
    }
}

// MARK: - Doubles

/// Records the order in which fetches started across every double in a test.
final class ProbeOrder: @unchecked Sendable {
    private let lock = NSLock()
    private var _keys: [AccountKey] = []
    var keys: [AccountKey] { lock.withLock { _keys } }
    func record(_ key: AccountKey) { lock.withLock { _keys.append(key) } }
}

/// Provider double for scheduler tests: a fixed lane, a result closure, a shared start
/// order, and a one-shot suspend gate the test releases.
final class LaneProbe: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let accountID: AccountID
    let displayName: String
    let pollingLane: ProviderPollingLane
    let reportsProviderCapability: Bool
    private let result: @Sendable () -> UsageProviderFetchResult
    private let order: ProbeOrder
    private let lock = NSLock()
    private var count = 0
    private var suspendNext = false
    private var started: CheckedContinuation<Void, Never>?
    private var didStart = false
    private var release: CheckedContinuation<Void, Never>?
    private var shouldRelease = false

    init(
        id: ProviderID,
        accountID: AccountID,
        lane: ProviderPollingLane,
        order: ProbeOrder,
        reportsProviderCapability: Bool = false,
        result: @escaping @Sendable () -> UsageProviderFetchResult
    ) {
        self.id = id
        self.accountID = accountID
        self.displayName = id.displayName
        self.pollingLane = lane
        self.order = order
        self.reportsProviderCapability = reportsProviderCapability
        self.result = result
    }

    var fetchCount: Int { lock.withLock { count } }

    /// The next fetch blocks until `release()`.
    func suspendNextFetch() {
        lock.withLock {
            suspendNext = true
            shouldRelease = false
            didStart = false
        }
    }

    func waitUntilStarted() async {
        let already = lock.withLock { didStart }
        if already { return }
        await withCheckedContinuation { continuation in
            var resumeNow = false
            lock.withLock {
                if didStart { resumeNow = true } else { started = continuation }
            }
            if resumeNow { continuation.resume() }
        }
    }

    func release() {
        let continuation = lock.withLock {
            shouldRelease = true
            let pending = release
            release = nil
            return pending
        }
        continuation?.resume()
    }

    func fetchSnapshot() async -> UsageSnapshot { await fetchResult().snapshot }

    func fetchResult() async -> UsageProviderFetchResult {
        let (suspend, started) = lock.withLock {
            count += 1
            didStart = true
            let pending = self.started
            self.started = nil
            let suspend = suspendNext
            suspendNext = false
            return (suspend, pending)
        }
        order.record(accountKey)
        started?.resume()
        if suspend {
            let released = lock.withLock { shouldRelease }
            if !released {
                await withCheckedContinuation { continuation in
                    var resumeNow = false
                    lock.withLock {
                        if shouldRelease { resumeNow = true } else { release = continuation }
                    }
                    if resumeNow { continuation.resume() }
                }
            }
        }
        return result()
    }
}

final class StubSpendProvider: APISpendProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName = "Spend"
    private let lock = NSLock()
    private var count = 0
    var fetchCount: Int { lock.withLock { count } }

    init(id: ProviderID) { self.id = id }

    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        lock.withLock { count += 1 }
        return .stale(providerID: id, displayName: displayName, periodLabel: period.label, reason: .transient("offline"))
    }
}
