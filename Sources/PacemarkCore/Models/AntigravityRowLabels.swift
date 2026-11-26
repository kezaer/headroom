import Foundation

/// The stored labels of Antigravity's four rows ("Gemini 5h", "Gemini weekly", "Other 5h",
/// "Other weekly") and their compact short forms, in one platform-neutral place. The provider
/// builds the stored labels, and the compact recipe reads the pool and short form back off them,
/// so each spelling lives only here.
enum AntigravityRowLabels {
    enum Pool: String, CaseIterable {
        case gemini = "Gemini"
        case other = "Other"
    }

    enum Window: String, CaseIterable {
        case fiveHour = "5h"
        case weekly = "weekly"

        var shortName: String {
            switch self {
            case .fiveHour: "5h"
            case .weekly: "wk"
            }
        }
    }

    static func stored(_ pool: Pool, _ window: Window) -> String {
        "\(pool.rawValue) \(window.rawValue)"
    }

    static func short(_ pool: Pool, _ window: Window) -> String {
        "\(pool.rawValue) \(window.shortName)"
    }

    /// The pool and window a stored label names, or nil for any other label.
    static func parse(_ label: String) -> (pool: Pool, window: Window)? {
        for pool in Pool.allCases {
            for window in Window.allCases where label == stored(pool, window) {
                return (pool, window)
            }
        }
        return nil
    }

    static func parse(_ kind: WindowKind) -> (pool: Pool, window: Window)? {
        guard case .other(let label) = kind else { return nil }
        return parse(label)
    }
}

/// Compatibility filter for the retired five-hour preference. The Mac uses
/// `AntigravityOtherModels` at the display boundary.
public enum AntigravityFiveHourWindows {
    public static func isFiveHourRow(_ kind: WindowKind, providerID: ProviderID) -> Bool {
        guard providerID == .antigravity, case .other(let label) = kind else { return false }
        return AntigravityRowLabels.parse(label)?.window == .fiveHour
    }

    /// `windows` without Antigravity's 5-hour rows while the switch is off. The 5-hour rows
    /// are hidden only while some remaining row has a usable number: when every other row is
    /// unavailable or has no finite percentage (or there is none), every row stays.
    public static func visibleWindows(
        _ windows: [UsageWindow], providerID: ProviderID, showsFiveHourWindows: Bool
    ) -> [UsageWindow] {
        guard providerID == .antigravity, !showsFiveHourWindows else { return windows }
        let kept = windows.filter { !isFiveHourRow($0.kind, providerID: providerID) }
        return kept.contains(where: hasUsableNumber) ? kept : windows
    }

    static func hasUsableNumber(_ window: UsageWindow) -> Bool {
        !window.freshness.isUnavailable && window.utilization.isFinite
    }

    public static func visibleSnapshot(_ snapshot: UsageSnapshot, showsFiveHourWindows: Bool) -> UsageSnapshot {
        guard snapshot.providerID == .antigravity, !showsFiveHourWindows else { return snapshot }
        let windows = visibleWindows(
            snapshot.windows, providerID: snapshot.providerID, showsFiveHourWindows: false)
        return windows.count == snapshot.windows.count ? snapshot : snapshot.replacingWindows(windows)
    }
}


/// Presentation filter for the "Show Claude & GPT models" preference.
public enum AntigravityOtherModels {
    public static func displayLabel(for kind: WindowKind, showsOtherModels: Bool) -> String? {
        guard let (pool, window) = AntigravityRowLabels.parse(kind) else { return nil }
        if !showsOtherModels { return window == .weekly ? "Weekly" : "5h" }
        return "\(pool == .gemini ? "Gemini" : "Claude & GPT") \(window.rawValue)"
    }

    static func visibleSnapshot(_ snapshot: UsageSnapshot, showsOtherModels: Bool) -> UsageSnapshot {
        guard snapshot.providerID == .antigravity else { return snapshot }
        return snapshot.replacingWindows(snapshot.windows.compactMap { original in
            if !showsOtherModels && AntigravityRowLabels.parse(original.kind)?.pool == .other { return nil }
            var window = original
            window.displayLabel = displayLabel(for: window.kind, showsOtherModels: showsOtherModels)
            return window
        })
    }
}
