import SwiftUI
import AppKit
import HeadroomCore

/// The always-visible menu bar content (R5, UI-03): the compact vessel glyph, with the
/// selected weekly percentage optionally shown beside it. The glyph is tinted by weekly
/// *severity* (healthy → amber → red), not by brand color, so the menu bar means "how
/// close is my weekly allotment to running out" at a glance; a small warning dot appears
/// when a provider needs re-auth, so a dead provider isn't silently invisible. Static
/// only — no pulsing (user's standing rule).
struct MenuBarLabel: View {
    let meters: [MenuBarMeter]
    let showsPercentage: Bool

    var body: some View {
        // Menu bar palette pinned dark (Jul 2026): the renderer draws every color to its
        // dark-scheme value regardless of system appearance, so `Image(nsImage:)` needs no
        // appearance baking — the render is appearance-independent. See MenuBarLabelRenderer.
        let result = MenuBarLabelRenderer.render(meters: meters, showsPercentage: showsPercentage)
        Image(nsImage: result.image)
            .accessibilityLabel(result.accessibilityLabel)
            .help(result.tooltip)
    }
}

@MainActor
struct MenuBarLabelRenderResult {
    let image: NSImage
    let accessibilityLabel: String
    let tooltip: String
}

@MainActor
enum MenuBarLabelRenderer {
    private static let height: CGFloat = 18
    private static let vesselWidth: CGFloat = 11
    private static let vesselTextGap: CGFloat = 7
    private static let meterGapWithPercentage: CGFloat = 16
    private static let meterGapIconOnly: CGFloat = 8
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .medium)

    static func render(meters: [MenuBarMeter], showsPercentage: Bool) -> MenuBarLabelRenderResult {
        let visibleMeters = meters.isEmpty ? [MenuBarMeter(summary: .neutral, fill: nil)] : meters
        let meterGap = showsPercentage ? meterGapWithPercentage : meterGapIconOnly
        let measured = visibleMeters.map { meter -> (meter: MenuBarMeter, textSize: NSSize?) in
            guard showsPercentage, !meter.summary.isNeutral else { return (meter, nil) }
            return (meter, textSize(for: meter.summary.text))
        }
        let width = measured.reduce(CGFloat.zero) { total, item in
            let textWidth = item.textSize.map { vesselTextGap + ceil($0.width) } ?? 0
            let gap = total > 0 ? meterGap : 0
            return total + gap + vesselWidth + textWidth
        }
        let image = NSImage(size: NSSize(width: max(vesselWidth, ceil(width)), height: height), flipped: false) { bounds in
            var x = bounds.minX
            for item in measured {
                if x > bounds.minX { x += meterGap }
                let vessel = VesselGlyph.menuBarImage(
                    fill: item.meter.fill,
                    severity: item.meter.summary.severity,
                    isNeutral: item.meter.summary.isNeutral
                )
                vessel.draw(in: NSRect(x: x, y: 0, width: vesselWidth, height: height))
                if item.meter.summary.needsAttention {
                    // Warning dot pinned to the fixed dark critical red (see menu-bar
                    // palette note below) for consistency with the pinned text/glyph colors.
                    severityColor(for: .critical).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x + vesselWidth - 2, y: height - 5, width: 5, height: 5)).fill()
                }
                x += vesselWidth
                if let textSize = item.textSize {
                    x += vesselTextGap
                    let textHeight = ceil(textSize.height)
                    let rect = NSRect(
                        x: x,
                        y: (height - textHeight) / 2,
                        width: ceil(textSize.width),
                        height: textHeight
                    )
                    item.meter.summary.text.draw(in: rect, withAttributes: [
                        .font: font,
                        .foregroundColor: textColor(for: item.meter.summary)
                    ])
                    x += ceil(textSize.width)
                }
            }
            return true
        }
        image.isTemplate = false
        let accessibilityLabel = accessibilityLabel(for: visibleMeters)
        return MenuBarLabelRenderResult(
            image: image,
            accessibilityLabel: accessibilityLabel,
            tooltip: accessibilityLabel
        )
    }

    private static func textSize(for text: String) -> NSSize {
        (text as NSString).size(withAttributes: [.font: font])
    }

    private static func accessibilityLabel(for meters: [MenuBarMeter]) -> String {
        if meters.count == 1, let summary = meters.first?.summary, summary.needsAttention, summary.isNeutral {
            return "AI usage — a provider needs sign-in"
        }
        let parts = meters.compactMap { meter -> String? in
            guard meter.summary.detail != nil else { return nil }
            return tooltip(for: meter.summary)
        }
        return parts.isEmpty ? "AI usage" : parts.joined(separator: "; ")
    }

    private static func tooltip(for summary: MenuBarSummary) -> String {
        guard let detail = summary.detail else {
            return summary.needsAttention ? "AI usage — a provider needs sign-in" : "AI usage"
        }
        let term = (summary.percentageMode ?? .remaining).term
        let base = summary.isNeutral ? detail : "\(detail), \(summary.text) \(term)"
        return summary.needsAttention ? "\(base), needs sign-in" : base
    }

    private static func textColor(for summary: MenuBarSummary) -> NSColor {
        if !summary.isNeutral, summary.severity != .healthy {
            return severityColor(for: summary.severity)
        }
        return summary.needsAttention ? severityColor(for: .critical) : .white
    }

    /// Menu bar palette pinned dark (Jul 2026). SwiftUI rasterizes `Image(nsImage:)` against
    /// the *system* appearance, so in light mode a dynamic severity `NSColor` bakes to its
    /// light value (dark-brown amber) while a sibling `.labelColor` stays genuinely dynamic
    /// and resolves white against the dark Tahoe menu bar — a mixed palette (brown "38%" next
    /// to white "64%"). The Tahoe menu bar always renders status items on a dark translucent
    /// backplate over effectively any wallpaper, so we pin every menu-bar color to its
    /// dark-scheme value — white ink and the dark severity palette — regardless of system
    /// appearance. This also makes the render appearance-independent (no baking needed).
    private static func severityColor(for severity: UsageSeverity) -> NSColor {
        let rgb = HeadroomSeverityColorValues.color(for: severity, dark: true)
        return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }
}
