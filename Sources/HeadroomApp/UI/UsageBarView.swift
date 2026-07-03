import SwiftUI
import HeadroomCore

/// One labeled usage bar showing percent remaining + reset countdown (U7, UI-01/04).
/// The fill color follows the window's static severity band (green → amber → red) so
/// "how much is left" reads before any number does; the percentage is promoted and
/// labeled "left" to kill the used-vs-remaining ambiguity. The bar carries an
/// `accessibilityValue` so VoiceOver reads the remaining percent — a custom bar is
/// invisible to VoiceOver otherwise (design review). `dimmed` renders the stale
/// treatment: the fill desaturates but the number stays fully legible, because a stale
/// last-known value is exactly what the user opened the app to see. The countdown ticks
/// per-minute via the caller's TimelineView `now`, so it never reads frozen.
struct UsageBarView: View {
    let window: UsageWindow
    let now: Date
    var dimmed: Bool = false

    private var pct: Int { Int(window.percentRemaining.rounded()) }
    private var fraction: Double { window.percentRemaining / 100 }
    private var severity: UsageSeverity { window.severity }

    /// Desaturated grey while stale; the live severity color otherwise.
    private var fillColor: Color {
        dimmed ? Color.secondary.opacity(0.55) : ProviderStyle.severityColor(for: severity)
    }

    /// Prefer the provider's verbatim reset text (Claude) over a computed countdown
    /// (Codex), so the app can't drift from what the source shows.
    private var resetText: String {
        window.resetLabel ?? "resets in \(Countdown.string(to: window.resetsAt, now: now))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !dimmed, severity == .critical {
                    lowChip
                }
                Spacer(minLength: 6)
                Text("\(pct)%")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("left")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 7)
            HStack {
                Spacer()
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage")
        .accessibilityValue("\(pct) percent remaining, \(resetText)")
    }

    /// Small static "Low" flag shown only for the critical band (≤15% left) — a word
    /// earns its place when you're nearly out, not across the whole amber range where
    /// the color alone is the right amount of signal.
    private var lowChip: some View {
        Text("Low")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(ProviderStyle.severityColor(for: severity))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(ProviderStyle.severityColor(for: severity).opacity(0.16), in: Capsule())
    }

    private var label: String {
        switch window.kind {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .other(let l): return l
        }
    }
}
