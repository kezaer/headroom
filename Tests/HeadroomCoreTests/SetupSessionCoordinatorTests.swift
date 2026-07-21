import Foundation
import Testing
@testable import HeadroomCore

@MainActor
@Suite struct SetupSessionCoordinatorTests {
    @Test func duplicateClicksPrepareAndOpenExactlyOnce() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        coordinator.begin(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(harness.openCalls == [account.key])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func cancellationDuringSuspendedPreparationNeverOpensTerminal() async {
        let harness = SetupCoordinatorHarness()
        harness.suspendPreparation = true
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .preparing)

        coordinator.cancel(account.key)
        harness.resumePreparation()
        await settleTasks()

        #expect(harness.openCalls.isEmpty)
        #expect(harness.discardCalls == [account.key])
        #expect(coordinator.state(for: account.key) == .cancelled)
    }

    @Test func retriesUseVirtualSchedulerAndStopAfterLive() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(retryDelays: [.seconds(1), .seconds(2)])
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.scheduler.pendingCount == 1)

        harness.scheduler.fireNext()
        #expect(harness.refreshCalls == [account.key])
        #expect(harness.scheduler.pendingCount == 1)

        coordinator.receive(.init(providerID: .claude, windows: [], planLabel: nil, capturedAt: Date(), freshness: .live), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func setupSettlesWithNoViewMounted() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.receive(.init(providerID: .codex, windows: [], planLabel: nil, capturedAt: Date(), freshness: .live), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
    }

    @Test func ordinaryLivePollingDoesNotCreateASetupSession() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )
        harness.existingAccounts.insert(account.key)

        coordinator.receive(
            .init(
                providerID: .codex,
                windows: [],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .live
            ),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .idle)
    }

    @Test func secondCodexLoginRequiresFreshContinueActionAfterSlotFrees() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.begin(for: second)
        #expect(coordinator.state(for: second.key) == .blockedByCodexLogin(first.key))

        coordinator.cancel(first.key)
        await settleTasks()
        #expect(harness.openCalls == [first.key])

        coordinator.continueSetup(for: second)
        await settleTasks()
        #expect(harness.openCalls == [first.key])
        #expect(coordinator.state(for: second.key) == .blockedByCodexLogin(first.key))

        coordinator.handoffDidEnd(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()
        #expect(harness.openCalls == [first.key, second.key])
    }

    @Test func blockedDeviceCodeLoginKeepsItsExplicitModeWhenContinued() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.begin(for: second, mode: .deviceCode)
        #expect(coordinator.state(for: second.key) == .blockedByCodexLogin(first.key))

        coordinator.handoffDidEnd(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()

        #expect(harness.prepareCalls.last == .init(key: second.key, mode: .deviceCode))
        #expect(coordinator.sessionMode(for: second.key) == .deviceCode)
    }

    @Test func openerFailureKeepsItsTypedReason() async {
        let harness = SetupCoordinatorHarness()
        harness.openResult = .failure(.pasteboardFailed)
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()

        #expect(coordinator.state(for: account.key) == .failed(.pasteboardFailed))
    }

    @Test func retryExhaustionDoesNotReopenOverActiveHandoffAndExitChecksOnce() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(retryDelays: [.seconds(1)])
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        harness.scheduler.fireNext()
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
        #expect(harness.refreshCalls == [account.key])

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 1)

        coordinator.handoffDidEnd(account.key)
        #expect(harness.refreshCalls == [account.key, account.key])
        coordinator.receive(.stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.provider(.codexCallbackIncomplete)))
        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 2)
    }

    @Test func finalTransientCheckAfterHandoffExitSettlesToActionableFailure() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        #expect(coordinator.state(for: account.key) == .verifying)

        coordinator.receive(.stale(for: .claude, reason: .transient("redacted")), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))
    }

    @Test func successfulCodexLoginWithoutReadableFileBecomesStorageMismatch() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .failed(.provider(.codexStorageMismatch)))
    }

    @Test func unsuccessfulCodexLoginWithoutReadableFileBecomesCallbackIncomplete() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("codex-extra"),
            providerID: .codex,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .failed)
        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: account.key
        )

        #expect(coordinator.state(for: account.key) == .failed(.provider(.codexCallbackIncomplete)))
    }

    @Test func completedHandoffRestoredAfterRelaunchStillRunsFinalClassification() {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let key = AccountKey(providerID: .codex, accountID: AccountID("codex-extra"))
        harness.existingAccounts.insert(key)

        coordinator.handoffDidEnd(key, completion: .succeeded)
        #expect(coordinator.state(for: key) == .verifying)
        #expect(harness.refreshCalls == [key])

        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: key
        )
        #expect(coordinator.state(for: key) == .failed(.provider(.codexStorageMismatch)))
    }

    @Test func removalCancelsRetryAndPreventsLateSettlement() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.markRemoved(account.key)
        coordinator.receive(.init(providerID: .claude, windows: [], planLabel: nil, capturedAt: Date(), freshness: .live), for: account.key)

        #expect(coordinator.state(for: account.key) == .removed)
        #expect(harness.scheduler.pendingCount == 0)
    }

    private func settleTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private final class SetupCoordinatorHarness {
    let scheduler = ManualSetupScheduler()
    struct PrepareCall: Equatable {
        let key: AccountKey
        let mode: SetupHandoffMode
    }

    var prepareCalls: [PrepareCall] = []
    var openCalls: [AccountKey] = []
    var discardCalls: [AccountKey] = []
    var refreshCalls: [AccountKey] = []
    var existingAccounts: Set<AccountKey> = []
    var suspendPreparation = false
    var openResult: SetupOpenResult = .success(())
    private var preparationContinuation: CheckedContinuation<SetupPreparationResult, Never>?

    func makeCoordinator(retryDelays: [Duration] = [.seconds(1)]) -> SetupSessionCoordinator {
        SetupSessionCoordinator(
            scheduler: scheduler,
            retryDelays: retryDelays,
            prepare: { [weak self] account, mode in
                guard let self else { return .failure(.stagingFailed) }
                self.prepareCalls.append(.init(key: account.key, mode: mode))
                self.existingAccounts.insert(account.key)
                if self.suspendPreparation {
                    return await withCheckedContinuation { self.preparationContinuation = $0 }
                }
                return .success(PreparedSetupHandoff(accountKey: account.key, mode: mode))
            },
            open: { [weak self] handoff in
                self?.openCalls.append(handoff.accountKey)
                return self?.openResult ?? .failure(.stagingFailed)
            },
            discard: { [weak self] handoff in self?.discardCalls.append(handoff.accountKey) },
            accountExists: { [weak self] key in self?.existingAccounts.contains(key) == true },
            requestRefresh: { [weak self] key in self?.refreshCalls.append(key) }
        )
    }

    func resumePreparation() {
        preparationContinuation?.resume(returning: .success(PreparedSetupHandoff(
            accountKey: prepareCalls.last?.key ?? AccountKey(providerID: .claude, accountID: .primary),
            mode: prepareCalls.last?.mode ?? .standard
        )))
        preparationContinuation = nil
    }
}

@MainActor
private final class ManualSetupScheduler: SetupRetryScheduling {
    private final class Entry: SetupRetryCancellation {
        var isCancelled = false
        let operation: @MainActor @Sendable () -> Void
        init(operation: @escaping @MainActor @Sendable () -> Void) { self.operation = operation }
        func cancel() { isCancelled = true }
    }

    private var entries: [Entry] = []
    var pendingCount: Int { entries.filter { !$0.isCancelled }.count }

    func schedule(after _: Duration, operation: @escaping @MainActor @Sendable () -> Void) -> any SetupRetryCancellation {
        let entry = Entry(operation: operation)
        entries.append(entry)
        return entry
    }

    func fireNext() {
        guard let index = entries.firstIndex(where: { !$0.isCancelled }) else { return }
        let entry = entries.remove(at: index)
        entry.operation()
    }
}
