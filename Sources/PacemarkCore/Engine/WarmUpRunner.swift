import Foundation
import Observation

public struct WarmUpRequest: Sendable {
    public let account: ProviderAccount
    public let attempt: WarmUpLedger.Attempt
    public let windowIDs: Set<String>
    let attachmentGeneration: UInt64
}

public protocol WarmUpSender: Sendable {
    func send(_ request: WarmUpRequest, mayLaunch: @MainActor @Sendable () -> Bool) async -> WarmUpOutcome
}

private struct InertWarmUpSender: WarmUpSender {
    func send(_ request: WarmUpRequest, mayLaunch: @MainActor @Sendable () -> Bool) async -> WarmUpOutcome {
        .skipped
    }
}

/// Actor isolation alone is reentrant across a send. Keep the drain owned until the
/// child exits so a merge or wake cannot start another sender concurrently.
actor WarmUpRunner {
    private let sender: any WarmUpSender
    private var draining = false
    private var needsRecheck = false

    init(sender: any WarmUpSender) { self.sender = sender }

    func run(
        next: @MainActor @Sendable () -> WarmUpRequest?,
        mayLaunch: @MainActor @Sendable (WarmUpRequest) -> Bool,
        complete: @MainActor @Sendable (WarmUpRequest, WarmUpOutcome) -> Void
    ) async {
        if draining {
            needsRecheck = true
            return
        }
        draining = true
        defer { draining = false }
        repeat {
            needsRecheck = false
            while let request = await next() {
                let outcome = await sender.send(request) { mayLaunch(request) }
                await complete(request, outcome)
            }
        } while needsRecheck
    }
}

@MainActor
@Observable
public final class WarmUpAutomation {
    public private(set) var settings: WarmUpSettings
    public private(set) var ledger: WarmUpLedger?
    public private(set) var activeAttemptID: UUID?
    let runner: WarmUpRunner
    let isInert: Bool
    private let defaults: UserDefaults?
    private var launchDeadlines: [String: WarmUpCycleDeadline] = [:]

    public init(defaults: UserDefaults, sender: any WarmUpSender) {
        self.defaults = defaults
        settings = WarmUpSettings.load(from: defaults)
        ledger = WarmUpLedger.load(from: defaults)
        runner = WarmUpRunner(sender: sender)
        isInert = false
    }

    public init(inertSettings: WarmUpSettings = WarmUpSettings(), ledger: WarmUpLedger? = WarmUpLedger()) {
        defaults = nil
        settings = inertSettings
        self.ledger = ledger
        runner = WarmUpRunner(sender: InertWarmUpSender())
        isInert = true
    }

    public func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        if let defaults { settings.save(to: defaults) }
    }

    public func setActiveHours(_ hours: WarmUpSettings.ActiveHours) {
        settings.activeHours = hours
        if let defaults { settings.save(to: defaults) }
    }

    func enable(_ selection: WarmUpSettings.Selection) {
        settings.enabled.insert(selection)
        if let defaults { settings.save(to: defaults) }
    }

    func disable(_ selections: Set<WarmUpSettings.Selection>) {
        settings.enabled.subtract(selections)
        if let defaults { settings.save(to: defaults) }
    }

    public func turnOff(for account: AccountKey) {
        let selections = settings.enabled.filter { $0.account == account }
        guard !selections.isEmpty else { return }
        disable(selections)
    }

    func currentLedger() -> WarmUpLedger? {
        if let defaults {
            let stored = WarmUpLedger.load(from: defaults)
            if stored != ledger { ledger = stored }
        }
        return ledger
    }

    func reserve(_ account: AccountKey, identity: AccountIdentity?, at now: Date) -> WarmUpLedger.Attempt? {
        guard activeAttemptID == nil, var ledger else { return nil }
        let attempt = ledger.reserve(account, identity: identity, at: now)
        if let defaults, !ledger.save(to: defaults) { return nil }
        self.ledger = ledger
        activeAttemptID = attempt.id
        return attempt
    }

    func confirmLaunch(resetDeadlines: [String: WarmUpCycleDeadline]) {
        launchDeadlines = resetDeadlines
    }

    func finish(_ attempt: WarmUpLedger.Attempt, outcome: WarmUpOutcome, at date: Date) {
        defer {
            activeAttemptID = nil
            launchDeadlines = [:]
        }
        guard var ledger = currentLedger() else { return }
        ledger.finish(attempt, outcome: outcome, resetDeadlines: launchDeadlines.mapValues { $0.deadline(after: date) })
        if let defaults, !ledger.save(to: defaults) {
            self.ledger = nil
            return
        }
        self.ledger = ledger
    }
}
