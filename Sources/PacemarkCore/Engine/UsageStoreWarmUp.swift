import Foundation

extension UsageStore {
    public func warmUpAccountIdentity(for key: AccountKey) -> AccountIdentity? {
        guard let identity = snapshots[key]?.identity?.identity,
              identity.strength == .strong, identity.providerID == key.providerID
        else { return nil }
        return identity
    }

    public func canEditWarmUp(for key: AccountKey) -> Bool {
        accounts(for: key.providerID).contains { $0.key == key }
            && (warmUp.isInert || key.providerID == .antigravity || warmUpAccountIdentity(for: key) != nil)
    }

    private func warmUpConsentKeys(for key: AccountKey) -> Set<AccountKey> {
        let mergeMap = displayMergeMaps[key.providerID] ?? [:]
        let visible = mergeMap[key] ?? key
        return Set(mergeMap.lazy.filter { $0.value == visible }.map(\.key)).union([visible])
    }

    public func warmUpSelections(for key: AccountKey) -> Set<WarmUpSettings.Selection> {
        let keys = warmUpConsentKeys(for: key)
        let identity = warmUpAccountIdentity(for: key)
        return warmUp.settings.enabled.filter { keys.contains($0.account) && $0.identity == identity }
    }

    public func lastWarmUpAttempt(for key: AccountKey) -> WarmUpLedger.Attempt? {
        let keys = warmUpConsentKeys(for: key)
        let identity = warmUpAccountIdentity(for: key)
        return warmUp.ledger?.attempts.last { keys.contains($0.account) && $0.identity == identity }
    }

    public func setWarmUpEnabled(_ enabled: Bool, for key: AccountKey, window: WindowKind) {
        guard WarmUpCapability.forProvider(key.providerID) == .supported,
              WarmUpSettings.windows(for: key.providerID).contains(window), canEditWarmUp(for: key)
        else { return }
        let visible = displayMergeMaps[key.providerID]?[key] ?? key
        if enabled {
            warmUp.enable(.init(account: visible, window: window, identity: warmUpAccountIdentity(for: visible)))
        } else {
            warmUp.disable(warmUpSelections(for: key).filter { $0.windowID == window.persistentID })
        }
    }

    func evaluateWarmUp() {
        guard !warmUp.isInert, warmUp.settings.isEnabled, !warmUp.settings.enabled.isEmpty else { return }
        let runner = warmUp.runner
        Task { [weak self] in
            await runner.run(
                next: { [weak self] in self?.nextWarmUp() },
                mayLaunch: { [weak self] in self?.canLaunchWarmUp($0) ?? false },
                complete: { [weak self] in self?.completeWarmUp($0, outcome: $1) }
            )
        }
    }

    func nextWarmUp() -> WarmUpRequest? {
        guard let ledger = warmUp.currentLedger() else { return nil }
        let date = now()
        let keys = Set(warmUp.settings.enabled.map(\.account))
        for provider in registeredProviderOrder {
            for account in accounts(for: provider) {
                let key = account.key
                guard !isMergedAway(key), !keys.isDisjoint(with: warmUpConsentKeys(for: key)) else { continue }
                let limits = idleWarmUpDeadlines(for: key, ledger: ledger, at: date)
                guard !limits.isEmpty, let attempt = warmUp.reserve(
                    key, identity: warmUpAccountIdentity(for: key), at: date
                ) else { continue }
                return WarmUpRequest(
                    account: account, attempt: attempt, windowIDs: Set(limits.keys),
                    attachmentGeneration: schedulerAttachmentGeneration(for: key)
                )
            }
        }
        return nil
    }

    private func idleWarmUpDeadlines(
        for key: AccountKey, ledger: WarmUpLedger, at date: Date, excludingAttemptID: UUID? = nil
    ) -> [String: WarmUpCycleDeadline] {
        guard schedulerIsEligible(key), !isMergedAway(key),
              setupCoordinator?.state(for: key).holdsDisplayMerge != true,
              let snapshot = snapshots[key], canEditWarmUp(for: key)
        else { return [:] }
        switch providerCapabilities[key.providerID]?.state {
        case .confirmedAbsent, .inconclusive: return [:]
        default: break
        }
        return WarmUpPlanner.idleDeadlines(
            for: key, snapshot: snapshot, settings: warmUp.settings, ledger: ledger, now: date,
            consentingAccounts: warmUpConsentKeys(for: key), excludingAttemptID: excludingAttemptID
        )
    }

    func canLaunchWarmUp(_ request: WarmUpRequest) -> Bool {
        let key = request.account.key
        guard let ledger = warmUp.currentLedger(),
              warmUp.activeAttemptID == request.attempt.id,
              let reservation = ledger.lastAttempt(for: key, identity: request.attempt.identity),
              reservation.id == request.attempt.id, reservation.outcome == .reserved,
              request.attachmentGeneration == schedulerAttachmentGeneration(for: key),
              request.attempt.identity == warmUpAccountIdentity(for: key)
        else { return false }
        let deadlines = idleWarmUpDeadlines(for: key, ledger: ledger, at: now(), excludingAttemptID: request.attempt.id)
            .filter { request.windowIDs.contains($0.key) }
        guard !deadlines.isEmpty else { return false }
        warmUp.confirmLaunch(resetDeadlines: deadlines)
        return true
    }

    func completeWarmUp(_ request: WarmUpRequest, outcome: WarmUpOutcome) {
        warmUp.finish(request.attempt, outcome: outcome, at: now())
        let key = request.account.key
        guard outcome.ranClient, request.attachmentGeneration == schedulerAttachmentGeneration(for: key) else { return }
        let visible = displayMergeMaps[key.providerID]?[key] ?? key
        scheduler.requestPostWarmUp(visible)
    }
}
