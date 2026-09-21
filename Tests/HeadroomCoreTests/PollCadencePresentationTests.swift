import Foundation
import Testing
@testable import HeadroomCore

/// U5 of the 2026-09-19 polling plan: the Settings cadence row is pure presentation over
/// `PollCadence` (AE2, AE3).
struct PollCadencePresentationTests {
    @Test func stretchedLaneNamesBothIntervalsAndTheAccountCount() {
        let cadence = PollCadence(chosenInterval: 2 * 60, effectiveInterval: 4 * 60, accountCount: 40)
        #expect(PollCadencePresentation.row(for: cadence, providerName: "Claude")
            == "Claude: 2\u{00A0}min chosen · about 4\u{00A0}min effective · 40 accounts")
    }

    @Test func aKeptPromiseRendersNoRow() {
        let cadence = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 5 * 60, accountCount: 3)
        #expect(PollCadencePresentation.row(for: cadence, providerName: "Claude") == nil)
        #expect(!cadence.isStretched)
    }

    @Test func httpLaneAtTheEnvelopeRendersNoRow() {
        // The HTTP lane is never stretched, so 20 Codex accounts show nothing extra.
        let cadence = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 5 * 60, accountCount: 20)
        #expect(PollCadencePresentation.row(for: cadence, providerName: "Codex") == nil)
    }

    @Test func fractionalMinutesRoundUpAndOneAccountReadsSingular() {
        let cadence = PollCadence(chosenInterval: 5 * 60, effectiveInterval: 6.2 * 60, accountCount: 1)
        #expect(PollCadencePresentation.row(for: cadence, providerName: "Grok")
            == "Grok: 5\u{00A0}min chosen · about 7\u{00A0}min effective · 1 account")
    }
}
