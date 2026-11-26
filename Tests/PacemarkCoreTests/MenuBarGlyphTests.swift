import Foundation
import Testing
@testable import PacemarkCore

struct MenuBarGlyphTests {
    @Test func badgesAreShortAndKeepTrailingSubscriptionNumbers() {
        #expect(MenuBarAccountBadge.defaultBadge(for: "Pro100", index: 0) == "100")
        #expect(MenuBarAccountBadge.defaultBadge(for: "Pro200", index: 1) == "200")
        #expect(MenuBarAccountBadge.defaultBadge(for: "Work", index: 0) == "W")
        #expect(MenuBarAccountBadge.defaultBadge(for: "  🟩 ", index: 1) == "2")
        #expect(MenuBarAccountBadge.sanitize("  x+2000 ") == "X200")
        #expect(MenuBarAccountBadge.sanitize("  ") == nil)
    }

    @Test func tickUsesTheSameQuotaDirectionAsTheGaugeFill() throws {
        let now = Date()
        let pace = try #require(MenuBarPace(usedFraction: 0.3, duration: 100, reset: now.addingTimeInterval(75), now: now))
        func meter(_ mode: UsagePercentageMode) -> MenuBarMeter {
            MenuBarMeter(summary: .init(text: "", providerID: .codex, detail: nil, isNeutral: false,
                                        percentageMode: mode), fill: nil, pace: pace)
        }
        #expect(meter(.remaining).expectedFill == 0.75)
        #expect(meter(.used).expectedFill == 0.25)
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
}
