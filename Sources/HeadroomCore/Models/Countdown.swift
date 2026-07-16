import Foundation

/// Pure reset-countdown formatting (U2). Kept out of the views so it is unit-tested
/// and never reimplemented in SwiftUI. Never renders a negative value — a past
/// `resetsAt` reads as "resets now".
public enum Countdown {
    /// Compact countdown from `now` to `resetsAt`, e.g. "4h 59m", "2m", "resets now".
    public static func string(to resetsAt: Date, now: Date) -> String {
        let seconds = resetsAt.timeIntervalSince(now)
        if seconds <= 0 { return "resets now" }

        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    /// Complete provider-independent reset sentence for subscription presentation.
    /// Deliberately derives from `resetsAt` instead of `resetLabel`, so Claude and Codex
    /// use the same compact relative grammar while source labels remain available to
    /// diagnostics and snapshot consumers.
    public static func resetText(resetsAt: Date, now: Date) -> String {
        guard resetsAt > now else { return "Resets now" }
        return "Resets in \(string(to: resetsAt, now: now))"
    }

    /// Relative "updated" label for a captured snapshot, e.g. "just now",
    /// "3 min ago". Returns nil when there is no capture time (`.pending`).
    public static func updatedLabel(capturedAt: Date?, now: Date) -> String? {
        guard let capturedAt else { return nil }
        let seconds = max(0, now.timeIntervalSince(capturedAt))
        let minutes = Int(seconds / 60)
        if minutes <= 0 { return "just now" }
        if minutes == 1 { return "1 min ago" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        return hours == 1 ? "1 hr ago" : "\(hours) hr ago"
    }
}
