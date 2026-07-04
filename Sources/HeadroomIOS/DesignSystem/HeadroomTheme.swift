import SwiftUI

enum HeadroomTheme {
    static let tileRadius: CGFloat = 17
    static let entranceAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.34)
    static let valueSpring = Animation.spring(response: 0.3, dampingFraction: 0.9)

    static func providerAccent(for id: String) -> Color {
        switch id {
        case ProviderID.claude.raw: Color(HeadroomBrandColorValues.claude)
        case ProviderID.codex.raw: Color(HeadroomBrandColorValues.codex)
        default: .secondary
        }
    }

    static func providerTextAccent(for id: String, scheme: ColorScheme) -> Color {
        switch (id, scheme) {
        case (ProviderID.claude.raw, .light): Color(red: 0.74, green: 0.36, blue: 0.13)
        case (ProviderID.claude.raw, .dark): Color(red: 0.91, green: 0.56, blue: 0.41)
        case (ProviderID.codex.raw, .light): Color(red: 0.20, green: 0.25, blue: 0.84)
        case (ProviderID.codex.raw, .dark): Color(red: 0.59, green: 0.63, blue: 1.00)
        default: .secondary
        }
    }

    static func severityColor(for severity: WidgetUsageSeverity) -> Color {
        Color(HeadroomSeverityColorValues.color(for: severity))
    }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.037, blue: 0.043) : Color(red: 0.965, green: 0.965, blue: 0.955)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.105, green: 0.108, blue: 0.122) : Color(red: 0.995, green: 0.992, blue: 0.980)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.66)
            : Color(red: 0.22, green: 0.22, blue: 0.24).opacity(0.74)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.92, green: 0.92, blue: 0.96).opacity(0.46)
            : Color(red: 0.22, green: 0.22, blue: 0.24).opacity(0.54)
    }

    static func barTrack(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
}

extension Color {
    init(_ rgb: HeadroomRGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
