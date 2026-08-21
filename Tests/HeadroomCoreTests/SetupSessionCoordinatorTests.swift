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

    @Test func beginWhileWrapperIsOpenExposesRefusalThenRetriesAfterHandoffEnds() async {
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

        #expect(coordinator.hasActiveHandoff(for: account.key))
        coordinator.begin(for: account, mode: .deviceCode)

        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)
        #expect(coordinator.sessionMode(for: account.key) == .standard)
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(harness.scheduler.pendingCount == 0)

        coordinator.handoffDidEnd(account.key, completion: .failed)

        #expect(!coordinator.hasActiveHandoff(for: account.key))
        #expect(coordinator.state(for: account.key) == .verifying)
        coordinator.receive(
            .stale(for: .codex, reason: .providerSetup(.codexAuthAbsent)),
            for: account.key
        )
        coordinator.begin(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard),
            .init(key: account.key, mode: .standard),
        ])
    }

    @Test func postWrapperVerificationDoesNotReportAnActiveHandoff() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.hasActiveHandoff(for: account.key))

        coordinator.handoffDidEnd(account.key)

        #expect(coordinator.state(for: account.key) == .verifying)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
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

    @Test func forceCancelOpenHandoffClearsRefusalAndReleasesLoginSlot() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.begin(for: account)
        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)

        coordinator.forceCancel(account.key)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func forceCancelWaitingHandoffMakesPendingRetryInert() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.scheduler.pendingCount == 1)

        coordinator.forceCancel(account.key)
        harness.scheduler.fireLastIncludingCancelled()

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
        #expect(harness.refreshCalls.isEmpty)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func forceCancelAllowsImmediateBeginForSameAccount() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.forceCancel(account.key)
        coordinator.begin(for: account)
        await settleTasks()

        #expect(harness.prepareCalls == [
            .init(key: account.key, mode: .standard),
            .init(key: account.key, mode: .standard),
        ])
        #expect(harness.openCalls == [account.key, account.key])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(coordinator.hasActiveHandoff(for: account.key))
    }

    @Test func forceCancelFinalVerificationMakesLateFailuresAndStopLossInert() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)
        #expect(coordinator.state(for: account.key) == .verifying)

        coordinator.forceCancel(account.key)
        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)
        coordinator.receive(
            .stale(for: .claude, reason: .providerSetup(.claudeCLIMissing)),
            for: account.key
        )
        harness.scheduler.fireLastIncludingCancelled()

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func lateHandoffEndAfterForceCancelDoesNotStartVerification() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("codex-extra"), providerID: .codex, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.forceCancel(account.key)
        coordinator.handoffDidEnd(account.key, completion: .failed)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(harness.refreshCalls.isEmpty)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func forceCancelCodexSlotHolderAllowsBlockedAccountToContinue() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.begin(for: second)
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.forceCancel(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()

        #expect(coordinator.state(for: first.key) == .cancelled)
        #expect(coordinator.state(for: second.key) == .waiting(attempt: 0))
        #expect(harness.openCalls == [first.key, second.key])
    }

    @Test func resetIgnoresLiveSnapshotDuringPreparationAndStillOpensHandoff() async {
        let harness = SetupCoordinatorHarness()
        harness.suspendPreparation = true
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .preparing)
        #expect(harness.openCalls.isEmpty)
        harness.resumePreparation()
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(harness.openCalls == [account.key])
    }

    @Test func resetSettlesOnlyFromLiveResultAfterHandoffEnds() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .codex)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.receive(.live(.codex, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
        #expect(coordinator.hasActiveHandoff(for: account.key))

        coordinator.handoffDidEnd(account.key, completion: .failed)
        #expect(coordinator.state(for: account.key) == .verifying)
        coordinator.receive(.live(.codex, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.resetBoundaryCalls == [account.key, account.key])
    }

    @Test func ordinaryBeginDuringActiveResetDoesNotClearResetSettlementGuard() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.begin(for: account)
        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .blockedByOpenHandoff)
        #expect(coordinator.hasActiveHandoff(for: account.key))
    }

    @Test func refusedResetDoesNotInvalidateUsageOrArmResetSettlement() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.receive(.live(.claude, windows: []), for: account.key)
        coordinator.beginReset(for: account)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.resetBoundaryCalls.isEmpty)
    }

    @Test func providerBlockedResetKeepsItsResetIntentWhenContinued() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("codex-two"), providerID: .codex, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        await settleTasks()
        coordinator.beginReset(for: second)
        #expect(harness.resetBoundaryCalls.isEmpty)

        coordinator.forceCancel(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()
        coordinator.receive(.live(.codex, windows: []), for: second.key)

        #expect(coordinator.state(for: second.key) == .waiting(attempt: 0))
        #expect(harness.resetBoundaryCalls == [second.key])
    }

    @Test func forceCancelResetLeavesSessionCancelledAndAllowsOrdinaryPolling() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.beginReset(for: account)
        await settleTasks()
        coordinator.forceCancel(account.key)
        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .cancelled)
        #expect(!coordinator.hasActiveHandoff(for: account.key))
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
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.cancel(first.key)
        await settleTasks()
        #expect(harness.openCalls == [first.key])

        coordinator.continueSetup(for: second)
        await settleTasks()
        #expect(harness.openCalls == [first.key])
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

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
        #expect(coordinator.state(for: second.key) == .blockedByProviderLogin(providerID: .codex, active: first.key))

        coordinator.handoffDidEnd(first.key)
        coordinator.continueSetup(for: second)
        await settleTasks()

        #expect(harness.prepareCalls.last == .init(key: second.key, mode: .deviceCode))
        #expect(coordinator.sessionMode(for: second.key) == .deviceCode)
    }

    @Test func grokLoginsCanOpenConcurrentlyBecauseTheCLIUsesEphemeralCallbacks() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("grok-one"), providerID: .grok, label: "One", isBuiltIn: false)
        let second = ProviderAccount(id: AccountID("grok-two"), providerID: .grok, label: "Two", isBuiltIn: false)

        coordinator.begin(for: first)
        coordinator.begin(for: second)
        await settleTasks()

        #expect(Set(harness.openCalls) == Set([first.key, second.key]))
        #expect(coordinator.state(for: first.key) == .waiting(attempt: 0))
        #expect(coordinator.state(for: second.key) == .waiting(attempt: 0))
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

    @Test func confirmedAbsentDuringFinalRefreshFailsImmediately() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key, completion: .succeeded)

        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)

        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(harness.scheduler.pendingCount == 0)
        coordinator.receive(.stale(for: .claude, reason: .transient("redacted")), for: account.key)
        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))
    }

    @Test func inconclusiveCapabilityWaitsForLiveResultBeforeStopLoss() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)

        #expect(coordinator.state(for: account.key) == .verifying)
        #expect(harness.scheduler.pendingDelays == [.seconds(100)])

        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func inconclusiveCapabilityBecomesTypedFailureAtStopLoss() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)

        harness.scheduler.fireNext()

        #expect(
            coordinator.state(for: account.key)
                == .failed(.providerCapability(.inconclusive(.shellTimeout)))
        )
    }

    @Test func confirmedAbsentFansOutOnlyAcrossMatchingProviderSessions() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let first = ProviderAccount(id: AccountID("claude-one"), providerID: .claude, label: "One")
        let second = ProviderAccount(id: AccountID("claude-two"), providerID: .claude, label: "Two")
        let codex = ProviderAccount(id: AccountID("codex-one"), providerID: .codex, label: "Codex")

        for account in [first, second, codex] {
            coordinator.begin(for: account)
        }
        await settleTasks()
        for account in [first, second, codex] {
            coordinator.handoffDidEnd(account.key)
        }

        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)

        #expect(coordinator.state(for: first.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(coordinator.state(for: second.key) == .failed(.providerCapability(.confirmedAbsent)))
        #expect(coordinator.state(for: codex.key) == .verifying)
    }

    @Test func silentFinalRefreshStopsAndCanRestartCleanly() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(verificationStopLoss: .seconds(100))
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)

        harness.scheduler.fireNext()
        #expect(coordinator.state(for: account.key) == .failed(.retryExhausted))

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.count == 2)
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func finalVerificationUsesSerialLaneBoundNotRetryLadderScale() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator(
            retryDelays: [.seconds(3), .seconds(7), .seconds(15), .seconds(30)]
        )
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)

        #expect(harness.scheduler.pendingDelays == [.seconds(240)])
        coordinator.receive(.live(.claude, windows: []), for: account.key)
        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func liveResultReconnectsAfterPriorCapabilityFailure() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.confirmedAbsent, for: .claude)
        #expect(coordinator.state(for: account.key) == .failed(.providerCapability(.confirmedAbsent)))

        coordinator.receive(.live(.claude, windows: []), for: account.key)

        #expect(coordinator.state(for: account.key) == .connected)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func cancelledStopLossCannotSettleRemovedSession() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(
            id: AccountID("claude-extra"),
            providerID: .claude,
            label: "Work",
            isBuiltIn: false
        )

        coordinator.begin(for: account)
        await settleTasks()
        coordinator.handoffDidEnd(account.key)
        coordinator.receiveCapabilityFailure(.inconclusive(.shellTimeout), for: .claude)
        coordinator.markRemoved(account.key)

        harness.scheduler.fireLastIncludingCancelled()

        #expect(coordinator.state(for: account.key) == .removed)
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

    @Test func reinstatedKeyStartsSetupAgainAfterRemoval() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount.builtIn(for: .claude)

        coordinator.markRemoved(account.key)
        #expect(coordinator.state(for: account.key) == .removed)
        // While removed, begin is a silent no-op — the sentinel the reinstate clears.
        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls.isEmpty)

        coordinator.markReinstated(account.key)
        #expect(coordinator.state(for: account.key) == .idle)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(harness.prepareCalls == [.init(key: account.key, mode: .standard)])
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
    }

    @Test func reinstateOnlyClearsTheRemovedSentinel() async {
        let harness = SetupCoordinatorHarness()
        let coordinator = harness.makeCoordinator()
        let account = ProviderAccount(id: AccountID("claude-extra"), providerID: .claude, label: "Work", isBuiltIn: false)

        coordinator.begin(for: account)
        await settleTasks()
        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))

        coordinator.markReinstated(account.key)

        #expect(coordinator.state(for: account.key) == .waiting(attempt: 0))
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
    var resetBoundaryCalls: [AccountKey] = []
    var existingAccounts: Set<AccountKey> = []
    var suspendPreparation = false
    var openResult: SetupOpenResult = .success(())
    private var preparationContinuation: CheckedContinuation<SetupPreparationResult, Never>?

    func makeCoordinator(
        retryDelays: [Duration] = [.seconds(1)],
        verificationStopLoss: Duration = .seconds(240)
    ) -> SetupSessionCoordinator {
        SetupSessionCoordinator(
            scheduler: scheduler,
            retryDelays: retryDelays,
            verificationStopLoss: verificationStopLoss,
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
            requestRefresh: { [weak self] key in self?.refreshCalls.append(key) },
            resetBoundary: { [weak self] key in self?.resetBoundaryCalls.append(key) }
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
        let delay: Duration
        let operation: @MainActor @Sendable () -> Void
        init(delay: Duration, operation: @escaping @MainActor @Sendable () -> Void) {
            self.delay = delay
            self.operation = operation
        }
        func cancel() { isCancelled = true }
    }

    private var entries: [Entry] = []
    var pendingCount: Int { entries.filter { !$0.isCancelled }.count }
    var pendingDelays: [Duration] { entries.filter { !$0.isCancelled }.map(\.delay) }

    func schedule(after delay: Duration, operation: @escaping @MainActor @Sendable () -> Void) -> any SetupRetryCancellation {
        let entry = Entry(delay: delay, operation: operation)
        entries.append(entry)
        return entry
    }

    func fireNext() {
        guard let index = entries.firstIndex(where: { !$0.isCancelled }) else { return }
        let entry = entries.remove(at: index)
        entry.operation()
    }

    func fireLastIncludingCancelled() {
        guard !entries.isEmpty else { return }
        entries.removeLast().operation()
    }
}
