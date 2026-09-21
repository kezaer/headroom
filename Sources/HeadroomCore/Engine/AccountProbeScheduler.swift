import Foundation

/// What the scheduler needs from the store. Kept as a protocol so the scheduler holds no
/// snapshot, provider, or export logic of its own (2026-09-19 polling plan, KTD1).
@MainActor
protocol AccountProbeSchedulerHost: AnyObject {
    var schedulerNow: Date { get }
    var schedulerChosenInterval: TimeInterval { get }
    func schedulerProvider(for key: AccountKey) -> (any UsageProvider)?
    /// Attached, not being removed, and its subscription surface is on.
    func schedulerIsEligible(_ key: AccountKey) -> Bool
    func schedulerIsPrimary(_ key: AccountKey) -> Bool
    func schedulerFreshness(for key: AccountKey) -> Freshness?
    func schedulerResetDeadline(for key: AccountKey, now: Date) -> Date?
    func schedulerAttachmentGeneration(for key: AccountKey) -> UInt64
    func schedulerBeginCapabilityRefresh(for providers: [any UsageProvider]) -> [ProviderID: UInt64]
    func schedulerApplyCapability(_ state: ProviderCapabilityState, for providerID: ProviderID, generation: UInt64?)
    /// Merges the result with continuity and exports compact surfaces when the key is a
    /// primary (KTD9). Returns whether the result was accepted.
    func schedulerMerge(key: AccountKey, result: UsageProviderFetchResult, attachmentGeneration: UInt64) -> Bool
    /// A lane pass ended, or a concurrent lane's last in-flight fetch finished (KTD6, KTD9).
    func schedulerLaneDidGoIdle(_ lane: ProviderPollingLane)
    /// User-initiated work started or drained (KTD2).
    func schedulerUserWorkDidChange(hasPending: Bool)
}

/// Per-lane due-queue engine (2026-09-19 polling plan, KTD1, KTD2, KTD6–KTD9, KTD11).
///
/// Each CLI lane drains one probe at a time, most overdue first, behind a measured
/// duty-cycle gate; the HTTP lane fetches its due accounts concurrently. The scheduler owns
/// the attempt clock (KTD3), the per-lane probe log (KTD4), and the priority requests that
/// let user actions jump the queue (KTD7). Everything that touches snapshots goes back
/// through the host.
@MainActor
final class AccountProbeScheduler {
    private struct LaneState {
        var draining = false
        var inFlight: Set<AccountKey> = []
        /// Ordered, unique: a repeated request for an account already waiting is coalesced (KTD7).
        var priority: [AccountKey] = []
        var log: [LaneSchedule.ProbeSpan] = []
        var passGeneration: UUID?
        var passCapability: [ProviderID: UInt64] = [:]
        var newestCapability: [ProviderID: ProviderCapabilityState] = [:]
    }

    /// The scheduler is created inside the store's initializer, before `self` can be
    /// captured, so the host attaches right after.
    weak var host: (any AccountProbeSchedulerHost)?

    private var records: [AccountKey: LaneSchedule.AccountRecord] = [:]
    private var laneOf: [AccountKey: ProviderPollingLane] = [:]
    private var lanes: [ProviderPollingLane: LaneState] = [:]
    /// Accounts a user action marked due and that have not merged yet (KTD2).
    private var userPending: Set<AccountKey> = []
    private var userWaiters: [CheckedContinuation<Void, Never>] = []
    private var completionWaiters: [AccountKey: [CheckedContinuation<Void, Never>]] = [:]
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: Membership

    func register(_ provider: any UsageProvider) {
        let key = provider.accountKey
        guard records[key] == nil else { return }
        records[key] = LaneSchedule.AccountRecord(key: key)
        laneOf[key] = provider.pollingLane
        if lanes[provider.pollingLane] == nil { lanes[provider.pollingLane] = LaneState() }
    }

    func unregister(_ key: AccountKey) {
        records.removeValue(forKey: key)
        if let lane = laneOf.removeValue(forKey: key) {
            lanes[lane]?.priority.removeAll { $0 == key }
        }
        finish(key)
    }

    /// KTD11: a re-enabled or newly attached account is due now once, with no history, so
    /// its first gap can neither stretch the displayed interval nor read as overdue.
    func markDueNow(_ keys: [AccountKey]) {
        for key in keys {
            guard var record = records[key] else { continue }
            record.lastAttempt = nil
            record.previousAttempt = nil
            record.forcedDue = true
            records[key] = record
        }
    }

    // MARK: Requests

    /// KTD2: a user asked for everything. Every eligible account is due now and bypasses
    /// the duty-cycle gate; `waitUntilUserWorkDrains()` returns when all of them merged.
    func markAllDue() {
        guard let host else { return }
        for key in records.keys where host.schedulerIsEligible(key) {
            records[key]?.forcedDue = true
            insertUserPending(key)
        }
    }

    /// KTD7: front of the account's lane; served after the in-flight probe.
    func requestPriority(_ key: AccountKey) {
        guard let host, records[key] != nil, host.schedulerIsEligible(key), let lane = laneOf[key] else { return }
        insertUserPending(key)
        // A probe of this very account is already running; its result answers the request.
        if lanes[lane]?.inFlight.contains(key) == true { return }
        if lanes[lane]?.priority.contains(key) == false {
            lanes[lane]?.priority.append(key)
        }
        dispatchDue()
    }

    /// Timer tick, popover open, or a surface change: start every idle lane that has due
    /// work the gate allows. Draining lanes serve their own queue and are left alone.
    func dispatchDue() {
        guard host != nil else { return }
        for lane in lanes.keys {
            switch lane {
            case .serial:
                startSerialPassIfNeeded(lane)
            case .concurrent:
                dispatchConcurrent(lane)
            }
        }
    }

    func dispatchDue(for providerID: ProviderID) {
        guard host != nil else { return }
        let involved = Set(laneOf.filter { $0.key.providerID == providerID }.values)
        for lane in involved {
            switch lane {
            case .serial:
                startSerialPassIfNeeded(lane)
            case .concurrent:
                dispatchConcurrent(lane, providerID: providerID)
            }
        }
    }

    func waitUntilUserWorkDrains() async {
        guard !userPending.isEmpty else { return }
        await withCheckedContinuation { continuation in
            userWaiters.append(continuation)
        }
    }

    func waitForCompletion(of key: AccountKey) async {
        guard userPending.contains(key) else { return }
        await withCheckedContinuation { continuation in
            completionWaiters[key, default: []].append(continuation)
        }
    }

    var allLanesIdle: Bool {
        lanes.values.allSatisfy { !$0.draining && $0.inFlight.isEmpty }
    }

    /// A full refresh returns only once every lane pass it started has ended, so pass-end
    /// capability verdicts and exports have landed (the contract the store tests rely on).
    func waitUntilLanesIdle() async {
        guard !allLanesIdle else { return }
        await withCheckedContinuation { continuation in
            idleWaiters.append(continuation)
        }
    }

    // MARK: Cadence readouts (KTD4, KTD12)

    func effectiveInterval(for lane: ProviderPollingLane, chosen: TimeInterval) -> TimeInterval {
        guard case .serial = lane else { return chosen }
        let gaps = liveRecords(in: lane).filter(\.isOnCadence).compactMap(\.attemptGap)
        return LaneSchedule.effectiveInterval(chosen: chosen, attemptGaps: gaps)
    }

    func effectiveInterval(forProvider providerID: ProviderID, chosen: TimeInterval) -> TimeInterval {
        guard let lane = laneOf.first(where: { $0.key.providerID == providerID })?.value else { return chosen }
        return effectiveInterval(for: lane, chosen: chosen)
    }

    func accountCount(for providerID: ProviderID) -> Int {
        guard let host else { return 0 }
        return records.keys.filter { $0.providerID == providerID && host.schedulerIsEligible($0) }.count
    }

    /// KTD6: seconds until the earliest due account in an idle lane, or until a closed
    /// lane's budget reopens, clamped by `LaneSchedule.wakeDelay`.
    func wakeDelay() -> TimeInterval {
        guard let host else { return LaneSchedule.chosenInterval(minutes: Preferences.defaultIntervalMinutes) }
        let now = host.schedulerNow
        let chosen = host.schedulerChosenInterval
        var candidates: [Date] = []
        for (lane, state) in lanes where !state.draining && state.inFlight.isEmpty {
            let effective = effectiveInterval(for: lane, chosen: chosen)
            let dueDates = liveRecords(in: lane).map { LaneSchedule.nextDue(for: $0, chosen: chosen, effective: effective) }
            guard var earliest = dueDates.min() else { continue }
            if case .serial = lane,
               let reopens = LaneSchedule.budgetReopens(log: state.log, now: now, chosen: chosen) {
                earliest = max(earliest, reopens)
            }
            candidates.append(earliest)
        }
        return LaneSchedule.wakeDelay(candidates: candidates, now: now, chosen: chosen)
    }

    // MARK: Lane passes

    private func startSerialPassIfNeeded(_ lane: ProviderPollingLane) {
        guard let host, let state = lanes[lane], !state.draining else { return }
        let now = host.schedulerNow
        let chosen = host.schedulerChosenInterval
        let effective = effectiveInterval(for: lane, chosen: chosen)
        guard LaneSchedule.nextAccount(
            records: gatedCandidates(in: lane, log: state.log, now: now, chosen: chosen),
            priority: state.priority, now: now, chosen: chosen, effective: effective
        ) != nil else { return }
        lanes[lane]?.draining = true
        Task { @MainActor [weak self] in
            await self?.runSerialPass(lane)
        }
    }

    private func runSerialPass(_ lane: ProviderPollingLane) async {
        guard let host else { return }
        // KTD8: one locator generation and one capability generation per pass.
        let passGeneration = UUID()
        lanes[lane]?.passGeneration = passGeneration
        let providers = laneOf.filter { $0.value == lane }.keys.compactMap { host.schedulerProvider(for: $0) }
        lanes[lane]?.passCapability = host.schedulerBeginCapabilityRefresh(for: providers)
        lanes[lane]?.newestCapability = [:]

        while let host = self.host, let state = lanes[lane] {
            let now = host.schedulerNow
            let chosen = host.schedulerChosenInterval
            let effective = effectiveInterval(for: lane, chosen: chosen)
            // R8: timer work waits for the budget; user work never does, so a closed gate
            // narrows the candidates to user requests instead of ending the pass.
            guard let key = LaneSchedule.nextAccount(
                records: gatedCandidates(in: lane, log: state.log, now: now, chosen: chosen),
                priority: state.priority, now: now, chosen: chosen, effective: effective
            ) else { break }
            let isPriority = state.priority.contains(key)
            lanes[lane]?.priority.removeAll { $0 == key }
            await probe(
                key,
                lane: lane,
                // KTD8: a user action's epoch advance must still force a fresh search.
                locatorGeneration: isPriority ? UUID() : passGeneration,
                capabilityGeneration: lanes[lane]?.passCapability[key.providerID],
                appliesCapabilityImmediately: isPriority
            )
        }

        if let state = lanes[lane] {
            for (providerID, capability) in state.newestCapability {
                host.schedulerApplyCapability(capability, for: providerID, generation: state.passCapability[providerID])
            }
        }
        lanes[lane]?.newestCapability = [:]
        lanes[lane]?.passCapability = [:]
        lanes[lane]?.passGeneration = nil
        lanes[lane]?.draining = false
        host.schedulerLaneDidGoIdle(lane)
        notifyIdleWaitersIfNeeded()
        // Work may have become due while the pass ran (a priority request arriving as the
        // loop exited, or the gate reopening); let the next wake or request restart it.
    }

    private func dispatchConcurrent(_ lane: ProviderPollingLane, providerID: ProviderID? = nil) {
        guard let host, let state = lanes[lane] else { return }
        let now = host.schedulerNow
        let chosen = host.schedulerChosenInterval
        var records = liveRecords(in: lane)
        if let providerID { records = records.filter { $0.key.providerID == providerID } }
        let due = LaneSchedule.dueAccounts(
            records: records, priority: state.priority, now: now, chosen: chosen, effective: chosen
        )
        for key in due where !state.inFlight.contains(key) {
            lanes[lane]?.priority.removeAll { $0 == key }
            guard let provider = host.schedulerProvider(for: key) else { continue }
            let cycle = host.schedulerBeginCapabilityRefresh(for: [provider])
            lanes[lane]?.inFlight.insert(key)
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.probe(
                    key,
                    lane: lane,
                    locatorGeneration: UUID(),
                    capabilityGeneration: cycle[key.providerID],
                    appliesCapabilityImmediately: true,
                    alreadyInFlight: true
                )
                if self.lanes[lane]?.inFlight.isEmpty == true {
                    self.host?.schedulerLaneDidGoIdle(lane)
                    self.notifyIdleWaitersIfNeeded()
                }
            }
        }
    }

    private func probe(
        _ key: AccountKey,
        lane: ProviderPollingLane,
        locatorGeneration: UUID,
        capabilityGeneration: UInt64?,
        appliesCapabilityImmediately: Bool,
        alreadyInFlight: Bool = false
    ) async {
        guard let host, let provider = host.schedulerProvider(for: key), host.schedulerIsEligible(key) else {
            if alreadyInFlight { lanes[lane]?.inFlight.remove(key) }
            finish(key)
            return
        }
        let start = host.schedulerNow
        if var record = records[key] {
            record.previousAttempt = record.lastAttempt
            record.lastAttempt = start
            record.forcedDue = false
            records[key] = record
        }
        if !alreadyInFlight { lanes[lane]?.inFlight.insert(key) }
        let attachment = host.schedulerAttachmentGeneration(for: key)

        let result = await CLIExecutableRefreshContext.$generation.withValue(locatorGeneration) {
            await provider.fetchResult()
        }

        // The store may have gone away while the probe ran; nothing left to merge into.
        guard let liveHost = self.host else { return }
        let end = liveHost.schedulerNow
        lanes[lane]?.inFlight.remove(key)
        appendToLog(LaneSchedule.ProbeSpan(start: start, end: end), lane: lane, now: end, chosen: liveHost.schedulerChosenInterval)
        let outcome = LaneSchedule.outcome(of: result)
        if var record = records[key] {
            record.consecutiveFailures = LaneSchedule.consecutiveFailures(after: outcome, previous: record.consecutiveFailures)
            records[key] = record
        }
        let accepted = liveHost.schedulerMerge(key: key, result: result, attachmentGeneration: attachment)
        if accepted, let capability = result.capability {
            if appliesCapabilityImmediately {
                liveHost.schedulerApplyCapability(capability, for: key.providerID, generation: capabilityGeneration)
            }
            // Serial lanes keep the newest verdict for pass end so a recovered later account
            // clears an earlier path miss from the same pass.
            lanes[lane]?.newestCapability[key.providerID] = capability
        }
        finish(key)
    }

    // MARK: Helpers

    /// Records the host can currently schedule, with the fields that live on the store
    /// (primary selection, never-signed-in state, reset deadline) filled in at read time.
    private func liveRecords(in lane: ProviderPollingLane) -> [LaneSchedule.AccountRecord] {
        guard let host else { return [] }
        let now = host.schedulerNow
        return laneOf.compactMap { element -> LaneSchedule.AccountRecord? in
            let (key, memberLane) = element
            guard memberLane == lane, var record = records[key], host.schedulerIsEligible(key) else { return nil }
            record.isPrimary = host.schedulerIsPrimary(key)
            record.isNeverSignedIn = LaneSchedule.isNeverSignedIn(host.schedulerFreshness(for: key))
            record.resetDeadline = host.schedulerResetDeadline(for: key, now: now)
            return record
        }
    }

    private func gatedCandidates(
        in lane: ProviderPollingLane,
        log: [LaneSchedule.ProbeSpan],
        now: Date,
        chosen: TimeInterval
    ) -> [LaneSchedule.AccountRecord] {
        let records = liveRecords(in: lane)
        if LaneSchedule.mayStartTimerProbe(log: log, now: now, chosen: chosen) { return records }
        return records.filter { userPending.contains($0.key) }
    }

    private func notifyIdleWaitersIfNeeded() {
        guard allLanesIdle, !idleWaiters.isEmpty else { return }
        let waiters = idleWaiters
        idleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func appendToLog(_ span: LaneSchedule.ProbeSpan, lane: ProviderPollingLane, now: Date, chosen: TimeInterval) {
        guard case .serial = lane else { return }
        var log = lanes[lane]?.log ?? []
        log.append(span)
        let horizon = now.addingTimeInterval(-2 * LaneSchedule.window(chosen: chosen))
        log.removeAll { $0.end < horizon }
        lanes[lane]?.log = log
    }

    private func insertUserPending(_ key: AccountKey) {
        let wasEmpty = userPending.isEmpty
        userPending.insert(key)
        if wasEmpty { host?.schedulerUserWorkDidChange(hasPending: true) }
    }

    private func finish(_ key: AccountKey) {
        if let waiters = completionWaiters.removeValue(forKey: key) {
            for waiter in waiters { waiter.resume() }
        }
        guard userPending.remove(key) != nil, userPending.isEmpty else { return }
        host?.schedulerUserWorkDidChange(hasPending: false)
        let waiters = userWaiters
        userWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
