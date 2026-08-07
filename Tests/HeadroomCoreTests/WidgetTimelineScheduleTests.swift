import Foundation
import Testing
@testable import HeadroomCore

struct WidgetTimelineScheduleTests {
    @Test func insertsResetBoundariesAlongsideMinuteCadence() {
        let now = Date(timeIntervalSince1970: 1_000)
        let deadline = now.addingTimeInterval(5 * 60 + 30)
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "claude",
                    displayName: "Claude",
                    planLabel: nil,
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .fiveHour,
                            label: "5h",
                            percentRemaining: 50,
                            utilization: 50,
                            resetSchedule: .scheduled(deadline),
                            resetLabel: nil,
                            severity: .low
                        ),
                    ],
                    renewalDate: nil
                ),
            ]
        )

        let dates = WidgetTimelineSchedule.entryDates(for: envelope, now: now)

        #expect(dates.first == now)
        #expect(dates.contains(deadline.addingTimeInterval(-60)))
        #expect(dates.contains(deadline))
        #expect(dates.contains(deadline.addingTimeInterval(61)))
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
    }

    @Test func ignoresTransitionsOutsideTimelineHorizon() {
        let now = Date(timeIntervalSince1970: 1_000)
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: now,
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "claude",
                    displayName: "Claude",
                    planLabel: nil,
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 50,
                            resetsAt: now.addingTimeInterval(24 * 60 * 60),
                            resetLabel: nil,
                            severity: .low
                        ),
                    ],
                    renewalDate: nil
                ),
            ]
        )

        let dates = WidgetTimelineSchedule.entryDates(for: envelope, now: now)

        #expect(dates.count == 15)
        #expect(dates.last == now.addingTimeInterval(14 * 60))
    }
}
