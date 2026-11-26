import Foundation
import PacemarkCore

enum WarmUpRenderFixture {
    @MainActor
    static func make(for accounts: [ProviderAccount], paused: Bool = false) -> WarmUpAutomation {
        let morning = Calendar.current.date(bySettingHour: 7, minute: 2, second: 0, of: DemoFixture.now) ?? DemoFixture.now
        var settings = WarmUpSettings()
        var ledger = WarmUpLedger()
        for account in accounts {
            switch (account.providerID, account.id) {
            case (.claude, .primary):
                settings.enabled.insert(.init(account: account.key, window: .fiveHour))
                ledger.finish(ledger.reserve(account.key, identity: nil, at: morning), outcome: .sent,
                              resetDeadlines: [WindowKind.fiveHour.persistentID: morning.addingTimeInterval(18_000)])
            case (.claude, _):
                _ = ledger.reserve(account.key, identity: nil, at: morning)
            case (.codex, .primary):
                settings.enabled.insert(.init(account: account.key, window: .weekly))
                ledger.finish(ledger.reserve(account.key, identity: nil, at: morning), outcome: .failed(.cliNotFound))
            default:
                break
            }
        }
        return WarmUpAutomation(inertSettings: settings, ledger: paused ? nil : ledger)
    }
}
