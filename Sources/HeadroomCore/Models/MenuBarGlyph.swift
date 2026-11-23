import Foundation

public enum MenuBarIconStyle: String, Sendable, CaseIterable, Identifiable, Codable {
    case providerIcons, capsules
    public var id: String { rawValue }
}

public enum MenuBarGlyphKind: Sendable, Hashable {
    case capsule
    case providerMark(ProviderID)
}

public struct MenuBarGlyphSize: Sendable, Equatable {
    public let width: Double
    public let height: Double
}

public enum MenuBarGlyph {
    public static let maxMarkDimension = 15.5
    public static let capsuleWidth = 11.0

    public static func kind(
        style: MenuBarIconStyle, providerID: ProviderID?, isAutomaticSummary: Bool
    ) -> MenuBarGlyphKind {
        guard style == .providerIcons, !isAutomaticSummary, let providerID else { return .capsule }
        return .providerMark(providerID)
    }

    public static func size(of kind: MenuBarGlyphKind) -> MenuBarGlyphSize {
        guard case .providerMark(let id) = kind else {
            return .init(width: capsuleWidth, height: MenuBarLabelGeometry.height)
        }
        let aspect = HeadroomBrandMark.inkAspect(for: id.raw)
        // Fit the ink box at its own aspect ratio and align to whole or half points.
        let width = maxMarkDimension * min(1, aspect)
        let height = maxMarkDimension / max(1, aspect)
        return .init(width: ceil(width * 2) / 2, height: ceil(height * 2) / 2)
    }

    public static func width(of kind: MenuBarGlyphKind) -> Double { size(of: kind).width }

    public static func maximumWidth(for style: MenuBarIconStyle) -> Double {
        style == .capsules ? capsuleWidth : ceil(maxMarkDimension)
    }
}

public enum MenuBarAccountBadge {
    public static let maxLength = 4

    public static func sanitize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let characters = raw.filter { character in
            guard let byte = character.asciiValue else { return false }
            return (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
        let badge = String(characters.prefix(maxLength)).uppercased()
        return badge.isEmpty ? nil : badge
    }

    public static func defaultBadge(for label: String, index: Int) -> String {
        let digits = String(label.trimmingCharacters(in: .whitespacesAndNewlines).reversed()
            .prefix { $0.asciiValue.map { (48...57).contains($0) } == true }.reversed())
        if let badge = sanitize(digits) { return badge }
        if let letter = sanitize(label)?.first { return String(letter) }
        return String(index + 1)
    }
}

/// Compact, self-contained menu bar summary (R5): the tightest live window plus its
/// provider identity, so the bar means something without opening the popover.
public struct MenuBarSummary: Sendable, Equatable {
    public let text: String            // e.g. "12%"
    public let providerID: ProviderID? // which provider the number is about
    public let detail: String?         // e.g. "Claude 5h"
    public let percentageMode: UsagePercentageMode?
    public let isNeutral: Bool         // true when no live data yet
    /// Health of the shown window — tints the glyph by urgency, not brand (UI-03).
    public let severity: UsageSeverity
    /// Any provider is permanently stale (needs the user to re-auth in its CLI) — the
    /// glyph shows a warning dot so a dead provider isn't invisible in the menu bar.
    public let needsAttention: Bool

    public init(
        text: String,
        providerID: ProviderID?,
        detail: String?,
        isNeutral: Bool,
        percentageMode: UsagePercentageMode? = nil,
        severity: UsageSeverity = .healthy,
        needsAttention: Bool = false
    ) {
        self.text = text
        self.providerID = providerID
        self.detail = detail
        self.isNeutral = isNeutral
        self.percentageMode = percentageMode
        self.severity = severity
        self.needsAttention = needsAttention
    }

    public static let neutral = MenuBarSummary(text: "—", providerID: nil, detail: nil, isNeutral: true)

    /// Copy of this summary with the menu-bar attention flag set — lets the neutral
    /// (no-live-data) case still surface a needs-reauth provider.
    func withAttention(_ flag: Bool) -> MenuBarSummary {
        MenuBarSummary(text: text, providerID: providerID, detail: detail,
                       isNeutral: isNeutral, percentageMode: percentageMode,
                       severity: severity, needsAttention: flag)
    }
}

/// One compact status unit for the menu bar. Automatic mode renders one summary;
/// an explicit provider selection renders one meter per provider.
public struct MenuBarMeter: Sendable, Equatable {
    public let summary: MenuBarSummary
    /// 0...1 fill for the vessel, or nil for the static decorative level.
    public let fill: Double?
    /// KTD13: nil fill also means signed out or decorative; only pending means ghost.
    public let awaitingFirstReading: Bool
    /// U8 distinguishes a fresh first result from a stale result carrying retained windows.
    public let isLiveReading: Bool
    /// Explicit provider pills use this to avoid a first-reading print on Make Main.
    /// Automatic mode has one stable rendering identity and no single source account.
    public let sourceAccountKey: AccountKey?
    public let glyph: MenuBarGlyphKind
    public let badge: String?

    public init(summary: MenuBarSummary, fill: Double?, awaitingFirstReading: Bool = false,
                isLiveReading: Bool = false, sourceAccountKey: AccountKey? = nil,
                glyph: MenuBarGlyphKind = .capsule, badge: String? = nil) {
        self.summary = summary
        self.fill = fill
        self.awaitingFirstReading = awaitingFirstReading
        self.isLiveReading = isLiveReading
        self.sourceAccountKey = sourceAccountKey
        self.glyph = glyph
        self.badge = badge
    }
}
