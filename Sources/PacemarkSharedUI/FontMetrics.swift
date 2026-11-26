import CoreText
import Foundation
import SwiftUI
import AppKit

public enum PacemarkFontMetrics {
    /// Distance from the baseline up to the middle of the capitals — the half-height the
    /// eye reads as the type's middle, and what a mixed-size row should centre on.
    public static func capHeightCenter(size: CGFloat, weight: Font.Weight, mono: Bool = false) -> CGFloat {
        capCache.value(for: MetricKey(size: size, weight: weightValue(weight), mono: mono, character: nil)) {
            CTFontGetCapHeight(ctFont(size: size, weight: weight, mono: mono)) / 2
        }
    }

    /// The leading correction to *subtract* from the layout edge so a string's perceived
    /// ink edge — not its glyph box — lands on the content axis. Bearing plus the print
    /// overhang for diagonals and rounds, quantised to the 0.25pt grid a Retina raster can
    /// resolve. Same table and same reasoning as the popover's `OpticalLeading`.
    public static func leadingCorrection(
        for text: String,
        size: CGFloat,
        weight: Font.Weight,
        mono: Bool = false
    ) -> CGFloat {
        guard let first = text.first else { return 0 }
        return bearingCache.value(
            for: MetricKey(size: size, weight: weightValue(weight), mono: mono, character: first)
        ) {
            let font = ctFont(size: size, weight: weight, mono: mono)
            let raw = bearing(of: first, font: font) + overhang(for: first) * size
            return (raw / quantum).rounded() * quantum
        }
    }

    public static func textWidth(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        mono: Bool = false,
        kerning: CGFloat = 0
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = WidthKey(text: text, size: size, weight: weightValue(weight), mono: mono, kerning: kerning)
        return widthCache.value(for: key) {
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont(size: size, weight: weight, mono: mono),
            ]
            if kerning != 0 {
                attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = kerning
            }
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: attributes) as CFAttributedString
            )
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }
    }

    // MARK: - CoreText

    private static let quantum: CGFloat = 0.25

    /// A V W X Y and their lowercase — apex/vertex touches the axis at one point.
    private static let diagonals: Set<Character> = ["A", "V", "W", "X", "Y", "v", "w", "x", "y"]
    /// Curves are tangent to the axis at one point, so they read indented when box-aligned.
    private static let rounds: Set<Character> = [
        "C", "G", "O", "Q", "S",
        "a", "c", "d", "e", "g", "o", "q", "s",
        "0", "3", "6", "8", "9", "(",
    ]

    private static func overhang(for character: Character) -> CGFloat {
        if diagonals.contains(character) { return 0.06 }
        if rounds.contains(character) { return 0.035 }
        return 0
    }

    /// Anything CoreText cannot resolve to exactly one glyph from one UTF-16 unit corrects
    /// by 0 rather than guessing — an unaligned label is a smaller defect than a shifted one.
    private static func bearing(of character: Character, font: CTFont) -> CGFloat {
        var units = Array(String(character).utf16)
        guard units.count == 1 else { return 0 }
        var glyphs = [CGGlyph](repeating: 0, count: 1)
        guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, 1) else { return 0 }
        var rects = [CGRect](repeating: .zero, count: 1)
        CTFontGetBoundingRectsForGlyphs(font, .horizontal, &glyphs, &rects, 1)
        return rects[0].origin.x
    }

    private static func ctFont(size: CGFloat, weight: Font.Weight, mono: Bool) -> CTFont {
        let value = weightValue(weight)
        let platform = mono
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: NSFont.Weight(value))
            : NSFont.systemFont(ofSize: size, weight: NSFont.Weight(value))
        return platform as CTFont
    }

    /// `Font.Weight` is opaque, so the bridge to the platform weight is a lookup rather
    /// than a cast. The raw values are the documented `UIFont.Weight`/`NSFont.Weight`
    /// constants, which are identical on both platforms.
    private static func weightValue(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: -0.8
        case .thin: -0.6
        case .light: -0.4
        case .medium: 0.23
        case .semibold: 0.3
        case .bold: 0.4
        case .heavy: 0.56
        case .black: 0.62
        default: 0
        }
    }

    // MARK: - Cache

    private struct MetricKey: Hashable {
        let size: CGFloat
        let weight: CGFloat
        let mono: Bool
        let character: Character?
    }

    private struct WidthKey: Hashable {
        let text: String
        let size: CGFloat
        let weight: CGFloat
        let mono: Bool
        let kerning: CGFloat
    }

    private final class Cache<Key: Hashable>: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Key: CGFloat] = [:]

        func value(for key: Key, compute: () -> CGFloat) -> CGFloat {
            lock.lock()
            defer { lock.unlock() }
            if let hit = storage[key] { return hit }
            let value = compute()
            if storage.count >= 256 { storage.removeAll(keepingCapacity: true) }
            storage[key] = value
            return value
        }
    }

    private static let capCache = Cache<MetricKey>()
    private static let bearingCache = Cache<MetricKey>()
    private static let widthCache = Cache<WidthKey>()
}

public extension View {
    func capHeightCentered(size: Double, weight: Font.Weight, mono: Bool = false) -> some View {
        alignmentGuide(VerticalAlignment.center) { dimensions in
            dimensions[.firstTextBaseline]
                - PacemarkFontMetrics.capHeightCenter(size: CGFloat(size), weight: weight, mono: mono)
        }
    }

    /// WCL6: pull this text back onto the content axis. The negative leading padding shrinks
    /// the padded view by the correction, so the glyph's perceived edge lands on the layout
    /// edge and the rest of the row travels with it.
    func opticalLeading(_ text: String, size: Double, weight: Font.Weight) -> some View {
        padding(
            .leading,
            -PacemarkFontMetrics.leadingCorrection(for: text, size: CGFloat(size), weight: weight)
        )
    }
}
