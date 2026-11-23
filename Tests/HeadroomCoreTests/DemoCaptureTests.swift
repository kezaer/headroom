import Foundation
import Testing
@testable import HeadroomCore

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
        #expect(row.key != liveKey)
        #expect(row.borrowedHome?.source.isT3 == true)
        #expect(row.label == "Studio")
        #expect(store.observedCLIVersions[row.key] == "1.2.3")
        #expect(store.menuBarBadge(for: row.key) == "ST")
        #expect(store.showMenuBarPercentage)
        #expect(store.menuBarProviderOrder == [.codex, .claude])
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
        demo.setShowMenuBarPercentage(false)
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
        #expect(newDemo.showMenuBarPercentage)
    }

    @Test func resolvesDefaultAndExplicitCaptureArguments() {
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "captured"]) == .captured(path: nil))
        #expect(DemoFixture.scenarioRequest(arguments: ["Headroom", "--demo", "captured=demo data.json"])
                == .captured(path: "demo data.json"))
    }
}
