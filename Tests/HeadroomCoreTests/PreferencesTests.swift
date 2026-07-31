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
        prefs.pollIntervalMinutes = 1
        #expect(prefs.pollIntervalMinutes == Preferences.minimumIntervalMinutes)

        // Persisted values from older builds are clamped on read as well as write.
        let defaults = freshDefaults()
        defaults.set(1, forKey: "pollIntervalMinutes")
        #expect(Preferences(defaults: defaults).pollIntervalMinutes == Preferences.minimumIntervalMinutes)
    }

    @Test func pollingEngineUsesTheSameTwoMinuteFloor() {
        #expect(PollingEngine.clampedIntervalMinutes(1) == Preferences.minimumIntervalMinutes)
        #expect(PollingEngine.clampedIntervalMinutes(5) == 5)
    }

    @Test func appearancePreferenceDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.appearancePreference == .system)

        prefs.appearancePreference = .dark
        #expect(prefs.appearancePreference == .dark)

        defaults.set("sepia", forKey: "appearancePreference")
        #expect(prefs.appearancePreference == .system)
    }

    @Test func menuBarPercentageDefaultsOffAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(!prefs.showMenuBarPercentage)
        prefs.showMenuBarPercentage = true
        #expect(prefs.showMenuBarPercentage)
    }

    @Test func usagePercentageModeDefaultsPersistsAndIgnoresUnknownValues() {
        let defaults = freshDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.usagePercentageMode == .remaining)

        prefs.usagePercentageMode = .used
        #expect(prefs.usagePercentageMode == .used)

        defaults.set("spent", forKey: "usagePercentageMode")
        #expect(prefs.usagePercentageMode == .remaining)
    }

    @Test func menuBarFillSourceSupportsBothProviders() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.menuBarFillSource == .none)
        prefs.menuBarFillSource = .both
        #expect(prefs.menuBarFillSource == .both)
    }

    @Test func menuBarWindowSourcesDefaultAndPersistIndependently() {
        let prefs = Preferences(defaults: freshDefaults())

        #expect(prefs.menuBarWindowSource(for: .claude) == .weekly)
        #expect(prefs.menuBarWindowSource(for: .codex) == .weekly)

        prefs.setMenuBarWindowSource(.fiveHour, for: .claude)

        #expect(prefs.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowSource(for: .codex) == .weekly)
    }

    @Test func providerWindowSourcesInheritLegacySharedPreferenceUntilOverridden() {
        let defaults = freshDefaults()
        defaults.set(MenuBarWindowSource.fiveHour.rawValue, forKey: "menuBarWindowSource")
        let prefs = Preferences(defaults: defaults)

        #expect(prefs.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowSource(for: .codex) == .fiveHour)

        prefs.setMenuBarWindowSource(.weekly, for: .codex)

        #expect(prefs.menuBarWindowSource(for: .claude) == .fiveHour)
        #expect(prefs.menuBarWindowSource(for: .codex) == .weekly)
    }

    @Test func widgetsEnabledDefaultsOnAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.widgetsEnabled)
        prefs.widgetsEnabled = false
        #expect(!prefs.widgetsEnabled)
        prefs.widgetsEnabled = true
        #expect(prefs.widgetsEnabled)
    }

    @Test func codexSparkCountersDefaultOffOnBothSurfacesAndPersist() {
        let prefs = Preferences(defaults: freshDefaults())
        // Both surfaces default off (Jul 2026 density audit); Settings opts back in.
        #expect(!prefs.showCodexSparkCountersInApp)
        #expect(!prefs.showCodexSparkCountersInWidgets)

        prefs.showCodexSparkCountersInApp = true
        prefs.showCodexSparkCountersInWidgets = true

        #expect(prefs.showCodexSparkCountersInApp)
        #expect(prefs.showCodexSparkCountersInWidgets)
    }

    @Test func syncToIPhoneDefaultsOffAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(!prefs.syncToIPhoneEnabled)
        prefs.syncToIPhoneEnabled = true
        #expect(prefs.syncToIPhoneEnabled)
        prefs.syncToIPhoneEnabled = false
        #expect(!prefs.syncToIPhoneEnabled)
    }

    @Test func surfacesDefaultToSubscriptionsOnlyAndPersist() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.isSurfaceEnabled(.claudeSubscription))
        #expect(prefs.isSurfaceEnabled(.codexSubscription))
        #expect(!prefs.isSurfaceEnabled(.grokSubscription))
        #expect(!prefs.isSurfaceEnabled(.cursorSubscription))
        #expect(!prefs.isSurfaceEnabled(.anthropicAPI))
        #expect(!prefs.isSurfaceEnabled(.openAIAPI))
        #expect(!prefs.isSurfaceEnabled(.xaiAPI))
        #expect(!prefs.isSurfaceEnabled(.cursorAPI))

        prefs.setSurfaceEnabled(false, for: .claudeSubscription)
        prefs.setSurfaceEnabled(true, for: .openAIAPI)
        #expect(!prefs.isSurfaceEnabled(.claudeSubscription))
        #expect(prefs.isSurfaceEnabled(.openAIAPI))
    }

    @Test func usageSurfaceRawValuesRemainStable() {
        #expect(UsageSurface.allCases.map(\.rawValue) == [
            "claudeSubscription",
            "codexSubscription",
            "grokSubscription",
            "cursorSubscription",
            "anthropicAPI",
            "openAIAPI",
            "xaiAPI",
            "cursorAPI",
        ])
    }

    @Test func apiSpendPeriodDefaultsAndPersists() {
        let prefs = Preferences(defaults: freshDefaults())
        #expect(prefs.apiSpendPeriod == .currentMonth)
        prefs.apiSpendPeriod = .rolling30Days
        #expect(prefs.apiSpendPeriod == .rolling30Days)
    }
}
