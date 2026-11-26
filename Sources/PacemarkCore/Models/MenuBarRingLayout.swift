import Foundation

/// Geometry for one row of proportionally sized menu bar gauges. Measurements are in points.
public struct MenuBarRingLayout: Sendable {
    public static let baseDiameter = 20.5
    private static let inset = 0.5
    private static let labeledInset = 2.0
    private static let baseLabelGap = 1.75

    public let diameter: Double
    public let height: Double
    public let center: Double
    public let labelCenter: Double
    public let labelScale = 1.0
    public let showsLabelBand: Bool
    public let logoBox: Double
    public let stroke: Double
    public let tickOverhang: Double
    public let span = 4 * Double.pi / 3
    public let artworkWidth: Double

    public var besideFontSize: Double { diameter * 0.50 }
    public var innerRadius: Double { diameter / 2 - stroke }
    public var scale: Double { diameter / Self.baseDiameter }
    public var startAngle: Double { -span / 2 }

    public func angle(at fraction: Double) -> Double {
        startAngle + min(1, max(0, fraction)) * span
    }

    /// The widest supported logo needs this much room for its optical size floor.
    private static let minimumInnerRadius = MenuBarGlyph.minimumRingLogoClearance
        / (1 - 1.2 * MenuBarGlyph.maximumNormalizedRingInkRadius)

    public static func stroke(for diameter: Double, ringWidth: Double) -> Double {
        min(ringWidth * diameter / baseDiameter, max(0.25, diameter / 2 - minimumInnerRadius))
    }

    public static func minimumHeight(
        diameter: Double, labelHeight: Double, ringWidth: Double, showsTick: Bool, logoScale: Double
    ) -> Double {
        let stroke = stroke(for: diameter, ringWidth: ringWidth)
        let scale = diameter / baseDiameter
        let tick = showsTick ? 0.75 * scale : 0
        let belowCenter = labelBandOffset(diameter: diameter, stroke: stroke, tick: tick, logoScale: logoScale)
        return ceil(2 * labeledInset + diameter / 2 + tick + belowCenter + labelHeight)
    }

    private static func labelBandOffset(diameter: Double, stroke: Double, tick: Double, logoScale: Double) -> Double {
        // At 120 degrees the round arc cap extends half a stroke below its path endpoint.
        let arcBottom = (diameter - stroke) / 4 + stroke / 2
        let gap = max(labeledInset, baseLabelGap * diameter / baseDiameter)
        return max(arcBottom + gap, (diameter - 2 * stroke) * logoScale / 2 + inset, arcBottom + tick)
    }

    public init(
        requestedDiameter: Double, heightLimit: Double, ringWidth: Double, showsTick: Bool,
        labelWidth: Double, labelHeight: Double, logoScale: Double,
        hasVisibleLabels: Bool = true
    ) {
        let labelWidth = hasVisibleLabels ? labelWidth : 0
        let labelHeight = hasVisibleLabels ? labelHeight : 0
        showsLabelBand = hasVisibleLabels
        let tickAtBase = showsTick ? 0.75 : 0
        let maxDiameter = (heightLimit - 2 * Self.inset) / (1 + 2 * tickAtBase / Self.baseDiameter)
        let requested = min(requestedDiameter, maxDiameter)

        var diameter = requested
        if hasVisibleLabels && Self.minimumHeight(diameter: diameter, labelHeight: labelHeight,
                ringWidth: ringWidth, showsTick: showsTick, logoScale: logoScale) > heightLimit {
            var lower = 0.0
            var upper = diameter
            while upper - lower > 0.001 {
                let candidate = (upper + lower) / 2
                if Self.minimumHeight(diameter: candidate, labelHeight: labelHeight, ringWidth: ringWidth,
                                      showsTick: showsTick, logoScale: logoScale) <= heightLimit {
                    lower = candidate
                } else {
                    upper = candidate
                }
            }
            diameter = lower
        }

        let factor = diameter / Self.baseDiameter
        let stroke = Self.stroke(for: diameter, ringWidth: ringWidth)
        let tick = tickAtBase * factor
        let logo = (diameter - 2 * stroke) * logoScale
        let outerInset = hasVisibleLabels ? Self.labeledInset : Self.inset
        let topHalf = diameter / 2 + tick + outerInset
        let arcEndpoint = diameter / 4 + stroke / 4 + tick
        let offset = Self.labelBandOffset(diameter: diameter, stroke: stroke, tick: tick, logoScale: logoScale)
        let free = max(0, heightLimit - topHalf - offset - labelHeight - outerInset)
        // Share spare height between the outside margins and the inter-line gap.
        let margin = outerInset + free / 3
        self.diameter = diameter
        height = hasVisibleLabels ? heightLimit : min(heightLimit, ceil(2 * topHalf))
        self.center = hasVisibleLabels ? height - topHalf - free / 3
            : height / 2 - (topHalf - arcEndpoint - Self.inset) / 2
        labelCenter = margin + labelHeight / 2
        logoBox = logo
        self.stroke = stroke
        tickOverhang = tick
        artworkWidth = max(diameter + 2 * tick, ceil(labelWidth) + 2 * Self.inset)
    }
}
