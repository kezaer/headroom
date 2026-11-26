import Foundation
import Testing
@testable import PacemarkCore

struct DemoScenarioParityTests {
    @MainActor
    @Test func rememberedScenarioPosesClaudeAndCodexAlike() async throws {
        let fixture = DemoFixture.multiFixture(for: .remembered)
        let defaults = DemoMemoryDefaults()

        let store = UsageStore(
            providers: fixture.providers,
            preferences: Preferences(defaults: defaults),
            accounts: fixture.accounts,
            defaultLoginRecords: fixture.makeDefaultLoginRecordStore()
        )
        await store.refreshAll()
        #expect(store.registeredProviderOrder == [.claude, .codex])

        func signature(_ providerID: ProviderID) -> [RememberedRowSignature] {
            store.displayAccounts(for: providerID).map { row in
                let snapshot = store.snapshot(for: row.key)
                return RememberedRowSignature(
                    label: row.label,
                    kind: row.kind,
                    windows: snapshot.windows.map { window in
                        let state = window.freshness.isLive ? "live" : window.freshness.isUnavailable ? "unavailable" : "stale"
                        let number = window.freshness.isUnavailable
                            ? nil : UsagePercentageMode.remaining.roundedPercentage(for: window)
                        return "\(window.kind.shortLabel) \(state) \(number.map(String.init) ?? "—")"
                    }
                )
            }
        }
        let claude = signature(.claude)
        #expect(claude.count == 3)
        #expect(claude == signature(.codex))
        #expect(claude.map(\.kind) == [.engine, .remembered, .remembered])
        #expect(claude[1].windows.allSatisfy { $0.contains(" stale ") })
        #expect(claude[2].windows.allSatisfy { $0.hasSuffix("unavailable —") })
    }

    @MainActor
    @Test func mergedScenarioPosesClaudeAndCodexAlike() async throws {
        let fixture = DemoFixture.multiFixture(for: .merged)
        let defaults = DemoMemoryDefaults()

        let preferences = Preferences(defaults: defaults)
        let store = UsageStore(
            providers: fixture.providers,
            preferences: preferences,
            accounts: fixture.accounts,
            defaultLoginRecords: fixture.makeDefaultLoginRecordStore()
        )
        await store.refreshAll()

        func signature(_ providerID: ProviderID) -> [RememberedRowSignature] {
            store.displayAccounts(for: providerID).map { row in
                RememberedRowSignature(
                    label: row.label,
                    kind: row.kind,
                    windows: store.snapshot(for: row.key).windows.map { window in
                        let state = window.freshness.isLive ? "live" : "stale"
                        let number = UsagePercentageMode.remaining.roundedPercentage(for: window)
                        return "\(window.kind.shortLabel) \(state) \(number)"
                    }
                )
            }
        }
        let claude = signature(.claude)
        #expect(claude == signature(.codex))
        #expect(claude.map(\.kind) == [.engine, .remembered])
        #expect(claude[0].windows.allSatisfy { $0.contains(" live ") })
        #expect(claude[1].windows.allSatisfy { $0.contains(" stale ") })

    }

}

private struct RememberedRowSignature: Equatable {
    let label: String
    let kind: DisplayAccountKind
    let windows: [String]
}
