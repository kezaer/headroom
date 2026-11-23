import Foundation

/// Where every piece of the rasterized menu bar label lands, and how wide the resulting
/// image has to be.
///
/// PB5: this used to be two loops in `MenuBarLabelRenderer` — one that summed a width and one
/// that drew — and they disagreed. The attention dot is drawn 3pt past the vessel's trailing
/// edge (it is a corner badge, not a column), but only the vessel and its text were measured,
/// so in icon-only mode the dot on the *last* meter had nothing to be drawn into and about
/// 60% of it was clipped away by the image bounds. Anywhere else the dot is covered
/// incidentally — a percentage adds at least `vesselTextGap`, another meter adds at least
/// `meterGapIconOnly`, and both are wider than the overhang — which is why the bug only ever
/// showed on the trailing mark.
///
/// One layout pass now answers both questions, so a mark's drawn extent cannot leave the
/// measured width again. Kept SwiftUI/AppKit-free so `MenuBarLabelGeometryTests` can measure it
/// without a status item.
public enum MenuBarLabelGeometry {
    public static let height: Double = 18
    public static let vesselWidth = MenuBarGlyph.capsuleWidth
    public static let cornerBadgeOverlap: Double = 6
    public static let vesselTextGap: Double = 7
    public static let meterGapWithPercentage: Double = 16
    public static let meterGapIconOnly: Double = 8
    public static let attentionDotDiameter: Double = 5
    /// How far the dot's leading edge sits *inside* the vessel's trailing edge; the rest of
    /// the diameter hangs past it.
    public static let attentionDotInset: Double = 2

    /// The part of a meter this layout cannot derive on its own: whether it draws a
    /// percentage (and how wide that text measured) and whether it carries the attention dot.
    public struct Item: Sendable, Equatable {
        public let glyphWidth: Double
        public let cornerBadgeWidth: Double?
        public let textWidth: Double?
        public let needsAttention: Bool

        public init(
            textWidth: Double?, needsAttention: Bool,
            glyphWidth: Double = vesselWidth, cornerBadgeWidth: Double? = nil
        ) {
            self.glyphWidth = glyphWidth
            self.cornerBadgeWidth = cornerBadgeWidth
            self.textWidth = textWidth
            self.needsAttention = needsAttention
        }
    }

    public struct Placement: Sendable, Equatable {
        /// Leading edge of the vessel glyph.
        public let vesselX: Double
        /// Leading edge of the percentage, when the meter draws one.
        public let textX: Double?
        public let glyphWidth: Double
        public let cornerBadgeX: Double?

        public init(
            vesselX: Double, textX: Double?,
            glyphWidth: Double = vesselWidth, cornerBadgeX: Double? = nil
        ) {
            self.vesselX = vesselX
            self.textX = textX
            self.glyphWidth = glyphWidth
            self.cornerBadgeX = cornerBadgeX
        }
    }

    public struct Layout: Sendable, Equatable {
        public let placements: [Placement]
        /// The widest point anything is drawn to, including the attention dot's overhang.
        public let contentWidth: Double
        /// What the image is actually made at: never narrower than a single vessel.
        public let imageWidth: Double

        public init(placements: [Placement], contentWidth: Double, imageWidth: Double) {
            self.placements = placements
            self.contentWidth = contentWidth
            self.imageWidth = imageWidth
        }
    }

    public static func meterGap(showsPercentage: Bool) -> Double {
        showsPercentage ? meterGapWithPercentage : meterGapIconOnly
    }

    /// The trailing edge of `item`'s attention dot, measured from the vessel's leading edge.
    public static func attentionDotTrailingEdge(vesselX: Double, glyphWidth: Double = vesselWidth) -> Double {
        vesselX + glyphWidth - attentionDotInset + attentionDotDiameter
    }

    /// `vesselTextGap` is overridable only for the Settings pill card's compact step; the
    /// status item always uses the standard gap.
    public static func layout(items: [Item], showsPercentage: Bool, vesselTextGap: Double = vesselTextGap) -> Layout {
        let gap = meterGap(showsPercentage: showsPercentage)
        var cursor: Double = 0
        var extent: Double = 0
        var placements: [Placement] = []
        placements.reserveCapacity(items.count)

        for item in items {
            if cursor > 0 { cursor += gap }
            let vesselX = cursor
            cursor += item.glyphWidth
            let badgeX = item.cornerBadgeWidth.map { width in
                cursor - min(width, cornerBadgeOverlap)
            }
            if let badgeX, let width = item.cornerBadgeWidth {
                cursor = max(cursor, badgeX + width)
            }
            var textX: Double?
            if let textWidth = item.textWidth {
                cursor += vesselTextGap
                textX = cursor
                cursor += textWidth
            }
            placements.append(Placement(
                vesselX: vesselX, textX: textX, glyphWidth: item.glyphWidth, cornerBadgeX: badgeX
            ))
            extent = max(extent, cursor)
            if item.needsAttention {
                extent = max(extent, attentionDotTrailingEdge(vesselX: vesselX, glyphWidth: item.glyphWidth))
            }
        }

        return Layout(
            placements: placements,
            contentWidth: extent,
            imageWidth: items.isEmpty ? vesselWidth : extent.rounded(.up)
        )
    }
}
