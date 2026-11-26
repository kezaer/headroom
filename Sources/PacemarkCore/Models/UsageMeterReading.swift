public struct UsageMeterReading: Sendable, Equatable {
    /// The window as a row renders it: kind, reset schedule, freshness and provenance.
    public let window: UsageWindow
    /// Canonical normalized remaining. Nil only when the source number is not finite; the
    /// row then shows no figure rather than an invented 0% or 100%.
    public let display: UsageDisplayValue?
    /// Source-precision utilization when the source supplied one. Nil for a remaining-only
    /// row, so live-zero inferences that require exact source metadata cannot qualify on a
    /// value fabricated from rounded remaining.
    public let exactUtilization: Double?

    /// Mac: normalized from the actual provider window (decimal subtraction before rounding).
    public init(window: UsageWindow) {
        self.window = window
        self.display = UsageDisplayValue(window: window)
        self.exactUtilization = window.utilization.isFinite ? window.utilization : nil
    }

    /// R2B2: an unavailable row keeps its slot but shows no figure and no fill.
    public var hidesValue: Bool { window.freshness.isUnavailable || display == nil }

    /// Severity from the normalized value. Retained on an unavailable row as hidden metadata;
    /// nil only when there is no finite value to classify.
    public var severity: UsageSeverity? { display?.severity }

    /// The mode's figure from the canonical remaining: Remaining → remaining, Used →
    /// `100 − remaining`. Nil when the row hides its value.
    public func percentage(for mode: UsagePercentageMode) -> Double? {
        guard !hidesValue, let display else { return nil }
        switch mode {
        case .remaining: return display.percentRemaining
        case .used: return 100 - display.percentRemaining
        }
    }

    /// The printed integer — the same `.rounded()` contract `UsagePercentageMode` keeps.
    public func roundedPercentage(for mode: UsagePercentageMode) -> Int? {
        percentage(for: mode).map { Int($0.rounded()) }
    }

    /// The gauge fill, 0 when the row hides its value.
    public func fraction(for mode: UsagePercentageMode) -> Double {
        (percentage(for: mode) ?? 0) / 100
    }

    /// AP1/PA8: critical ink is live-only. A dimmed or retained row keeps its severity as
    /// metadata but never paints it — the reading is no longer one Pacemark stands behind.
    public func usesCriticalInk(dimmed: Bool) -> Bool {
        !dimmed && window.freshness.isLive && severity == .critical
    }
}

public extension UsagePercentageMode {
    /// KTD6.2: the integer every Mac surface prints for a provider window — the popover row's
    /// own `UsageMeterReading` figure — so the menu bar, its arranger and Settings never round
    /// one window two ways. Nil when the row would hide its value (unavailable, non-finite).
    func displayedPercentage(for window: UsageWindow) -> Int? {
        UsageMeterReading(window: window).roundedPercentage(for: self)
    }
}
