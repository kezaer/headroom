import Testing
import Foundation
@testable import HeadroomCore

/// U8 test scenarios: renewal-date round-trip and poll-interval persistence/default.
struct PreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test func renewalDateRoundTrips() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.renewalDate(for: .claude) == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        prefs.setRenewalDate(date, for: .claude)
        #expect(prefs.renewalDate(for: .claude)?.timeIntervalSince1970 == date.timeIntervalSince1970)
        // Per-provider isolation: setting Claude doesn't set Codex.
        #expect(prefs.renewalDate(for: .codex) == nil)
        prefs.setRenewalDate(nil, for: .claude)
        #expect(prefs.renewalDate(for: .claude) == nil)
    }

    @Test func intervalPersistsAndDefaults() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.pollIntervalMinutes == Preferences.defaultIntervalMinutes) // unset default
        prefs.pollIntervalMinutes = 12
        #expect(prefs.pollIntervalMinutes == 12)
        prefs.pollIntervalMinutes = 0            // clamped to >= 1
        #expect(prefs.pollIntervalMinutes >= 1)
    }

    @Test func menuBarPercentageDefaultsOffAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(!prefs.showMenuBarPercentage)
        prefs.showMenuBarPercentage = true
        #expect(prefs.showMenuBarPercentage)
    }
}
