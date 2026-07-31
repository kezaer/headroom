import Foundation
import Testing
@testable import HeadroomCore

struct UsageContinuityCacheTests {
    @Test func roundTripPreservesDisplaySafeWindowsPerAccount() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let primary = AccountKey(providerID: .claude, accountID: .primary)
        let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let reset = Date(timeIntervalSince1970: 3_000_000)
        let capturedAt = Date(timeIntervalSince1970: 2_000_000)

        cache.save(
            .live(.claude, windows: [
                UsageWindow(
                    kind: .other("Weekly (Fable)"),
                    utilization: 39,
                    resetsAt: reset,
                    resetLabel: "Resets Jul 23 at 9:59am",
                    freshness: .stale(observedAt: capturedAt)
                ),
            ], plan: "Max", at: capturedAt),
            for: primary
        )
        cache.save(
            .live(.claude, windows: [
                UsageWindow(kind: .weekly, utilization: 12, resetsAt: reset),
            ], at: capturedAt),
            for: work
        )

        let restored = UsageContinuityCache(defaults: defaults).load()

        #expect(restored[primary]?.windows.map(\.kind) == [.other("Weekly (Fable)")])
        #expect(restored[primary]?.windows.first?.resetLabel == "Resets Jul 23 at 9:59am")
        #expect(restored[primary]?.planLabel == "Max")
        #expect(restored[primary]?.capturedAt == capturedAt)
        #expect(restored[primary]?.windows.first?.freshness == .stale(observedAt: capturedAt))
        #expect(restored[work]?.windows.map(\.kind) == [.weekly])
        if case .stale = restored[primary]?.freshness {} else {
            Issue.record("restored continuity data must never claim to be live")
        }
    }

    @Test func removeDeletesOnlyTheRequestedAccount() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let primary = AccountKey(providerID: .claude, accountID: .primary)
        let work = AccountKey(providerID: .claude, accountID: AccountID("work"))
        let snapshot = UsageSnapshot.live(
            .claude,
            windows: [UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture)]
        )
        cache.save(snapshot, for: primary)
        cache.save(snapshot, for: work)

        cache.remove(for: work)

        #expect(cache.load()[primary] != nil)
        #expect(cache.load()[work] == nil)
    }

    @Test func billingPeriodRestoresWithFutureResetAndOriginalObservation() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let key = AccountKey(providerID: .grok, accountID: .primary)
        let observedAt = Date(timeIntervalSince1970: 2_000_000)
        let duration: TimeInterval = 30 * 24 * 60 * 60
        let resetsAt = observedAt.addingTimeInterval(duration)
        let kind = WindowKind.billingPeriod(label: "Monthly", duration: duration)
        cache.save(
            .live(.grok, windows: [
                UsageWindow(kind: kind, utilization: 25, resetsAt: resetsAt),
            ], at: observedAt),
            for: key
        )

        let cached = UsageContinuityCache(defaults: defaults).load()[key]
        let restored = UsageContinuityPolicy.restoredSnapshot(
            cached,
            for: .grok,
            at: observedAt.addingTimeInterval(2 * 24 * 60 * 60)
        )

        #expect(restored.windows.first?.kind == kind)
        #expect(restored.windows.first?.freshness == .stale(observedAt: observedAt))
        #expect(restored.windows.first?.resetsAt == resetsAt)
    }

    @Test func corruptPersistenceFailsSafe() {
        let defaults = freshDefaults()
        defaults.set(Data("not-json".utf8), forKey: "usageContinuitySnapshots.v1")

        #expect(UsageContinuityCache(defaults: defaults).load().isEmpty)
    }

    @Test func mismatchedProviderKeyIsRejected() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let claudeKey = AccountKey(providerID: .claude, accountID: .primary)
        cache.save(
            .live(.codex, windows: [
                UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture),
            ]),
            for: claudeKey
        )

        #expect(cache.load().isEmpty)
    }

    @Test func failureDetailsAreNeverPersisted() {
        let defaults = freshDefaults()
        let cache = UsageContinuityCache(defaults: defaults)
        let secret = "SECRET_PROVIDER_FAILURE_DETAIL"
        cache.save(
            UsageSnapshot(
                providerID: .claude,
                windows: [UsageWindow(kind: .weekly, utilization: 12, resetsAt: .distantFuture)],
                planLabel: nil,
                capturedAt: Date(),
                freshness: .stale(.transient(secret))
            ),
            for: AccountKey(providerID: .claude, accountID: .primary)
        )

        let encoded = defaults.data(forKey: "usageContinuitySnapshots.v1") ?? Data()
        #expect(!String(decoding: encoded, as: UTF8.self).contains(secret))
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.continuity-cache.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
