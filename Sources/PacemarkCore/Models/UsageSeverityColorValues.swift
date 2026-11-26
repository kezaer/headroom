public extension PacemarkSeverityColorValues {
    static func aheadText(dark: Bool) -> PacemarkRGBColor {
        dark ? PacemarkRGBColor(red: 1, green: 179.0 / 255, blue: 64.0 / 255)
            : PacemarkRGBColor(red: 154.0 / 255, green: 90.0 / 255, blue: 0)
    }

    static func color(for severity: UsageSeverity, dark: Bool) -> PacemarkRGBColor {
        switch severity {
        case .healthy: healthy(dark: dark)
        case .low: low(dark: dark)
        case .critical: critical(dark: dark)
        }
    }

    /// Meter-bar fill tier (see `BrandColorValues.swift`). Text, icons, and the "Low" pill
    /// keep using `color(for:dark:)`.
    static func fill(
        for severity: UsageSeverity,
        dark: Bool,
        increasedContrast: Bool
    ) -> PacemarkRGBColor {
        switch severity {
        case .healthy: healthyFill(dark: dark, increasedContrast: increasedContrast)
        case .low: lowFill(dark: dark, increasedContrast: increasedContrast)
        case .critical: criticalFill(dark: dark, increasedContrast: increasedContrast)
        }
    }
}
