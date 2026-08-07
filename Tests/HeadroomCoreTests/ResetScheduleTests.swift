import Foundation
import Testing
@testable import HeadroomCore

struct ResetScheduleTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    @Test func missingAndMalformedLabelsRemainUnresolved() {
        let now = date(2026, 8, 7, 9, 0)

        #expect(
            ClaudeResetNormalizer.schedule(
                label: nil,
                timeZoneIdentifier: nil,
                kind: .fiveHour,
                now: now,
                defaultTimeZone: losAngeles
            ) == .unresolved(.absent)
        )
        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets eventually",
                timeZoneIdentifier: nil,
                kind: .fiveHour,
                now: now,
                defaultTimeZone: losAngeles
            ) == .unresolved(.unparseable)
        )
    }

    @Test func invalidExplicitZoneFailsClosed() {
        let now = date(2026, 8, 7, 9, 0)

        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets 10:10am",
                timeZoneIdentifier: "Not/AZone",
                kind: .fiveHour,
                now: now,
                defaultTimeZone: losAngeles
            ) == .unresolved(.invalidZone)
        )
    }

    @Test func clockAndMonthDayLabelsResolveInSourceZone() {
        let now = date(2026, 8, 7, 9, 0)

        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets 10:10am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .fiveHour,
                now: now,
                defaultTimeZone: TimeZone(secondsFromGMT: 0)!
            ) == .scheduled(date(2026, 8, 7, 10, 10))
        )
        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Aug 9 at 10am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .weekly,
                now: now,
                defaultTimeZone: TimeZone(secondsFromGMT: 0)!
            ) == .scheduled(date(2026, 8, 9, 10, 0))
        )
    }

    @Test func sameYearPastAndImplausibleFutureFailHonestly() {
        let now = date(2026, 8, 7, 9, 0)

        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Aug 6 at 8pm",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .weekly,
                now: now,
                defaultTimeZone: losAngeles
            ) == .unresolved(.elapsed)
        )
        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Sep 1 at 10am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .weekly,
                now: now,
                defaultTimeZone: losAngeles
            ) == .unresolved(.implausible)
        )
    }

    @Test func decemberToJanuaryRollsOnlyInsideWindowHorizon() {
        let now = date(2026, 12, 31, 23, 0)

        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Jan 1 at 1am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .weekly,
                now: now,
                defaultTimeZone: losAngeles
            ) == .scheduled(date(2027, 1, 1, 1, 0))
        )
    }

    @Test func invalidCalendarDatesAndDSTGapsFailClosed() {
        let august = date(2026, 8, 7, 9, 0)
        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Feb 30 at 10am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .weekly,
                now: august,
                defaultTimeZone: losAngeles
            ) == .unresolved(.unparseable)
        )

        let beforeDSTGap = date(2026, 3, 8, 1, 0)
        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Mar 8 at 2:30am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .fiveHour,
                now: beforeDSTGap,
                defaultTimeZone: losAngeles
            ) == .unresolved(.unparseable)
        )
    }

    @Test func yearBoundaryRolloverStillHonorsWindowHorizon() {
        let now = date(2026, 12, 31, 23, 0)

        #expect(
            ClaudeResetNormalizer.schedule(
                label: "Resets Jan 2 at 1am",
                timeZoneIdentifier: "America/Los_Angeles",
                kind: .fiveHour,
                now: now,
                defaultTimeZone: losAngeles
            ) == .unresolved(.implausible)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = losAngeles
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
