import Foundation
import Testing
@testable import HeadroomCore

/// U6 / KTD14 (2026-09-19 sign-in plan): the record is diagnostics-only (R16, R17). These
/// cover the single edge it records, the exclusions that have to survive a relaunch, and
/// the redaction boundary its storage shares with every other Claude diagnostic (R18).
struct SignOutRecordTests {
    private let builtIn = AccountKey(providerID: .claude, accountID: .primary)
    private let extra = AccountKey(providerID: .claude, accountID: AccountID("8f14e45f-ea2b-4c0e-9c1f-2b7a1d6e5c30"))

    private func freshDefaults(_ suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func signedInThenSignedOutRecordsOneEventStampedWithDetectionTime() {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 1_000))
        let record = SignOutRecord(defaults: freshDefaults("headroom.signout.\(UUID().uuidString)"), now: clock.now)

        record.noteSignedIn(builtIn)
        clock.set(Date(timeIntervalSince1970: 2_500))
        record.noteSignedOut(builtIn)

        #expect(record.events.map(\.account) == [builtIn])
        #expect(record.events.map(\.detectedAt) == [Date(timeIntervalSince1970: 2_500)])
        #expect(!record.isLastKnownSignedIn(builtIn))
    }

    @Test func repeatedSignedOutObservationsRecordNothingMore() {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 1_000))
        let record = SignOutRecord(defaults: freshDefaults("headroom.signout.\(UUID().uuidString)"), now: clock.now)

        record.noteSignedIn(builtIn)
        record.noteSignedOut(builtIn)
        clock.set(Date(timeIntervalSince1970: 9_000))
        record.noteSignedOut(builtIn)
        record.noteSignedOut(builtIn)

        #expect(record.events.count == 1)
        #expect(record.events.first?.detectedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func signedOutFirstObservationWithNoPersistedFlagRecordsNothing() {
        let record = SignOutRecord(
            defaults: freshDefaults("headroom.signout.\(UUID().uuidString)"),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        record.noteSignedOut(builtIn)

        #expect(record.events.isEmpty)
    }

    /// R16's closed-while-signed-out case: the flag is what makes it one event at the next
    /// launch instead of one on every launch.
    @Test func persistedFlagPlusSignedOutFirstObservationAfterRelaunchRecordsExactlyOne() {
        let defaults = freshDefaults("headroom.signout.\(UUID().uuidString)")
        SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 1_000) }).noteSignedIn(builtIn)

        let afterRelaunch = SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 5_000) })
        #expect(afterRelaunch.isLastKnownSignedIn(builtIn))
        afterRelaunch.noteSignedOut(builtIn)

        let afterSecondRelaunch = SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 9_000) })
        afterSecondRelaunch.noteSignedOut(builtIn)

        #expect(afterSecondRelaunch.events.map(\.detectedAt) == [Date(timeIntervalSince1970: 5_000)])
    }

    @Test func clearingTheFlagSuppressesTheNextSignedOutObservation() {
        let record = SignOutRecord(
            defaults: freshDefaults("headroom.signout.\(UUID().uuidString)"),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        record.noteSignedIn(builtIn)
        record.clearLastKnownSignedIn(for: builtIn)
        record.noteSignedOut(builtIn)

        #expect(!record.isLastKnownSignedIn(builtIn))
        #expect(record.events.isEmpty)
    }

    @Test func purgingOneAccountLeavesEveryOtherAccountsEvents() {
        let record = SignOutRecord(
            defaults: freshDefaults("headroom.signout.\(UUID().uuidString)"),
            now: { Date(timeIntervalSince1970: 1_000) }
        )

        record.noteSignedIn(builtIn)
        record.noteSignedOut(builtIn)
        record.noteSignedIn(extra)
        record.noteSignedOut(extra)

        record.purgeEvents(for: extra)

        #expect(record.events.map(\.account) == [builtIn])
        #expect(record.events(for: extra).isEmpty)
        #expect(!record.isLastKnownSignedIn(extra))
    }

    @Test func listDropsItsOldestEntryPastTheBound() {
        let clock = MutableDateSource(Date(timeIntervalSince1970: 0))
        let record = SignOutRecord(defaults: freshDefaults("headroom.signout.\(UUID().uuidString)"), now: clock.now)

        for index in 0...SignOutRecord.maxEvents {
            clock.set(Date(timeIntervalSince1970: TimeInterval(index)))
            record.noteSignedIn(builtIn)
            record.noteSignedOut(builtIn)
        }

        #expect(record.events.count == SignOutRecord.maxEvents)
        // The first observation (t=0) is gone; the list stays oldest-first.
        #expect(record.events.first?.detectedAt == Date(timeIntervalSince1970: 1))
        #expect(record.events.last?.detectedAt == Date(timeIntervalSince1970: TimeInterval(SignOutRecord.maxEvents)))
    }

    @Test func encodedStorageCarriesNoIdentityOrCLIOutput() {
        let suite = "headroom.signout.\(UUID().uuidString)"
        let defaults = freshDefaults(suite)
        let record = SignOutRecord(defaults: defaults, now: { Date(timeIntervalSince1970: 1_000) })

        record.noteSignedIn(extra)
        record.noteSignedOut(extra)

        let stored = (defaults.persistentDomain(forName: suite) ?? [:]).values
            .map { value -> String in
                if let data = value as? Data { return String(decoding: data, as: UTF8.self) }
                return String(describing: value)
            }
            .joined(separator: "\n")

        #expect(!stored.isEmpty)
        for forbidden in [
            "example@example.com",
            "Example Org",
            "acct_01HZZZ",
            "Current week (all models)",
            "/Users/example/.claude-extra",
            "sk-ant-secret",
        ] {
            #expect(!stored.contains(forbidden))
        }
    }

    @Test func diagnosticSectionPrintsCountAndTimestampsPerAccountOnly() {
        let output = ClaudeCapabilityDiagnostic.lines(
            account: .extra,
            versionBand: .printSupported,
            outcome: .loginRequired,
            events: [],
            signOutEvents: [
                SignOutEvent(account: builtIn, detectedAt: Date(timeIntervalSince1970: 10)),
                SignOutEvent(account: extra, detectedAt: Date(timeIntervalSince1970: 20)),
                SignOutEvent(account: builtIn, detectedAt: Date(timeIntervalSince1970: 30)),
            ],
            now: Date(timeIntervalSince1970: 100)
        ).joined(separator: "\n")

        #expect(output.contains("sign-out-events=3"))
        #expect(output.contains("sign-out-account=claude/primary count=2"))
        #expect(output.contains("sign-out-account=claude/\(extra.accountID.raw) count=1"))
        #expect(output.contains("sign-out-detected-at=1970-01-01T00:00:10Z"))
        #expect(output.contains("sign-out-detected-at=1970-01-01T00:00:20Z"))
        #expect(output.contains("sign-out-detected-at=1970-01-01T00:00:30Z"))

        for forbidden in [
            "example@example.com",
            "Example Org",
            "acct_01HZZZ",
            "Current week (all models)",
            "/Users/example/.claude-extra",
            "sk-ant-secret",
        ] {
            #expect(!output.contains(forbidden))
        }
    }

    @Test func diagnosticSectionStillReportsAnEmptyRecord() {
        let output = ClaudeCapabilityDiagnostic.lines(
            account: .builtIn,
            versionBand: .unknown,
            outcome: .available,
            events: [],
            now: Date(timeIntervalSince1970: 100)
        ).joined(separator: "\n")

        #expect(output.contains("sign-out-events=0"))
    }
}
