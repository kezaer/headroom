import Foundation
import Testing
@testable import PacemarkCore

@MainActor
struct MenuBarMeterSelectionTests {
    @Test func futureWindowPreservesTheStoredList() throws {
        let prefs = Preferences(defaults: DemoMemoryDefaults())
        let account = ProviderAccount.builtIn(for: .codex)
        let item = MenuBarMeterSelection.Item(account: account.key, window: .auto, label: " Account 2 ")
        let saved = MenuBarMeterSelection(items: [item])
        let bytes = try JSONEncoder().encode(saved)
        let future = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #""auto""#, with: #""future""#)
        prefs.defaults.set(Data(future.utf8), forKey: "t3.menuBar.meters.v1")
        #expect(prefs.menuBarMeterSelection == saved)
        #expect(item.label == "Account")
    }

    @Test func newAccountsAppendAcrossProvidersAndThereIsNoCap() {
        let old = (1...12).map { account(.claude, "account-\($0)") }
        let offMain = account(.codex, "main")
        let newAccount = account(.codex, "new")
        let visible = DisplayAccountsResolver.resolve(providerID: .claude, engine: old, remembered: [])
        let other = DisplayAccountsResolver.resolve(providerID: .codex, engine: [offMain, newAccount], remembered: [])
        var selection = MenuBarMeterSelection(items: old.map { .init(account: $0.key) }, hidden: [.init(account: offMain.key)])
        selection.appendNewAccounts((old + [offMain, newAccount]).map(\.key))
        #expect(selection.items.map(\.account) == (old + [newAccount]).map(\.key))
        #expect(MenuBarMeterResolver.resolve(selection, projections: [visible, other], enabled: [.claude])
            .map(\.key) == old.map(\.key))
        let rows = MenuBarMeterResolver.resolve(selection, projections: [visible, other], enabled: [.claude, .codex])
        #expect(rows.filter(\.isShown).map(\.key) == (old + [newAccount]).map(\.key))
        #expect(rows.last?.key == offMain.key)
        #expect(rows.last?.isShown == false)
    }

    @Test func addingAnAccountToAnOffProviderQueuesItsMeterAtTheEnd() throws {
        let defaults = DemoMemoryDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarFillSource = .claude
        func provider(_ account: ProviderAccount) -> DemoUsageProvider {
            DemoUsageProvider(id: account.providerID, displayName: account.providerID.displayName,
                              snapshot: .pending(for: account.providerID), accountID: account.id)
        }
        let claude = ProviderAccount.builtIn(for: .claude)
        let grok = ProviderAccount.builtIn(for: .grok)
        let store = UsageStore(providers: [provider(claude), provider(grok)], preferences: preferences,
                               accountRegistry: AccountRegistry(defaults: defaults), accountStorage: DemoAccountStorage(),
                               providerFactory: provider)
        let added = try #require(store.addAccount(for: .grok, label: "Work"))
        #expect(store.menuBarMeterRows.map(\.key) == [claude.key])
        #expect(store.menuBarMeterSelection.items.map(\.account) == [claude.key, added.key])
        store.setSurfaceEnabled(true, for: .grokSubscription)
        #expect(store.menuBarMeterRows.filter(\.isShown).map(\.key) == [claude.key, added.key, grok.key])
        let main = try #require(store.menuBarMeterRows.first { $0.key == grok.key })
        store.setMenuBarShown(false, for: main)
        store.setSurfaceEnabled(false, for: .grokSubscription)
        store.setSurfaceEnabled(true, for: .grokSubscription)
        #expect(store.menuBarMeterRows.filter(\.isShown).map(\.key) == [claude.key, added.key])
        #expect(store.menuBarMeterSelection.hidden.contains { $0.account == grok.key })
    }

    @Test func mergesResolveToOneMeterAndRemovedAccountsStayOut() {
        let builtIn = ProviderAccount.builtIn(for: .codex)
        let extra = account(.codex, "extra")
        let removed = account(.codex, "removed")
        let projection = DisplayAccountsResolver.resolve(providerID: .codex, engine: [builtIn, extra], remembered: [],
                                                         mergeMap: [builtIn.key: extra.key])
        let selection = MenuBarMeterSelection(items: [
            .init(account: builtIn.key, window: .auto), .init(account: removed.key), .init(account: extra.key)
        ])
        let rows = MenuBarMeterResolver.resolve(selection, projections: [projection], enabled: [.codex])
        #expect(rows.map(\.key) == [extra.key])
        #expect(rows.first?.item.window == .auto)
    }

    @Test func mergedMeterEditsCoverBothAccounts() throws {
        let builtIn = ProviderAccount.builtIn(for: .codex)
        let work = account(.codex, "work")
        let studio = account(.codex, "studio")
        let claude = ProviderAccount.builtIn(for: .claude)
        let accounts = [builtIn, work, studio, claude]
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let store = UsageStore(providers: accounts.map(provider), preferences: preferences, accounts: accounts)
        store.displayMergeMaps[.codex] = [builtIn.key: work.key]
        store.menuBarMeterSelection = .init(
            items: [builtIn, claude, work, studio].map { .init(account: $0.key) },
            hidden: [.init(account: builtIn.key), .init(account: work.key)]
        )
        let row = try #require(store.menuBarMeterRows.first)
        #expect(row.key == work.key)

        store.setMeterLabel("Account 2", for: row)
        store.setMenuBarWindow(.auto, for: row)
        let mergeKeys = Set([builtIn.key, work.key])
        let selection = store.menuBarMeterSelection
        #expect((selection.items + selection.hidden).filter { mergeKeys.contains($0.account) }
            .allSatisfy { $0.window == .auto && $0.label == "Account" })

        store.moveMenuBarMeter(work.key, by: 2)
        #expect(store.menuBarMeterRows.filter(\.isShown).map(\.key) == [claude.key, studio.key, work.key])
        store.resetMenuBarOrder()
        #expect(store.menuBarMeterRows.filter(\.isShown).map(\.key) == [work.key, studio.key, claude.key])
        #expect(store.menuBarMeterSelection.items.map(\.account) == [builtIn.key, work.key, studio.key, claude.key])

        store.setMenuBarShown(false, for: row)
        #expect(store.menuBarMeterSelection.hidden.map(\.account) == [builtIn.key, work.key])
        let hidden = try #require(store.menuBarMeterRows.first { $0.key == work.key })
        #expect(!hidden.isShown)
        #expect(hidden.item.account == builtIn.key)
        #expect(hidden.item.window == .auto)
        #expect(hidden.item.label == "Account")

        let weekly = MenuBarMeterWindow.limit(WindowKind.weekly.persistentID)
        store.setMenuBarWindow(weekly, for: hidden)
        #expect(store.menuBarMeterSelection.hidden.map(\.window) == [weekly, weekly])
        store.setMenuBarShown(true, for: hidden)
        #expect(store.menuBarMeterSelection.hidden.isEmpty)
        #expect(store.menuBarMeterRows.filter(\.isShown).map(\.key) == [studio.key, claude.key, work.key])
        store.displayMergeMaps[.codex] = nil
        #expect(store.menuBarMeterRows.suffix(2).map(\.item.window) == [weekly, weekly])
        #expect(store.menuBarMeterRows.allSatisfy { $0.isShown })
        #expect(preferences.menuBarMeterSelection == store.menuBarMeterSelection)
    }

    @Test func settingAWindowOnASynthesizedHiddenRowPersistsIt() throws {
        let claude = ProviderAccount.builtIn(for: .claude)
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let store = UsageStore(providers: [provider(claude)], preferences: preferences)
        store.menuBarMeterSelection = .init()
        let row = try #require(store.menuBarMeterRows.first)
        #expect(!row.isShown)

        store.setMenuBarWindow(.auto, for: row)
        #expect(preferences.menuBarMeterSelection?.hidden == [.init(account: claude.key, window: .auto)])
        store.setMenuBarShown(true, for: row)
        #expect(store.menuBarMeterRows.first?.item.window == .auto)
        #expect(store.menuBarMeterRows.first?.isShown == true)
    }

    @Test func meterOrderAndOverridesSurviveAccountChurn() async throws {
        let defaults = DemoMemoryDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarFillSource = .both
        let claude = ProviderAccount.builtIn(for: .claude)
        let codex = ProviderAccount.builtIn(for: .codex)
        let store = UsageStore(
            providers: [provider(claude), provider(codex)], preferences: preferences,
            accountRegistry: AccountRegistry(defaults: defaults), accountStorage: DemoAccountStorage(),
            providerFactory: provider
        )
        let work = try #require(store.addAccount(for: .claude, label: "Work"))
        let workRow = try #require(store.menuBarMeterRows.first { $0.key == work.key })
        store.setMenuBarWindow(.auto, for: workRow)
        store.setMenuBarBadge("WK", for: work.key)
        #expect(store.automaticMenuBarBadge(for: work.key) == "W")
        #expect(store.menuBarBadge(for: work.key) == "WK")
        store.moveMenuBarMeter(work.key, by: -1)
        let ordered = store.menuBarMeterSelection
        #expect(store.promoteAccount(work.key))
        #expect(store.displayPrimaryKey(for: .claude) == work.key)
        #expect(store.menuBarMeterSelection == ordered)

        store.setSurfaceEnabled(false, for: .claudeSubscription)
        #expect(store.menuBarMeterRows.map(\.key) == [codex.key])
        store.setSurfaceEnabled(true, for: .claudeSubscription)
        #expect(store.menuBarMeterRows.map(\.item) == ordered.items)
        #expect(store.menuBarLabelOverride(for: work.key) == "WK")

        store.setMenuBarShown(false, for: workRow)
        #expect(store.menuBarMeterSelection.hidden.map(\.account).contains(work.key))
        #expect(await store.removeAccount(work.key) == .removed)
        let saved = try #require(preferences.menuBarMeterSelection)
        #expect(saved.items.map(\.account) == [claude.key, codex.key])
        #expect(saved.hidden.isEmpty)
        #expect(store.menuBarMeterRows.map(\.key) == [claude.key, codex.key])
    }

    @Test func rememberedAccountsRejectMenuBarEdits() throws {
        let claude = ProviderAccount.builtIn(for: .claude)
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.menuBarFillSource = .claude
        let store = UsageStore(providers: [provider(claude)], preferences: preferences)
        store.rememberedAccountRows[.claude] = [
            .init(id: AccountID("remembered"), providerID: .claude, label: "Former login",
                  email: nil, snapshot: nil, lastReadAt: nil, isHidden: false)
        ]
        let row = try #require(store.menuBarMeterRows.first { $0.account.isRemembered })
        let original = store.menuBarMeterSelection
        store.setMenuBarShown(true, for: row)
        store.setMeterLabel("blocked", for: row)
        store.setMenuBarWindow(.auto, for: row)
        store.moveMenuBarMeter(row.key, by: -1)
        #expect(!row.isShown)
        #expect(store.menuBarMeterSelection == original)
        #expect(store.menuBarMeters.map(\.sourceAccountKey) == [claude.key])
    }

    @Test func choosingHidingAndReorderingAffectsOnlyTheMenuBarAndPersists() throws {
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.menuBarFillSource = .both
        let fixture = DemoFixture.multiFixture(for: .multiTwo)
        let store = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        let original = store.menuBarMeterRows
        let first = try #require(original.first)
        let last = try #require(original.last)
        store.setMenuBarWindow(.auto, for: first)
        store.setMeterLabel("Account 2", for: first)
        store.moveMenuBarMeter(last.key, by: -2)
        #expect(store.menuBarMeterRows.first?.key == last.key)
        for row in store.menuBarMeterRows { store.setMenuBarShown(false, for: row) }
        #expect(store.menuBarMeters.isEmpty)
        #expect(store.displayAccounts(for: first.key.providerID).contains { $0.key == first.key })
        let reloaded = UsageStore(providers: fixture.providers, preferences: preferences, accounts: fixture.accounts)
        let hidden = try #require(reloaded.menuBarMeterRows.first { $0.key == first.key })
        #expect(hidden.item.window == .auto)
        #expect(hidden.item.label == "Account")
        #expect(!hidden.isShown)
        reloaded.setMenuBarShown(true, for: hidden)
        #expect(reloaded.menuBarMeters.first?.sourceAccountKey == first.key)
    }

    @Test func tightestAndNextResetUseTheSameReadingsAsThePopover() async throws {
        let now = Date()
        let claudeWindow = UsageWindow(kind: .fiveHour, utilization: 65, resetsAt: now.addingTimeInterval(9_000))
        let other = UsageWindow(kind: .fiveHour, utilization: 90, resetsAt: now.addingTimeInterval(1_700))
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let store = UsageStore(providers: [
            StubProvider(id: .claude, displayName: "Claude", snapshot: .live(.claude, windows: [claudeWindow])),
            StubProvider(id: .codex, displayName: "Codex", snapshot: .live(.codex, windows: [other])),
        ], preferences: preferences, now: { now })
        await store.refreshAll()
        store.setMenuBarMode(.tightest)
        let candidates = store.summaryCandidates(at: now)
        let summary = PopoverSummaryRecipe(slots: [.tightest, .nextReset], candidates: candidates, spend: [], now: now)
        guard case .tightest(let tightest) = try #require(summary.tiles.first),
              case .nextReset(let next) = try #require(summary.tiles.last) else {
            Issue.record("Expected Tightest and Next reset")
            return
        }
        #expect(tightest.candidate.key.providerID == .claude)
        #expect(next.candidate.key.providerID == .codex)
        #expect(store.menuBarMeters.first?.sourceAccountKey == tightest.candidate.key)
        #expect(store.menuBarMeters.first?.summary.text == "35%")
    }

    @Test func tightestFallsBackToTheLeastLeftRetainedWindowThenToStatus() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let claude = ProviderAccount.builtIn(for: .claude)
        let codex = ProviderAccount.builtIn(for: .codex)
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        let store = UsageStore(providers: [provider(claude), provider(codex)], preferences: preferences, now: { now })
        store.setMenuBarMode(.tightest)
        let pending = try #require(store.menuBarMeters.first)
        #expect(pending.sourceAccountKey == claude.key)
        #expect(pending.awaitingFirstReading)

        let reset = now.addingTimeInterval(7_000)
        let week = UsageWindow(kind: .weekly, utilization: 40, resetsAt: reset)
        let session = UsageWindow(kind: .fiveHour, utilization: 90, resetsAt: reset)
        store.snapshots[claude.key] = .live(.claude, windows: [week]).markedStale(.transient("Offline"))
        store.snapshots[codex.key] = .live(.codex, windows: [week, session]).markedStale(.transient("Offline"))
        let stale = try #require(store.menuBarMeters.first)
        #expect(stale.sourceAccountKey == codex.key)
        #expect(stale.summary.text == "10%")
        #expect(!stale.isLiveReading)
        #expect(!stale.awaitingFirstReading)

        store.snapshots[claude.key] = .stale(for: .claude, reason: .transient("Offline"))
        store.snapshots[codex.key] = .stale(for: .codex, reason: .notLoggedIn("Sign in"))
        let attention = try #require(store.menuBarMeters.first)
        #expect(attention.sourceAccountKey == codex.key)
        #expect(attention.summary.needsAttention)
        #expect(attention.fill == nil)
    }

    @Test func tightestShowsAnUnusedAntigravityPoolAfterItsReportedReset() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let account = ProviderAccount.builtIn(for: .antigravity)
        let preferences = Preferences(defaults: DemoMemoryDefaults())
        preferences.setSurfaceEnabled(true, for: .antigravitySubscription)
        let store = UsageStore(providers: [provider(account)], preferences: preferences, now: { now })
        store.setMenuBarMode(.tightest)
        let pool = UsageWindow(kind: .other("Gemini weekly"), utilization: 0, resetsAt: now.addingTimeInterval(-30))
        store.snapshots[account.key] = .live(.antigravity, windows: [pool])
        let meter = try #require(store.menuBarMeters.first)
        #expect(PopoverSummaryRecipe.tightest(candidates: store.summaryCandidates(at: now), now: now)?.countdown == nil)
        #expect(meter.sourceAccountKey == account.key)
        #expect(meter.isLiveReading)
        #expect(meter.summary.text == "100%")
    }

    private func provider(_ account: ProviderAccount) -> DemoUsageProvider {
        DemoUsageProvider(id: account.providerID, displayName: account.providerID.displayName,
                          snapshot: .pending(for: account.providerID), accountID: account.id)
    }

    private func account(_ provider: ProviderID, _ id: String) -> ProviderAccount {
        ProviderAccount(id: AccountID(id), providerID: provider, label: id)
    }
}
