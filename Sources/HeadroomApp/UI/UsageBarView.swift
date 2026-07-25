import SwiftUI
import HeadroomCore

/// One labeled usage bar showing the selected percentage + reset countdown (U7, UI-01/04).
/// The fill color follows the window's static severity band (green → amber → red) so
/// urgency reads before any number does; the percentage and fill switch together while
/// the adjacent term removes used-vs-left ambiguity. The bar carries an
/// `accessibilityValue` so VoiceOver reads the selected percentage — a custom bar is
/// invisible to VoiceOver otherwise (design review). `dimmed` renders the stale
/// treatment: the fill desaturates but the number stays fully legible, because a stale
/// last-known value is exactly what the user opened the app to see. The countdown ticks
/// per-minute via the caller's TimelineView `now`, so it never reads frozen.
struct UsageBarView: View {
    let window: UsageWindow
    let percentageMode: UsagePercentageMode
    let now: Date
    var dimmed: Bool = false
    /// H3a (Jul 2026 multi-account design review): in the multi-account meter the critical
    /// band drops the "Low" chip and paints the percentage numeral a decoupled critical text
    /// color instead — the band header already carries per-account identity, so the chip's
    /// second urgency mark became redundant. Off by default so the single-account path keeps
    /// the chip exactly as before.
    var chiplessCriticalInk: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    // Whole-point steps only, staying on the family ladder (impeccable audit P3).
    private var labelSize: CGFloat { 13 }
    private var resetSize: CGFloat { 11 }
    private var percentSize: CGFloat { 18 }
    private var termSize: CGFloat { 11 }
    private var barHeight: CGFloat { 8 }
    private var rowSpacing: CGFloat { 5 }

    /// True only when this row should paint its numeral critical instead of chipping it
    /// (H3a): live (not dimmed) critical, in the chipless multi-account path.
    private var usesCriticalInk: Bool { chiplessCriticalInk && !dimmed && severity == .critical }

    private var pct: Int { percentageMode.roundedPercentage(for: window) }
    private var fraction: Double { percentageMode.fraction(for: window) }
    private var severity: UsageSeverity { window.severity }

    /// One spring drives the fill width, its color band, and the rolling percentage so the
    /// bar and its number describe the same value in lockstep. A no-overshoot spring reads
    /// as physical and is distance-aware — a 3% change settles faster than a 40% one — where
    /// the old fixed 450ms `easeOut` felt both slow (Emil: keep UI motion under ~300ms) and
    /// uniform regardless of distance. Nil'd under Reduce Motion so the value snaps instead.
    private var valueAnimation: Animation? { reduceMotion ? nil : HeadroomMotion.valueSpring }

    /// Desaturated grey while stale; the live severity color otherwise.
    private var fillColor: Color {
        dimmed ? Color.secondary.opacity(0.55) : ProviderStyle.severityColor(for: severity, scheme: scheme)
    }

    private var resetText: String {
        Countdown.resetText(resetsAt: window.resetsAt, now: now)
    }

    private func fillWidth(in availableWidth: Double) -> Double {
        guard fraction > 0 else { return 0 }
        return max(8, availableWidth * fraction)
    }

    var body: some View {
        // Prefer the reset inline beside the label; fall back to a sub-line under the bar
        // when the row is too tight to share (Codex's long "GPT-5.3-Codex-Spark …" labels).
        // Fit-aware instead of keyed on window kind, so short labels like "Weekly (Fable)"
        // inline like the standard windows (KTD3).
        ViewThatFits(in: .horizontal) {
            meter(inlineReset: true)
            meter(inlineReset: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage")
        .accessibilityValue("\(pct) percent \(percentageMode.term), \(resetText)")
        .animation(valueAnimation, value: severity)
    }

    private func meter(inlineReset: Bool) -> some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            // Row recipe aligned with the large widget's meter (Jul 2026): 13pt medium
            // label + "· reset" in the shared WCAG-tuned widget grays (system .tertiary
            // sat at ~2.3:1 on the dark tile). Percent stays 18pt medium — the popover's
            // larger canvas earns the bigger numeral; weight ladder 400/500/600/700.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: labelSize, weight: .medium))
                    .foregroundStyle(ProviderStyle.secondaryText(scheme: scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if inlineReset {
                    // fixedSize so the reset reports its full width to ViewThatFits — the
                    // inline candidate must be rejected (dropping to the sub-line) rather
                    // than accepted by silently compressing the reset.
                    Text("· \(resetText)")
                        .font(.system(size: resetSize).monospacedDigit())
                        .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 6)
                if !dimmed, severity == .critical, !chiplessCriticalInk {
                    lowChip
                        .transition(.opacity)
                }
                Text("\(pct)%")
                    // Semibold, matching the widgets' bold numerals — the glance payload
                    // leads the row. H3a: goes critical-ink (chipless multi-account) when the
                    // "Low" chip is suppressed, so urgency still reads on the numeral itself.
                    .font(.system(size: percentSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(usesCriticalInk ? ProviderStyle.criticalText(scheme: scheme) : .primary)
                    .contentTransition(.numericText())
                    .animation(valueAnimation, value: pct)
                Text(percentageMode.term)
                    .font(.system(size: termSize))
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
            bar
            if !inlineReset {
                Text(resetText)
                    .font(.system(size: resetSize).monospacedDigit())
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ProviderStyle.barTrack(scheme: scheme))
                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth(in: geo.size.width))
                    // Width and its severity color ride one spring — a band change only
                    // ever happens when the fraction changes, so both animate together in
                    // the same transaction. The visible payoff of a refresh cycle; not a
                    // loop. (Stale desaturation rides the card's freshness cross-fade.)
                    .animation(valueAnimation, value: fraction)
            }
        }
        .frame(height: barHeight)
    }

    /// Small static "Low" flag shown only for the critical band (≤15% left) — a word
    /// earns its place when you're nearly out, not across the whole amber range where
    /// the color alone is the right amount of signal.
    private var lowChip: some View {
        Text("Low")
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.2)
            .foregroundStyle(ProviderStyle.severityColor(for: severity, scheme: scheme))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(ProviderStyle.severityColor(for: severity, scheme: scheme).opacity(0.16), in: Capsule())
    }

    private var label: String {
        switch window.kind {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .other(let raw): return Self.normalizeOther(raw)
        }
    }

    /// Presentation-only tidy of Codex's constructed window labels so their period suffix
    /// matches the "5-hour"/"Weekly" windows shown above them. The model name is left
    /// verbatim (KTD6) — only the "5h"/"weekly" suffix the provider appends is normalized,
    /// with a middot setting it off from the model. Non-matching labels (Claude's
    /// "Weekly (Fable)") pass through untouched.
    private static func normalizeOther(_ raw: String) -> String {
        if raw.hasSuffix(" weekly") { return "\(raw.dropLast(7)) · Weekly" }
        if raw.hasSuffix(" 5h") { return "\(raw.dropLast(3)) · 5-hour" }
        return raw
    }
}
