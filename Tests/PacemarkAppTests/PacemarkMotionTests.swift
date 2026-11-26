import SwiftUI
import Testing
@testable import Pacemark

/// S2A: Reduce Motion is a gentler equivalent, not silence. These pin the resolver's
/// contract so a future call site can't quietly gate a cross-fade into nothing, and S1A's
/// single curve family so the retired `easeOut` can't drift back in.
@MainActor
@Suite(.sharedAppState)
struct PacemarkMotionTests {
    @Test func crossfadeKeepsItsAnimationWhateverReduceMotionSays() {
        #expect(PacemarkMotion.resolved(PacemarkMotion.settle, .crossfade, reduceMotion: true)
            == PacemarkMotion.settle)
        #expect(PacemarkMotion.resolved(PacemarkMotion.settle, .crossfade, reduceMotion: false)
            == PacemarkMotion.settle)
        #expect(PacemarkMotion.resolved(PacemarkMotion.hoverOut, .crossfade, reduceMotion: true)
            == PacemarkMotion.hoverOut)
    }

    @Test func movementIsTheOnlyKindReduceMotionSilences() {
        #expect(PacemarkMotion.resolved(PacemarkMotion.pressDown, .movement, reduceMotion: true) == nil)
        #expect(PacemarkMotion.resolved(PacemarkMotion.pressDown, .movement, reduceMotion: false)
            == PacemarkMotion.pressDown)
        #expect(PacemarkMotion.resolved(PacemarkMotion.valueSpring, .movement, reduceMotion: true) == nil)
    }

    /// S1A/S3A: one curve family, and a press pair that lands inside 100ms then returns on
    /// `settle`. Asserted against literals so a change to the vocabulary is a deliberate edit.
    @Test func thePressAndHoverPairsUseTheHouseCurve() {
        #expect(PacemarkMotion.pressDown == Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.10))
        #expect(PacemarkMotion.settle == Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.20))
        #expect(PacemarkMotion.quickSettle == Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.12))
        #expect(PacemarkMotion.hoverIn == PacemarkMotion.quickSettle)
        #expect(PacemarkMotion.hoverOut == Animation.smooth(duration: 0.18, extraBounce: 0))
        #expect(PacemarkMotion.pressDown != Animation.easeOut(duration: 0.12))
    }

    /// PB12: one press scale for every button style. It was 0.96 in `HoverButtonStyle` and
    /// 0.98 in the three chip/CTA styles, so two neighbouring controls gave different amounts
    /// of give. Pinned to the literal, and to the 0.95 floor below which a press reads as
    /// exaggerated rather than tactile.
    @Test func everyButtonStyleSharesOnePressScale() {
        #expect(PacemarkMotion.pressScale == 0.96)
        #expect(PacemarkMotion.pressScale > 0.95)
        #expect(PacemarkMotion.pressScale < 1)
    }

    /// M2A/S2A: the digit roll is movement, so Reduce Motion swaps the text outright.
    @Test func numericTextCollapsesToAPlainSwapUnderReduceMotion() {
        #expect(PacemarkMotion.numericText(value: 12, reduceMotion: true) == .identity)
        #expect(PacemarkMotion.numericText(value: 12, reduceMotion: false) != .identity)
        #expect(PacemarkMotion.numericText(reduceMotion: true) == .identity)
        #expect(PacemarkMotion.numericText(reduceMotion: false) != .identity)
    }
}
