import Foundation
import Testing
@testable import HeadroomCore

struct MenuBarGlyphTests {
    @Test func providerMarksHaveVariableWidthsWithinTheCompactCardBudget() {
        let providers: [ProviderID] = [.claude, .codex, .grok, .cursor, .copilot, .opencode, .antigravity]
        let sizes = providers.map { MenuBarGlyph.size(of: .providerMark($0)) }
        #expect(Set(sizes.map(\.width)).count > 1)
        for size in sizes {
            #expect(max(size.width, size.height) <= 15.5)
            #expect(ceil(size.width) <= MenuBarGlyph.maximumWidth(for: .providerIcons))
            #expect(8 + ceil(size.width) + 4 + 33 <= 62)
        }
        #expect(MenuBarGlyph.kind(style: .providerIcons, providerID: .codex, isAutomaticSummary: true) == .capsule)
        #expect(MenuBarGlyph.kind(style: .providerIcons, providerID: .codex, isAutomaticSummary: false) == .providerMark(.codex))
        #expect(MenuBarGlyph.kind(style: .capsules, providerID: .codex, isAutomaticSummary: false) == .capsule)
    }

    @Test func badgesAreShortAndKeepTrailingSubscriptionNumbers() {
        #expect(MenuBarAccountBadge.defaultBadge(for: "Pro100", index: 0) == "100")
        #expect(MenuBarAccountBadge.defaultBadge(for: "Pro200", index: 1) == "200")
        #expect(MenuBarAccountBadge.defaultBadge(for: "Work", index: 0) == "W")
        #expect(MenuBarAccountBadge.defaultBadge(for: "  🟩 ", index: 1) == "2")
        #expect(MenuBarAccountBadge.sanitize("  x+2000 ") == "X200")
        #expect(MenuBarAccountBadge.sanitize("  ") == nil)
    }

    @Test func widthIncludesBothOverhangsAndKeepsTheTextClear() throws {
        let first = MenuBarLabelGeometry.Item(textWidth: 18, needsAttention: true, glyphWidth: 15.5, cornerBadgeWidth: 19)
        let second = MenuBarLabelGeometry.Item(textWidth: nil, needsAttention: true, glyphWidth: 12.5, cornerBadgeWidth: 5)
        let layout = MenuBarLabelGeometry.layout(items: [first, second], showsPercentage: true)
        let initial = try #require(layout.placements.first)
        let trailing = try #require(layout.placements.last)
        let firstBadge = try #require(initial.cornerBadgeX)
        let secondBadge = try #require(trailing.cornerBadgeX)
        let firstText = try #require(initial.textX)
        #expect(firstText >= firstBadge + 19 + MenuBarLabelGeometry.vesselTextGap)
        #expect(trailing.vesselX > firstText + 18)
        #expect(layout.imageWidth >= secondBadge + 5)
        let dot = MenuBarLabelGeometry.attentionDotTrailingEdge(vesselX: trailing.vesselX, glyphWidth: 12.5)
        #expect(layout.imageWidth >= dot)
        let badgeOnly = MenuBarLabelGeometry.layout(
            items: [.init(textWidth: nil, needsAttention: true, glyphWidth: 15.5, cornerBadgeWidth: 19)],
            showsPercentage: false
        )
        #expect(badgeOnly.imageWidth == ceil(firstBadge + 19))
    }

    @Test func emptyTrackHasNeutralAndCriticalContrastInBothAppearances() {
        for isDark in [true, false] {
            let palette = MenuBarPalette(isDarkMenuBar: isDark)
            let neutral = palette.markTrack(for: .healthy, isNeutral: false)
            let critical = palette.markTrack(for: .critical, isNeutral: false)
            #expect(neutral.color == palette.ink.color)
            #expect(critical.color == palette.liquid(for: .critical))
            #expect(neutral.opacity == (isDark ? 0.28 : 0.24))
            #expect(critical.opacity == (isDark ? 0.30 : 0.26))
            #expect(palette.markTrack(for: .critical, isNeutral: true) == neutral)
            let surface = isDark ? 0.15 : 0.93
            let background = HeadroomRGBColor(red: surface, green: surface, blue: surface)
            let empty = composite(neutral, over: background)
            let emptyCritical = composite(critical, over: background)
            #expect(contrast(empty, background) > 1.6)
            #expect(contrast(emptyCritical, background) > 1.2)
            #expect(contrast(critical.color, emptyCritical) > 1.5)
        }
    }

    @Test func refreshingOneSubscriptionDoesNotAnimateTheOtherAccountsPill() {
        let main = AccountKey(providerID: .codex, accountID: AccountID("pro100"))
        let other = AccountKey(providerID: .codex, accountID: AccountID("pro200"))
        let meters = [main, other].map { key in
            MenuBarMeter(
                summary: .init(text: "50%", providerID: .codex, detail: nil, isNeutral: false),
                fill: 0.5, sourceAccountKey: key, glyph: .providerMark(.codex), badge: key == main ? "100" : "200"
            )
        }
        let now = Date()
        let recipe = ReprintRecipe(
            meters: meters, automatic: false, currentMains: [.codex: main], run: nil,
            probingAccounts: [other], probeEndTimes: [:], spendInFlightProviders: [],
            visibleWork: .init(clearedAt: now), now: now
        )
        #expect(recipe.pills.map(\.id) == [main.description, other.description])
        #expect(recipe.pills.map(\.isSloshing) == [false, true])
    }

    private func composite(_ tint: HeadroomTint, over background: HeadroomRGBColor) -> HeadroomRGBColor {
        let opacity = tint.opacity
        return .init(
            red: tint.color.red * opacity + background.red * (1 - opacity),
            green: tint.color.green * opacity + background.green * (1 - opacity),
            blue: tint.color.blue * opacity + background.blue * (1 - opacity)
        )
    }

    private func contrast(_ a: HeadroomRGBColor, _ b: HeadroomRGBColor) -> Double {
        func luminance(_ color: HeadroomRGBColor) -> Double {
            func linear(_ component: Double) -> Double {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }
        let first = luminance(a) + 0.05
        let second = luminance(b) + 0.05
        return max(first, second) / min(first, second)
    }
}
