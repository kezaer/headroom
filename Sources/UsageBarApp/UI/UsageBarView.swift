import SwiftUI
import UsageBarCore

/// One labeled usage bar showing percent remaining + reset countdown (U7). The bar
/// carries an `accessibilityValue` so VoiceOver reads the remaining percent — a
/// custom bar is invisible to VoiceOver otherwise (design review). `dimmed` renders
/// the stale treatment. The countdown ticks per-minute via the caller's TimelineView
/// `now`, so it never reads frozen.
struct UsageBarView: View {
    let window: UsageWindow
    let accent: Color
    let now: Date
    var dimmed: Bool = false

    private var pct: Int { Int(window.percentRemaining.rounded()) }
    private var fraction: Double { window.percentRemaining / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pct)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            HStack {
                Spacer()
                Text("resets in \(Countdown.string(to: window.resetsAt, now: now))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) usage")
        .accessibilityValue("\(pct) percent remaining, resets in \(Countdown.string(to: window.resetsAt, now: now))")
    }

    private var label: String {
        switch window.kind {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .other(let l): return l
        }
    }
}
