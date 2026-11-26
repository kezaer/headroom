import Foundation
import Testing
@testable import PacemarkCore

/// Every single-slot surface headlines the Antigravity row with the least left across both
/// pools, whichever pool it is in. The reading here puts the Other (Claude and GPT) 5-hour row lowest
/// while the Gemini pool comes first, so a surface that took the first row would be wrong.
@Suite(.serialized)
struct AntigravityHeadlineTests {
    /// Friday 25 Sep 2026, 10:00 AM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_790_355_600)
    private let hour: TimeInterval = 60 * 60
    private let day: TimeInterval = 24 * 60 * 60
    private let tightest = WindowKind.other("Other 5h")

    private var snapshot: UsageSnapshot {
        let windows = AntigravityProvider.windows(for: [
            AntigravityBucket(pool: .gemini, window: .weekly, remainingFraction: 0.60, resetsAt: now.addingTimeInterval(5 * day)),
            AntigravityBucket(pool: .gemini, window: .fiveHour, remainingFraction: 0.80, resetsAt: now.addingTimeInterval(3 * hour)),
            AntigravityBucket(pool: .claudeAndGPT, window: .weekly, remainingFraction: 0.50, resetsAt: now.addingTimeInterval(5 * day)),
            AntigravityBucket(pool: .claudeAndGPT, window: .fiveHour, remainingFraction: 0.10, resetsAt: now.addingTimeInterval(2 * hour)),
        ])
        return UsageSnapshot(
            providerID: .antigravity, windows: windows, planLabel: "1,200 credits", capturedAt: now, freshness: .live)
    }

    @Test func theSnapshotLeadsWithTheGeminiPoolSoFirstRowWouldBeWrong() {
        #expect(snapshot.windows.first?.kind == .other("Gemini weekly"))
        #expect(snapshot.windows.map(\.kind).contains(tightest))
    }

    @Test(arguments: [true, false])
    func displayNamesPreserveWindowIDs(_ showsOtherModels: Bool) {
        let visible = AntigravityOtherModels.visibleSnapshot(snapshot, showsOtherModels: showsOtherModels)
        let names = Set(visible.windows.compactMap(\.displayLabel))
        #expect(names == (showsOtherModels ? ["Gemini weekly", "Gemini 5h", "Claude & GPT weekly", "Claude & GPT 5h"] : ["Weekly", "5h"]))
        #expect(visible.windows.allSatisfy { window in snapshot.windows.contains { $0.kind == window.kind } })
    }

    @MainActor
    @Test func tightestMeterRespectsTheAntigravityWindowFilter() async {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.setSurfaceEnabled(true, for: .antigravitySubscription)
        let date = now
        let store = UsageStore(
            providers: [StubProvider(id: .antigravity, displayName: "Antigravity", snapshot: snapshot)],
            preferences: preferences, now: { date }
        )
        await store.refreshAll()
        #expect(store.menuBarMeters.first?.summary.text == "60%")

        store.setShowsAntigravityOtherModels(true)
        #expect(store.menuBarMeters.first?.summary.text == "10%")
    }

}
