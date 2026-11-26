import Foundation
import Testing
@testable import PacemarkCore

@MainActor
struct DemoCaptureTests {
    private let captureDate = Date(timeIntervalSince1970: 1_800_000_000)
    private let liveKey = AccountKey(providerID: .codex, accountID: .borrowedHome(
        CanonicalHomePath(trustedCanonical: "/fixture-home-that-must-not-leak")!
    ))

    private func capture() async -> DemoCapture {
        let defaults = DemoMemoryDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.menuBarFillSource = .codex
        preferences.showMenuBarPercentage = true
        preferences.menuBarProviderOrder = [.codex, .claude]
        preferences.menuBarIconStyle = .providerIcons
        preferences.setMenuBarWindowChoice(.fiveHour, for: .codex)
        let account = ProviderAccount(
            borrowing: BorrowedHome(
                path: CanonicalHomePath(trustedCanonical: "/fixture-home-that-must-not-leak")!,
                source: .t3Instance(instanceID: "private-instance-marker", displayName: nil),
                preferredExecutable: "/fixture-executable-that-must-not-leak"
            ),
            providerID: .codex, label: "Studio"
        )
        let identity = AccountIdentity(
            providerID: .codex, strength: .strong, digest: "private-upstream-digest-marker",
            digestVersion: AccountIdentity.currentDigestVersion
        )
        let reading = UsageSnapshot(
            providerID: .codex, windows: [
                UsageWindow(kind: .fiveHour, utilization: 27.5, resetsAt: captureDate.addingTimeInterval(900)),
                UsageWindow(kind: .billingPeriod(label: "Monthly", duration: 2_592_000), utilization: 100,
                            resetSchedule: .unresolved(.absent), isLimited: true),
                UsageWindow(kind: .other("Retained"), utilization: 12,
                            resetSchedule: .scheduled(captureDate.addingTimeInterval(-30)),
                            freshness: .unavailable(since: captureDate.addingTimeInterval(-30)))
            ],
            planLabel: "Plus", accountEmail: "studio@example.invalid", bankedResets: 2,
            capturedAt: captureDate.addingTimeInterval(-10), freshness: .live, identity: .known(identity)
        )
        let signedOut = UsageSnapshot.stale(for: .claude, reason: .providerSetup(.claudeLoginRequired))
        let codex = DemoUsageProvider(id: .codex, displayName: "Codex", snapshot: reading,
                                     accountID: account.id, capability: .available, cliVersion: "1.2.3")
        let claude = DemoUsageProvider(id: .claude, displayName: "Claude", snapshot: signedOut)
        let date = captureDate
        let store = UsageStore(providers: [codex, claude], preferences: preferences,
                               accounts: [account, .builtIn(for: .claude)], now: { date })
        await store.refreshAll()
        if let row = store.menuBarMeterRows.first(where: { $0.key == liveKey }) { store.setMeterLabel("Studio", for: row) }
        store.setMenuBarBadge("ST", for: liveKey)
        return DemoCapture(store: store, preferences: preferences, at: date,
                           hasT3Claude: false, hasT3Antigravity: false)
    }

    @Test func roundTripKeepsDisplayDataAndRebasesDates() async throws {
        let original = await capture()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DemoCapture.self, from: data)
        #expect(original == decoded)
        let launch = captureDate.addingTimeInterval(86_400)
        let store = decoded.makeReplayStore(defaults: DemoMemoryDefaults(), at: launch)
        let row = try #require(store.accounts(for: .codex).first)
        #expect(store.menuBarMeterRows.first { $0.key == row.key }?.item.label == "Studio")
        #expect(row.key != liveKey)
        #expect(row.borrowedHome?.source.isT3 == true)
        #expect(row.label == "Studio")
        #expect(store.observedCLIVersions[row.key] == "1.2.3")
        #expect(store.menuBarBadge(for: row.key) == "ST")
        #expect(store.preferences.showMenuBarPercentage)
        #expect(store.preferences.menuBarProviderOrder == [.codex, .claude])
        #expect(store.menuBarWindowChoice(for: .codex) == .fiveHour)
        let snapshot = store.snapshot(for: row.key)
        #expect(snapshot.planLabel == "Plus")
        #expect(snapshot.accountEmail == "studio@example.invalid")
        #expect(snapshot.bankedResets == 2)
        #expect(snapshot.capturedAt == launch.addingTimeInterval(-10))
        #expect(abs(try #require(snapshot.windows.first).utilization - 27.5) < 0.000001)
        #expect(snapshot.windows.first?.resetSchedule == .scheduled(launch.addingTimeInterval(900)))
        #expect(snapshot.windows.contains { $0.isLimited && $0.resetSchedule == .unresolved(.absent) })
        #expect(snapshot.windows.last?.freshness == .unavailable(since: launch.addingTimeInterval(-30)))
        #expect(store.snapshot(for: .claude).freshness == .stale(.providerSetup(.claudeLoginRequired)))

        store.invalidateUsageForAccountReset(row.key)
        await store.refreshAll()
        #expect(store.snapshot(for: row.key) == snapshot)
    }

    @Test func missingFieldsUseCurrentDefaults() async throws {
        let original = await capture()
        var json = try captureJSON(original)
        var settings = try #require(json["settings"] as? [String: Any])
        for key in ["showMenuBarPercentage", "menuBarProviderOrder", "menuBarIconStyle", "enabledSurfaces"] {
            settings.removeValue(forKey: key)
        }
        var providers = try #require(settings["providerSettings"] as? [[String: Any]])
        let codex = try #require(providers.firstIndex { $0["windowWasChosen"] as? Bool == true })
        providers[codex].removeValue(forKey: "menuBarWindow")
        providers[codex].removeValue(forKey: "windowWasChosen")
        settings["providerSettings"] = providers
        json["settings"] = settings
        json.removeValue(forKey: "providerOrder")
        json.removeValue(forKey: "hasT3Claude")
        var accounts = try #require(json["accounts"] as? [[String: Any]])
        let tracked = try #require(accounts.firstIndex { $0["label"] as? String == "Studio" })
        accounts[tracked].removeValue(forKey: "isRemembered")
        accounts[tracked].removeValue(forKey: "mergesBuiltIn")
        json["accounts"] = accounts

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(DemoCapture.self, from: data)
        let defaults = Preferences(defaults: DemoMemoryDefaults())
        let store = decoded.makeReplayStore(defaults: DemoMemoryDefaults(), at: captureDate)
        #expect(store.preferences.showMenuBarPercentage == defaults.showMenuBarPercentage)
        #expect(decoded.settings.menuBarProviderOrder == defaults.menuBarProviderOrder)
        #expect(store.preferences.menuBarIconStyle == defaults.menuBarIconStyle)
        #expect(store.isSurfaceEnabled(.codexSubscription) == defaults.isSurfaceEnabled(.codexSubscription))
        #expect(store.menuBarWindowChoice(for: .codex) == defaults.menuBarWindowChoice(for: .codex))
        #expect(store.preferences.menuBarFillSource == .codex)
        #expect(decoded.providerOrder == original.providerOrder)
        #expect(!decoded.hasT3Claude)
        #expect(!decoded.accounts[tracked].isRemembered)
        #expect(!decoded.accounts[tracked].mergesBuiltIn)
    }

    @Test func ignoresUnknownFields() async throws {
        let original = await capture()
        var json = try captureJSON(original)
        var settings = try #require(json["settings"] as? [String: Any])
        settings["futureSetting"] = ["enabled": true]
        json["settings"] = settings
        json["futureCaptureField"] = 3

        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(DemoCapture.self, from: data) == original)
    }

    private func captureJSON(_ capture: DemoCapture) throws -> [String: Any] {
        let data = try JSONEncoder().encode(capture)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func encoderNeverCarriesCredentialsAccountKeysOrHomePaths() async throws {
        let capture = await capture()
        let data = try JSONEncoder().encode(capture)
        let json = try #require(String(data: data, encoding: .utf8)).lowercased()
        for forbidden in [
            "token", "auth.json", "credential", "accountid", "instanceid", "identitydigest", "refreshtoken",
            "fixture-home-that-must-not-leak", "fixture-executable-that-must-not-leak",
            "private-instance-marker", "private-upstream-digest-marker", liveKey.accountID.raw
        ] {
            #expect(!json.contains(forbidden))
        }
        #expect(json.contains("studio@example.invalid"))
        #expect(json.contains("\"resetoffset\":900"))
    }

    @Test func editsAreIsolatedAndSourcesCanBeRestored() async throws {
        let capture = await capture()
        let liveDefaults = DemoMemoryDefaults()
        let livePrefs = Preferences(defaults: liveDefaults)
        let liveRegistry = AccountRegistry(defaults: liveDefaults)
        liveRegistry.renameAccount(.init(providerID: .codex, accountID: .primary), to: "Unchanged")
        let demo = capture.makeReplayStore(defaults: DemoMemoryDefaults())
        let row = try #require(demo.accounts(for: .codex).first)

        demo.renameAccount(row.key, to: "Edited")
        demo.setMenuBarBadge("ED", for: row.key)
        demo.setMenuBarMode(.tightest)
        #expect(demo.accounts(for: .codex).first?.label == "Edited")
        #expect(demo.menuBarBadge(for: row.key) == "ED")
        #expect(await demo.removeAccount(row.key, keepingCLISourceStopped: true) == .removed)
        #expect(demo.accounts(for: .codex).isEmpty)
        #expect(demo.discoveredT3CodexAccounts().map(\.key) == [row.key])
        #expect(demo.restoreBorrowedAccount(row.key))
        await demo.refreshAll()
        #expect(demo.snapshot(for: row.key).planLabel == "Plus")
        #expect(demo.addAccount(for: .codex, label: "New Demo Login") != nil)
        let folder = demo.addExternalCodexHome(at: URL(fileURLWithPath: "/fictional-demo-folder"), label: "Demo Folder")
        #expect(try folder.get().label == "Demo Folder")

        #expect(liveRegistry.accounts(for: .codex).map(\.label) == ["Unchanged"])
        #expect(!livePrefs.showMenuBarPercentage)
        let newDemo = capture.makeReplayStore(defaults: DemoMemoryDefaults())
        #expect(newDemo.accounts(for: .codex).map(\.label) == ["Studio"])
        #expect(newDemo.menuBarMeterSelection.mode == .chosen)
    }

    @Test func resolvesDefaultAndExplicitCaptureArguments() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Pacemark", "--demo", "captured"]) == .captured(path: nil))
        #expect(DemoFixture.scenarioRequest(arguments: ["Pacemark", "--demo", "captured=demo data.json"])
                == .captured(path: "demo data.json"))
    }
}
