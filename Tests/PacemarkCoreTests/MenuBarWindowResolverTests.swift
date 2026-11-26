import Foundation
import Testing
@testable import PacemarkCore

struct MenuBarWindowResolverTests {
    @Test func autoPrefersEarlierProjectedRunOutEvenWithMoreQuotaLeft() {
        let now = Date()
        let snapshot = UsageSnapshot(providerID: .claude, windows: [
            .init(kind: .fiveHour, utilization: 60, resetsAt: now.addingTimeInterval(3 * 3600)),
            .init(kind: .weekly, utilization: 80, resetsAt: now.addingTimeInterval(4 * 86400))
        ], planLabel: nil, capturedAt: now, freshness: .live)
        let reading = MenuBarWindowResolver(snapshot: snapshot, choice: .auto, ledgerChoice: .weekly,
                                            percentageMode: .remaining, now: now, showsCodexSparkCounters: false,
                                            showsAntigravityFiveHourWindows: true)
        #expect(reading.selected?.value.window.kind == .fiveHour)
    }

    @Test func autoUsesTheFirstLeastRemainingLimitWhenStaleLimitsTie() {
        let now = Date()
        let windows = [WindowKind.fiveHour, .weekly].map {
            UsageWindow(kind: $0, utilization: 40, resetsAt: now.addingTimeInterval(1000))
        }
        let snapshot = UsageSnapshot.live(.claude, windows: windows).markedStale(.transient("Offline"))
        let result = MenuBarWindowResolver(snapshot: snapshot, choice: .auto, ledgerChoice: .weekly,
            percentageMode: .remaining, now: now, showsCodexSparkCounters: false, showsAntigravityFiveHourWindows: true)
        #expect(result.selected?.value.window.kind == result.ledger.windows.first?.value.window.kind)
        #expect(result.selected != nil)
    }

    @Test func resolvesAutoAndNamedLimits() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let reset = now.addingTimeInterval(8_000)
        let session = UsageWindow(kind: .fiveHour, utilization: 80, resetsAt: reset)
        let week = UsageWindow(kind: .weekly, utilization: 30, resetsAt: reset)
        let unavailableWeek = week.withFreshness(.unavailable(since: now))
        let unavailableSession = session.withFreshness(.unavailable(since: now))
        let weekly = MenuBarMeterWindow.limit(WindowKind.weekly.persistentID)

        let cases: [(choice: MenuBarMeterWindow, windows: [UsageWindow],
                     selected: WindowKind?, reported: WindowKind?, missing: Bool, used: Int?)] = [
            (.auto, [session, week], .fiveHour, nil, false, 80),
            (weekly, [session, week], .weekly, .weekly, false, 30),
            (weekly, [session], .fiveHour, nil, true, 80),
            (weekly, [session, unavailableWeek], .fiveHour, .weekly, true, 80),
            (weekly, [unavailableSession, unavailableWeek], .weekly, .weekly, true, nil),
            (.auto, [unavailableSession, unavailableWeek], nil, nil, false, nil),
        ]
        for entry in cases {
            let snapshot = UsageSnapshot(providerID: .claude, windows: entry.windows,
                                         planLabel: nil, capturedAt: now, freshness: .live)
            let resolution = MenuBarWindowResolver(
                snapshot: snapshot, choice: entry.choice, ledgerChoice: .weekly,
                percentageMode: .used, now: now,
                showsCodexSparkCounters: false, showsAntigravityFiveHourWindows: true
            )
            let context = Comment(rawValue: "\(entry.choice), expected \(String(describing: entry.selected))")
            #expect(resolution.selected?.value.window.kind == entry.selected, context)
            #expect(resolution.reportedLimit?.value.window.kind == entry.reported, context)
            #expect(resolution.isMissingLimit == entry.missing, context)
            #expect(resolution.selected?.value.displayedPercentage == entry.used, context)
        }
    }
}
