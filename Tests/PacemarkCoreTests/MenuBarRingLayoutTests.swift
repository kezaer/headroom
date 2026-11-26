import Foundation
import PacemarkCore
import Testing

struct MenuBarRingLayoutTests {
    private func layout(width: Double, height: Double, limit: Double = 39) -> MenuBarRingLayout {
        MenuBarRingLayout(requestedDiameter: 20.5, heightLimit: limit, ringWidth: 1, showsTick: true,
                          labelWidth: width, labelHeight: height, logoScale: 0.85)
    }

    @Test func largerTextKeepsTheSameGaugeWithoutResizingTheLogo() {
        let small = layout(width: 9, height: 3.5)
        let large = layout(width: 16, height: 5)
        #expect(large.span == small.span)
        #expect(large.diameter == 20.5)
        #expect(large.logoBox == small.logoBox)
        #expect(large.labelScale == 1)
        #expect(large.center - large.logoBox / 2 > large.labelCenter + 2.5)
        #expect(abs(large.angle(at: 0.75) - large.span / 4) < 0.000_001)
    }

    @Test(arguments: [22.0, 39.0])
    func wideLabelsOnlyChangeArtworkWidth(limit: Double) {
        let narrow = layout(width: 0, height: 5, limit: limit)
        let wide = layout(width: 48, height: 5, limit: limit)
        #expect(narrow.diameter == wide.diameter)
        #expect(narrow.center == wide.center)
        #expect(wide.artworkWidth == max(narrow.artworkWidth, ceil(48 * wide.labelScale) + 1))
    }

    @Test(arguments: [22.0, 39.0])
    func labelsClearRoundCapsAtEveryPreset(limit: Double) {
        for icon in 10...16 {
            let diameter = MenuBarRingLayout.baseDiameter * Double(icon) / 10
            for ratio in [0.17, 0.20, 0.23, 0.25] {
                let text = diameter * ratio
                let ring = MenuBarRingLayout(requestedDiameter: diameter, heightLimit: limit,
                    ringWidth: 2.5, showsTick: true, labelWidth: 12, labelHeight: text, logoScale: 0.85)
                let arcBottom = ring.center + cos(ring.startAngle) * (ring.diameter - ring.stroke) / 2 - ring.stroke / 2
                let gap = arcBottom - ring.labelCenter - text / 2
                #expect(gap >= ring.labelCenter - text / 2 - 0.001)
                #expect(gap >= 1.75 * ring.scale - 0.001)
                #expect(ring.labelCenter >= text / 2)
                #expect(ring.center + ring.diameter / 2 + ring.tickOverhang <= limit)
            }
        }
    }

    @Test func actualLogoInkKeepsItsSizeAndClearance() {
        let providers: [ProviderID] = [.claude, .codex, .antigravity, .grok, .cursor, .copilot, .opencode]
        let kinds: [MenuBarGlyphKind] = [.capsule] + providers.map { .providerMark($0) }
        for factor in [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6] {
            for ringWidth in [1.0, 2.5] {
                for logoScale in [0.60, 0.85] {
                    let result = MenuBarRingLayout(
                        requestedDiameter: MenuBarRingLayout.baseDiameter * factor,
                        heightLimit: 39, ringWidth: ringWidth, showsTick: true,
                        labelWidth: 24, labelHeight: 7, logoScale: logoScale)
                    let floor = 1.2 * result.innerRadius
                    for kind in kinds {
                        let size = MenuBarGlyph.ringLogoSize(of: kind, preferredSize: result.logoBox,
                            innerRadius: result.innerRadius, minimumSize: floor, usesRadialInkBounds: true)
                        let largestSide = max(size.width, size.height)
                        #expect(largestSide >= floor - 0.000_001)
                        let extent = largestSide * MenuBarGlyph.normalizedRingInkRadius(of: kind)
                        #expect(result.innerRadius - extent >= 1.5 - 0.000_001)
                    }
                }
            }
        }
    }

    @Test func defaultLogoClearsTheRingWithEveryIconAndTextPreset() {
        let kinds: [MenuBarGlyphKind] = [.capsule, .providerMark(.claude), .providerMark(.codex),
            .providerMark(.antigravity), .providerMark(.grok), .providerMark(.cursor),
            .providerMark(.copilot), .providerMark(.opencode)]
        for factor in [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6] {
            for capHeightRatio in [0.17, 0.20, 0.23, 0.25] {
                let diameter = MenuBarRingLayout.baseDiameter * factor
                let labelHeight = diameter * capHeightRatio
                let layout = MenuBarRingLayout(
                    requestedDiameter: diameter, heightLimit: 39, ringWidth: 1, showsTick: true,
                    labelWidth: 4 * labelHeight, labelHeight: labelHeight, logoScale: 0.70)
                for kind in kinds {
                    let floor = 1.2 * layout.innerRadius
                    let logo = MenuBarGlyph.ringLogoSize(of: kind, preferredSize: layout.logoBox,
                        innerRadius: layout.innerRadius, minimumSize: floor, usesRadialInkBounds: true)
                    let side = max(logo.width, logo.height)
                    #expect(side >= floor - 0.000_001)
                    #expect(layout.innerRadius - side * MenuBarGlyph.normalizedRingInkRadius(of: kind) >= 1.5 - 0.000_001)
                }
            }
        }
    }
    @Test func aRowWithoutVisibleLabelsRetainsTheOpenGauge() {
        func layout(hasLabels: Bool) -> MenuBarRingLayout {
            MenuBarRingLayout(requestedDiameter: 24.6, heightLimit: 39, ringWidth: 1,
                              showsTick: true, labelWidth: 10, labelHeight: 8,
                              logoScale: 0.70, hasVisibleLabels: hasLabels)
        }
        let labeled = layout(hasLabels: true)
        let unlabeled = layout(hasLabels: false)
        #expect(labeled.showsLabelBand)
        #expect(!unlabeled.showsLabelBand)
        #expect(unlabeled.span == 4 * .pi / 3)
        #expect(unlabeled.span == labeled.span)
        #expect(unlabeled.diameter == labeled.diameter)
        #expect(unlabeled.logoBox == labeled.logoBox)
        #expect(unlabeled.height < labeled.height)
        #expect(abs((unlabeled.center + unlabeled.diameter / 2) - (unlabeled.height - unlabeled.center + unlabeled.diameter / 4 + unlabeled.stroke / 4)) <= 1)
    }
}
