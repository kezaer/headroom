import Foundation
import Testing
@testable import PacemarkCore

@MainActor
struct MenuBarMeterMigrationTests {
    @Test func accountsPartitionPreservesOrderInsideEachGroup() {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.setSurfaceEnabled(false, for: .claudeSubscription)
        preferences.setSurfaceEnabled(true, for: .codexSubscription)
        let fixture = DemoFixture.multiFixture(for: .multiTwo)
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(store.enabledFirstSettingsOrder == [.codex, .claude])
    }

    @Test(arguments: ["auto", "always", "off"])
    func migrateSavedLabelsOnce(_ mode: String) throws {
        let defaults = DemoMemoryDefaults()
        defaults.set(mode, forKey: "t3.menuBar.accountLabels")
        let preferences = Preferences(defaults: defaults)
        let fixture = DemoFixture.multiFixture(for: .multiTwo)
        var legacy = MenuBarMeterSelection(items: fixture.accounts.map { .init(account: $0.key, label: $0.label) })
        legacy.explicitLabels = nil
        legacy.items[0].label = "CUSTOM"
        preferences.menuBarMeterSelection = legacy
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(store.showMenuBarLabels == (mode != "off"))
        #expect(store.menuBarMeterSelection.items.first?.label == "CUSTOM")
        #expect(store.menuBarMeterSelection.items.dropFirst().allSatisfy { $0.label == "" })
        let row = try #require(store.menuBarMeterRows.first)
        store.setMeterLabel(row.account.account.label, for: row)
        defaults.set("off", forKey: "t3.menuBar.accountLabels")
        let reopened = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(reopened.showMenuBarLabels == (mode != "off"))
        #expect(reopened.menuBarMeterSelection == store.menuBarMeterSelection)
    }

    @Test(arguments: ["popover", "leastLeft"])
    func legacyWindowsDecodeAsAuto(_ name: String) throws {
        let bytes = try JSONSerialization.data(withJSONObject: [name: [:]])
        #expect(try JSONDecoder().decode(MenuBarMeterWindow.self, from: bytes) == .auto)
    }

    @Test(arguments: [true, false])
    func legacyChosenOrderAndAccountsMigrateOnce(showAll: Bool) throws {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.menuBarFillSource = .both
        preferences.menuBarProviderOrder = [.codex, .claude]
        preferences.showAllProviderAccountsInMenuBar = showAll
        preferences.setMenuBarWindowChoice(.closest, for: .claude)
        preferences.setMenuBarWindowChoice(.fiveHour, for: .codex)
        let fixture = DemoFixture.multiFixture(for: .multiTwo)
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        let migrated = try #require(preferences.menuBarMeterSelection)
        #expect(migrated.mode == .chosen)
        #expect(migrated.items.map(\.account.providerID) == (showAll ? [.codex, .claude, .claude] : [.codex, .claude]))
        #expect(migrated.items.first?.window == .limit(WindowKind.fiveHour.persistentID))
        #expect(migrated.items.last?.window == .auto)
        #expect(store.menuBarMeterSelection == migrated)
        preferences.menuBarFillSource = .auto
        let reloaded = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(reloaded.menuBarMeterSelection == migrated)
        #expect(preferences.menuBarProviderOrder == [.codex, .claude])
    }

    @Test func legacyAutomaticSeedsEnabledAccountsAndIgnoresSharedWindow() {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.setInheritedMenuBarWindow(WindowKind.fiveHour.persistentID)
        let fixture = DemoFixture.multiFixture(for: .multiTwo)
        let store = UsageStore(providers: fixture.providers + [
            StubProvider(id: .grok, displayName: "Grok", snapshot: .pending(for: .grok))
        ], preferences: preferences, accounts: fixture.accounts)
        #expect(store.menuBarMeterSelection.mode == .chosen)
        #expect(store.menuBarMeterSelection.items.map(\.account) == store.providerOrder.flatMap { store.accounts(for: $0).map(\.key) })
        #expect(store.menuBarMeterSelection.items.allSatisfy { $0.window == .auto })
        #expect(store.menuBarMeterSelection.hidden.isEmpty)
        #expect(preferences.menuBarWindowChoice(for: .claude) == .fiveHour)
    }

    @Test func undecodableSelectionSurvivesMigrationAndEdits() throws {
        let defaults = DemoMemoryDefaults()
        let future = Data(#"{"mode":"future","items":[],"hidden":[]}"#.utf8)
        defaults.set(future, forKey: Preferences.menuBarMetersKey)
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarFillSource = .claude
        let fixture = DemoFixture.multiFixture(for: .multiTwo)
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        #expect(store.menuBarMeterSelection.mode == .chosen)
        #expect(store.menuBarMeterSelection.items.map(\.account.providerID) == [.claude, .claude])
        #expect(defaults.data(forKey: Preferences.menuBarMetersKey) == future)

        let row = try #require(store.menuBarMeterRows.first)
        store.setMenuBarMode(.tightest)
        store.setMenuBarWindow(.auto, for: row)
        #expect(store.menuBarMeterSelection.mode == .tightest)
        #expect(store.menuBarMeterSelection.items.first?.window == .auto)
        #expect(defaults.data(forKey: Preferences.menuBarMetersKey) == future)
    }

    @Test func initializationPersistsAccountsMissingFromSavedSelection() {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let claude = ProviderAccount.builtIn(for: .claude)
        let codex = ProviderAccount.builtIn(for: .codex)
        preferences.menuBarMeterSelection = .init(items: [.init(account: claude.key, window: .auto)])
        let store = UsageStore(providers: [claude, codex].map {
            StubProvider(id: $0.providerID, displayName: $0.providerID.displayName, snapshot: .pending(for: $0.providerID))
        }, preferences: preferences)
        #expect(store.menuBarMeterSelection.items == [
            .init(account: claude.key, window: .auto), .init(account: codex.key)
        ])
        #expect(preferences.menuBarMeterSelection == store.menuBarMeterSelection)
    }

    @Test func allAccountsMigrateIncludingThoseOfASelectedDisabledProvider() {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.menuBarFillSource = .providers([.grok, .claude])
        preferences.menuBarProviderOrder = [.grok, .claude]
        preferences.showAllProviderAccountsInMenuBar = true
        preferences.setMenuBarWindowChoice(.closest, for: .grok)
        let grok = ProviderAccount.builtIn(for: .grok)
        let claude = [ProviderAccount.builtIn(for: .claude)] + (1...10).map {
            ProviderAccount(id: AccountID("account-\($0)"), providerID: .claude, label: "Account \($0)")
        }
        let projections = [
            DisplayAccountsResolver.resolve(providerID: .claude, engine: claude, remembered: []),
            DisplayAccountsResolver.resolve(providerID: .grok, engine: [grok], remembered: []),
        ]
        let selection = preferences.migrateLegacyMenuBarSelection(
            projections: projections, tracked: claude.map(\.key) + [grok.key], enabled: [.claude])
        #expect(selection.items.map(\.account) == [grok.key] + claude.map(\.key))
        #expect(selection.items.first?.window == .auto)
        #expect(selection.hidden.isEmpty)
        #expect(MenuBarMeterResolver.resolve(selection, projections: projections, enabled: [.claude]).map(\.key)
            == claude.map(\.key))
        #expect(MenuBarMeterResolver.resolve(selection, projections: projections, enabled: [.claude, .grok]).map(\.key)
            == [grok.key] + claude.map(\.key))
    }

    @Test func absentAccountsNeverGetPlaceholderLabels() {
        let defaults = DemoMemoryDefaults()
        let prefs = Preferences(defaults: defaults)
        defaults.set("always", forKey: "t3.menuBar.accountLabels")
        let absent = ProviderAccount.builtIn(for: .claude).key
        prefs.menuBarMeterSelection = .init(hidden: [.init(account: absent, label: nil)])
        let selection = prefs.migrateLegacyMenuBarSelection(projections: [], tracked: [], enabled: [.claude])
        #expect(selection.hidden.first?.label == nil)
    }

    @Test func migratingAllAccountsKeepsBothSlotsOfAMergedMeterShown() {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.menuBarFillSource = .codex
        preferences.showAllProviderAccountsInMenuBar = true
        let builtIn = ProviderAccount.builtIn(for: .codex)
        let work = ProviderAccount(id: AccountID("work"), providerID: .codex, label: "Work")
        let accounts = [builtIn, work]
        let merged = DisplayAccountsResolver.resolve(providerID: .codex, engine: accounts, remembered: [],
                                                     mergeMap: [builtIn.key: work.key])
        let selection = preferences.migrateLegacyMenuBarSelection(
            projections: [merged], tracked: accounts.map(\.key), enabled: [.codex])
        #expect(Set(selection.items.map(\.account)) == Set(accounts.map(\.key)))
        #expect(selection.hidden.isEmpty)
        #expect(MenuBarMeterResolver.resolve(selection, projections: [merged], enabled: [.codex]).map(\.key) == [work.key])
        #expect(selection.items.allSatisfy { $0.label == "" })
        let separate = DisplayAccountsResolver.resolve(providerID: .codex, engine: accounts, remembered: [])
        #expect(MenuBarMeterResolver.resolve(selection, projections: [separate], enabled: [.codex]).allSatisfy { $0.isShown })
    }
    @Test func hiddenAntigravitySurvivesMigrationAndLaneRecovery() throws {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let account = ProviderAccount.builtIn(for: .antigravity)
        let item = MenuBarMeterSelection.Item(account: account.key, window: .limit("Gemini weekly"), label: "Gemini")
        preferences.menuBarMeterSelection = .init(hidden: [item])
        let provider = StubProvider(id: .antigravity, displayName: "Antigravity", snapshot: DemoFixture.antigravitySnapshot)
        for _ in 0..<2 {
            let store = UsageStore(providers: [provider], preferences: preferences)
            store.setSurfaceEnabled(true, for: .antigravitySubscription)
            for snapshot in [DemoFixture.antigravitySnapshot, .pending(for: .antigravity), DemoFixture.antigravitySnapshot] {
                store.snapshots[account.key] = snapshot
                let row = try #require(store.menuBarMeterRows.first)
                #expect(!row.isShown)
                #expect(row.item == item)
                #expect(store.menuBarMeters.isEmpty)
            }
            store.setSurfaceEnabled(false, for: .antigravitySubscription)
        }
    }
}
