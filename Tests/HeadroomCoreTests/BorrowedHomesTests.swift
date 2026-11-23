import Foundation
import Testing
@testable import HeadroomCore

struct BorrowedHomesTests {
    @Test func ownedAndSetupCapabilitiesAndRelease162RoundTrip() throws {
        let path = try #require(CanonicalHomePath(trustedCanonical: "/fixture/shadow/pro100"))
        let borrowed = ProviderAccount(borrowing: .init(path: path, source: .manual), providerID: .codex, label: "Pro100")
        let cli = ProviderAccount.builtIn(for: .codex)
        let owned = ProviderAccount(id: AccountID("owned"), providerID: .codex, label: "Work")
        #expect(cli.origin == .cliDefault)
        #expect(owned.origin == .headroomOwned)
        #expect(borrowed.id == .borrowedHome(path))
        #expect(borrowed.origin == .borrowed(try #require(borrowed.borrowedHome)))
        #expect(!borrowed.isBuiltIn)
        #expect(HeadroomOwnedHome(cli) == nil)
        #expect(HeadroomOwnedHome(owned)?.account == owned)
        #expect(HeadroomOwnedHome(borrowed) == nil)
        #expect(SetupCapableAccount(cli)?.ownedHome == nil)
        #expect(SetupCapableAccount(cli)?.account == cli)
        #expect(SetupCapableAccount(owned)?.ownedHome?.account == owned)
        #expect(SetupCapableAccount(borrowed) == nil)
        #expect(PersistedAccount(borrowed) == nil)

        let defaults = try makeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        registry.seed([cli, owned, borrowed])
        let bytes = try #require(defaults.data(forKey: "providerAccounts.v1"))
        let release = try JSONDecoder().decode([Release162ProviderAccount].self, from: bytes)
        #expect(release.map(\.isBuiltIn) == [true, false])
        #expect(release.map(\.label) == ["Main", "Work"])
        defaults.set(try JSONEncoder().encode(release), forKey: "providerAccounts.v1")
        #expect(registry.accounts(for: .codex) == [cli, owned])
        let config = ProviderAccountConfiguration.make(for: borrowed)
        #expect(config.codexAuthFile == nil && config.codexHomeDirectory == nil)
        #expect(config.codexTransport == borrowed.borrowedHome.map(CodexTransport.appServer))

        for invalid in ["relative", "/path/../other", "/path//other", "/path/", "/path/./other", "/"] {
            #expect(CanonicalHomePath(trustedCanonical: invalid) == nil)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CanonicalHomePath.self, from: Data("\"/a/../b\"".utf8))
        }
        let encoded = try JSONEncoder().encode(borrowed)
        #expect(try JSONDecoder().decode(ProviderAccount.self, from: encoded) == borrowed)
    }

    @Test func claudeDiscoverySelectsTheEnabledDefaultHome() {
        let settings = Data(#"""
        {"providerInstances":{
          "a-codex":{"driver":"codex"},
          "b-isolated":{"driver":"claudeAgent","config":{"homePath":"/fixture/other-claude"}},
          "c-disabled":{"driver":"claudeAgent","enabled":false},
          "d-default":{"driver":"claudeAgent","displayName":"Personal Claude","config":{"homePath":"~/.claude"}}
        }}
        """#.utf8)
        #expect(T3Installation.claudeInstanceName(in: settings, userHome: "/fixture") == "Personal Claude")
        let bare = Data(#"{"providerInstances":{"claudeAgent":{"driver":"claudeAgent"}}}"#.utf8)
        #expect(T3Installation.claudeInstanceName(in: bare, userHome: "/fixture") == "Claude (T3)")
        #expect(T3Installation.claudeInstanceName(in: Data("{".utf8), userHome: "/fixture") == nil)
    }

    @Test @MainActor func explicitCLIStopSurvivesRestartAndPreservesRegistryEncoding() async throws {
        let defaults = try makeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let prefs = Preferences(defaults: defaults)
        let storage = DemoAccountStorage()
        let account = ProviderAccount(id: .primary, providerID: .cursor, label: "My CLI", isBuiltIn: true)
        registry.seed([account])
        let bytes = defaults.data(forKey: "providerAccounts.v1")
        let factory: @MainActor (ProviderAccount) -> any UsageProvider = { row in
            DemoUsageProvider(id: row.providerID, displayName: row.providerID.displayName,
                              snapshot: .pending(for: row.providerID), accountID: row.id)
        }
        let live = UsageStore(providers: [factory(account)], preferences: prefs, accountRegistry: registry,
                              accountStorage: storage, providerFactory: factory)
        #expect(await live.stopTrackingBuiltInAccount(for: .cursor) == .notAllowed)
        storage.beginHandoff(account.key)
        #expect(await live.stopTrackingBuiltInAccount(for: .cursor, allowingEmpty: true) == .setupActive)
        storage.endHandoff(account.key)
        #expect(await live.stopTrackingBuiltInAccount(for: .cursor, allowingEmpty: true) == .removed)
        #expect(registry.accounts(for: .cursor, capacity: 1).isEmpty)
        #expect(live.accounts(for: .cursor).isEmpty)
        #expect(live.accountSettingsProviderIDs.contains(.cursor))
        #expect(defaults.data(forKey: "providerAccounts.v1") == bytes)

        let relaunched = UsageStore(providers: [], preferences: prefs, accountRegistry: registry,
                                    accountStorage: storage, providerFactory: factory)
        #expect(relaunched.accountSettingsProviderIDs.contains(.cursor))
        #expect(relaunched.registeredProviderOrder.isEmpty)
        #expect(relaunched.accountCapacity(for: .cursor) == 1)
        #expect(!relaunched.canAddAccount(for: .cursor))
        #expect(relaunched.resumeTrackingBuiltInAccount(for: .cursor) == account)
        #expect(relaunched.accounts(for: .cursor) == [account])
        #expect(defaults.data(forKey: "providerAccounts.v1") == bytes)
    }

    @Test @MainActor func stoppingLastT3HomeKeepsSuppressedCodexCLIStopped() async throws {
        let defaults = try makeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let home = try t3Home("a", name: "Pro100")
        _ = T3DiscoveryCache(defaults: defaults).record(.found([home]))
        let account = try #require(registry.accounts(for: .codex).first)
        let store = UsageStore(
            providers: [demoProvider(account)], preferences: Preferences(defaults: defaults),
            accountRegistry: registry, accountStorage: DemoAccountStorage(), providerFactory: demoProvider
        )
        #expect(store.discoveredT3CodexAccounts().map(\.key) == [account.key])
        #expect(await store.removeAccount(account.key, keepingCLISourceStopped: true) == .removed)
        #expect(store.accounts(for: .codex).isEmpty)
        #expect(store.discoveredT3CodexAccounts().map(\.key) == [account.key])
        #expect(store.restoreBorrowedAccount(account.key))
        #expect(store.accounts(for: .codex).map(\.key) == [account.key])
        store.setTracksCLIDefaultAlongsideT3(true)
        #expect(store.accounts(for: .codex).contains { $0.isBuiltIn })
        await store.waitForAccountProbesToFinish()
    }

    @Test @MainActor func observedCLIVersionFollowsTheActiveAttachment() async throws {
        let defaults = try makeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let account = ProviderAccount.builtIn(for: .codex)
        let store = UsageStore(
            providers: [demoProvider(account)], preferences: Preferences(defaults: defaults),
            accountRegistry: registry, accountStorage: DemoAccountStorage(), providerFactory: demoProvider
        )
        let pending = UsageSnapshot.pending(for: .codex)
        let reading = UsageProviderFetchResult(snapshot: pending, cliVersion: "v0.171.0")
        #expect(store.schedulerMerge(key: account.key, result: reading, attachmentGeneration: 0))
        #expect(store.observedCLIVersions[account.key] == "v0.171.0")
        #expect(store.schedulerMerge(key: account.key, result: .init(snapshot: pending), attachmentGeneration: 0))
        #expect(store.observedCLIVersions[account.key] == "v0.171.0")
        #expect(await store.stopTrackingBuiltInAccount(for: .codex, allowingEmpty: true) == .removed)
        #expect(store.observedCLIVersions[account.key] == nil)
        store.setTracksCLIDefaultAlongsideT3(true)
        #expect(!store.schedulerMerge(key: account.key, result: reading, attachmentGeneration: 0))
        #expect(store.observedCLIVersions[account.key] == nil)
        await store.waitForAccountProbesToFinish()
    }

    @Test func parserFiltersRegularCodexHomesAndDistinguishesReadFailures() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent(".t3/userdata/settings.json")
        let folder = root.appendingPathComponent("shadow", isDirectory: true)
        let cli = root.appendingPathComponent(".codex", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        let owned = root.appendingPathComponent("Headroom/Accounts", isDirectory: true)
        let install = T3Installation(userHome: root, accountsBase: owned)
        #expect(install.scanCodexHomes() == .notInstalled)
        for directory in [settings.deletingLastPathComponent(), folder, cli, owned] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)
        let data = try JSONSerialization.data(withJSONObject: ["providerInstances": [
            "codex_pro100": ["driver": "codex", "displayName": "Pro100", "enabled": true,
                            "config": ["shadowHomePath": alias.path, "binaryPath": "/fixture/bin/codex"]],
            "codex_pro200": ["driver": "codex", "enabled": false, "config": ["shadowHomePath": folder.path]],
            "codex_managed": ["driver": "codex-managed", "config": ["shadowHomePath": folder.path]],
            "codex": ["driver": "codex", "config": ["shadowHomePath": cli.path]],
            "owned": ["driver": "codex", "config": ["shadowHomePath": owned.path]],
            "empty": ["driver": "codex", "config": ["shadowHomePath": ""]],
            "remote": ["driver": "codex", "config": ["shadowHomePath": "/missing-headroom-test-folder"]],
        ]])
        let entries = try #require(T3SettingsParser.parse(data))
        #expect(entries.count == 7)
        #expect(entries.first { $0.id == "codex_managed" }?.enabled == true)
        try data.write(to: settings)
        let expected = T3CodexHome(
            instanceID: "codex_pro100", displayName: "Pro100",
            path: try #require(CanonicalHomePath(trustedCanonical: folder.path)), binaryPath: "/fixture/bin/codex"
        )
        #expect(install.scanCodexHomes() == .found([expected]))
        #expect(BorrowedHomePaths.canonicalize(cli, userHome: root, accountsBase: owned) == .failure(.isCLIDefault))
        #expect(BorrowedHomePaths.canonicalize(owned, userHome: root, accountsBase: owned) == .failure(.insideHeadroomStorage))
        try Data("{".utf8).write(to: settings)
        #expect(install.scanCodexHomes() == .unreadable)
        try Data("{\"providerInstances\":{}}".utf8).write(to: settings)
        #expect(install.scanCodexHomes() == .found([]))
        #expect(T3SettingsParser.parse(Data("{}".utf8)) == nil)
    }

    @Test func discoveryIsIdempotentAndUserDecisionsSurviveRescans() throws {
        let defaults = try makeDefaults()
        let cache = T3DiscoveryCache(defaults: defaults)
        let registry = AccountRegistry(defaults: defaults)
        let first = try t3Home("a", name: "Pro100")
        let second = try t3Home("b", name: "Pro200")
        #expect(!cache.record(.notInstalled))
        #expect(cache.record(.found([first, second])))
        let bytes = defaults.data(forKey: T3DiscoveryCache.storageKey)
        #expect(!cache.record(.found([second, first, first])))
        #expect(!cache.record(.unreadable))
        #expect(defaults.data(forKey: T3DiscoveryCache.storageKey) == bytes)
        let pro100 = try #require(registry.accounts(for: .codex).first)
        #expect(!registry.accounts(for: .codex).contains { $0.isBuiltIn })
        #expect(!registry.isBuiltInHidden(for: .codex))
        registry.renameAccount(pro100.key, to: "My plan")
        registry.setBorrowedMenuBarBadge("A", for: pro100.id)
        registry.removeAccount(pro100.key)
        let updated = T3CodexHome(instanceID: "a", displayName: "New name", path: first.path, binaryPath: "/new/codex")
        #expect(cache.record(.found([updated, second])))
        #expect(registry.accounts(for: .codex).map(\.label) == ["Pro200"])
        #expect(registry.hiddenBorrowedAccounts(for: .codex).map(\.label) == ["My plan"])
        #expect(registry.borrowedMenuBarBadge(for: pro100.id) == "A")
        #expect(registry.restoreBorrowedAccount(pro100.key))
        registry.setTracksCLIDefaultAlongsideT3(true)
        #expect(registry.accounts(for: .codex).contains { $0.isBuiltIn })
        #expect(registry.accounts(for: .codex).first { $0.key == pro100.key }?.label == "My plan")
        #expect(cache.record(.notInstalled))
        #expect(!cache.record(.notInstalled))
        #expect(registry.accounts(for: .codex) == [.builtIn(for: .codex)])

        var decisions = BorrowedHomeDecisions()
        decisions.manualHomes = [.init(path: first.path, addedAt: .distantPast)]
        let resolved = BorrowedHomeRoster.resolve(discovered: [first, second], decisions: decisions)
        #expect(resolved.visible.count == 2)
        #expect(resolved.visible.first?.borrowedHome?.source.isT3 == true)
        #expect(resolved.suppressesCLIDefault)
        #expect(!BorrowedHomeRoster.resolve(discovered: [], decisions: decisions).suppressesCLIDefault)
    }

    @Test @MainActor func rescanDetachesWithoutPurgingAndExplicitHidePurges() async throws {
        let defaults = try makeDefaults()
        let registry = AccountRegistry(defaults: defaults)
        let cache = UsageContinuityCache(defaults: defaults)
        let ledger = UseItUpLedger(defaults: defaults)
        let baseline = BankedResetNotificationBaseline(defaults: defaults)
        let t3 = try t3Home("a", name: "Pro100")
        let settings = ScanBox(.found([t3]))
        let key = AccountKey(providerID: .codex, accountID: .borrowedHome(t3.path))
        let now = Date()
        let snapshot = UsageSnapshot.live(.codex, windows: [
            UsageWindow(kind: .weekly, utilization: 20, resetsAt: now.addingTimeInterval(3600)),
        ])
        let entry = UseItUpLedgerEntry(account: key, windowID: "weekly", deadline: now, firedKeys: ["one"])
        cache.save(snapshot, for: key)
        ledger.restore([entry], for: key, now: now)
        baseline.record(count: 3, for: key)
        let store = UsageStore(
            providers: [demoProvider(.builtIn(for: .codex))], preferences: Preferences(defaults: defaults),
            accountRegistry: registry, accountStorage: FailIfTouchedStorage(),
            borrowedHomes: BorrowedHomeEnvironment(scanT3: { settings.scan }, canonicalize: { _ in .success(t3.path) }),
            providerFactory: demoProvider, continuityCache: cache,
            notificationCoordinator: NotificationCoordinator(
                poster: InertNotificationPoster(), useItUpLedger: ledger, bankedResetBaseline: baseline
            ), now: { now }
        )
        #expect(store.rescanBorrowedHomes().visibleT3Homes == 1)
        #expect(store.accounts(for: .codex).map(\.key) == [key])
        #expect(!store.snapshot(for: key).windows.isEmpty)
        settings.scan = .unreadable
        #expect(!store.rescanBorrowedHomes().read)
        #expect(store.accounts(for: .codex).map(\.key) == [key])
        settings.scan = .found([])
        #expect(store.rescanBorrowedHomes().visibleT3Homes == 0)
        #expect(store.accounts(for: .codex).map(\.id) == [.primary])
        #expect(cache.load()[key] != nil)
        #expect(ledger.entry(for: key, windowID: "weekly") == entry)
        #expect(baseline.baselineCount(for: key) == 3)
        settings.scan = .found([t3])
        #expect(store.rescanBorrowedHomes().visibleT3Homes == 1)
        #expect(!store.snapshot(for: key).windows.isEmpty)
        #expect(await store.removeAccount(key) == .removed)
        #expect(cache.load()[key] == nil)
        #expect(ledger.entry(for: key, windowID: "weekly") == nil)
        #expect(baseline.baselineCount(for: key) == nil)
        #expect(store.hiddenBorrowedAccounts(for: .codex).map(\.key) == [key])
    }

    @Test @MainActor func manualFolderCanBecomeT3WithSameKeyBadgeAndContinuity() async throws {
        let defaults = try makeDefaults()
        let folder = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let witness = folder.appendingPathComponent("keep")
        try Data().write(to: witness)
        let canonical = try #require(CanonicalHomePath(trustedCanonical: folder.path))
        let settings = ScanBox(.notInstalled)
        let prefs = Preferences(defaults: defaults)
        prefs.menuBarFillSource = .providers([.codex])
        let registry = AccountRegistry(defaults: defaults)
        var origins: [AccountOrigin] = []
        let store = UsageStore(
            providers: [demoProvider(.builtIn(for: .codex))], preferences: prefs,
            accountRegistry: registry, accountStorage: FailIfTouchedStorage(),
            borrowedHomes: BorrowedHomeEnvironment(scanT3: { settings.scan }, canonicalize: { _ in .success(canonical) }),
            providerFactory: { account in origins.append(account.origin); return demoProvider(account) }
        )
        let account = try store.addExternalCodexHome(at: folder, label: "Pro100").get()
        #expect(account.borrowedHome?.source == .manual)
        #expect(store.menuBarMeters.map(\.badge) == ["M", "100"])
        #expect(store.menuBarMeters.map(\.glyph) == [.providerMark(.codex), .providerMark(.codex)])
        store.setMenuBarBadge(" 2k! ", for: account.key)
        #expect(store.menuBarBadge(for: account.key) == "2K")
        #expect(store.addExternalCodexHome(at: folder, label: nil) == .failure(.alreadyTracked(account.key)))
        await store.waitForAccountProbesToFinish()
        let reading = UsageSnapshot.live(.codex, windows: [
            UsageWindow(kind: .weekly, utilization: 42, resetsAt: .distantFuture),
        ])
        store.snapshots[account.key] = reading
        settings.scan = .found([T3CodexHome(instanceID: "x", displayName: "Changed", path: canonical, binaryPath: "/new/codex")])
        store.rescanBorrowedHomes()
        #expect(origins.compactMap { origin -> BorrowedHomeSource? in
            guard case .borrowed(let home) = origin else { return nil }
            return home.source
        } == [.manual, .t3Instance(instanceID: "x", displayName: "Changed")])
        #expect(store.accounts(for: .codex).map(\.label) == ["Pro100"])
        #expect(store.snapshot(for: account.key) == reading)
        #expect(store.menuBarBadge(for: account.key) == "2K")
        store.setTracksCLIDefaultAlongsideT3(true)
        #expect(store.accounts(for: .codex).count == 2)
        store.setShowAllProviderAccountsInMenuBar(false)
        #expect(store.menuBarMeters.count == 1)
        store.setMenuBarIconStyle(.capsules)
        #expect(store.menuBarMeters.first?.glyph == .capsule)
        #expect(await store.removeAccount(account.key) == .removed)
        #expect(FileManager.default.fileExists(atPath: witness.path))
        settings.scan = .found([])
        store.rescanBorrowedHomes()
        #expect(store.accounts(for: .codex).map(\.id) == [.primary])
        let reacquired = try store.addExternalCodexHome(at: folder, label: "Folder").get()
        #expect(await store.removeAccount(reacquired.key) == .removed)
        #expect(FileManager.default.fileExists(atPath: witness.path))
        #expect(store.menuBarBadge(for: reacquired.key) == nil)
        await store.waitForAccountProbesToFinish()
    }

    @Test @MainActor func widgetAndCompanionV4PayloadContainNoBorrowedPath() throws {
        let defaults = try makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.widgetsEnabled = true
        prefs.syncToIPhoneEnabled = true
        let path = try #require(CanonicalHomePath(trustedCanonical: "/sensitive-parent-marker/private/pro100"))
        let row = ProviderAccount(borrowing: .init(
            path: path, source: .manual, preferredExecutable: "/sensitive-executable-marker/codex"
        ), providerID: .codex, label: "Pro100")
        let widgets = SpyWidgetExporter()
        let store = UsageStore(
            providers: [demoProvider(row)], preferences: prefs, accounts: [row], widgetExporter: widgets
        )
        store.snapshots[row.key] = .live(.codex, windows: [
            UsageWindow(kind: .weekly, utilization: 20, resetsAt: Date().addingTimeInterval(3600)),
        ])
        store.exportWidgetSnapshot()
        let exported = try #require(widgets.exports.last)
        #expect(exported.providers.first?.id == "codex")
        let widgetBytes = try JSONEncoder().encode(exported)
        let capture = store.companionCapture()
        let provider = try #require(capture.providers.first)
        #expect(provider.mainAccount?.id == row.id.raw)
        var versionedCapture = capture
        versionedCapture.generation = 1
        let image = try CompanionPublishImage.fullImage(
            capture: versionedCapture, sourceID: UUID().uuidString.lowercased()
        )
        #expect(!image.providers.isEmpty)
        for data in [widgetBytes, image.manifest, image.v3] + Array(image.providers.values) {
            let text = String(decoding: data, as: UTF8.self)
            #expect(!text.contains("sensitive-parent-marker"))
            #expect(!text.contains("sensitive-executable-marker"))
            #expect(!text.contains("borrowedHome"))
        }
    }
}

private final class ScanBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: T3CodexScan
    init(_ state: T3CodexScan) { self.state = state }
    var scan: T3CodexScan {
        get { lock.withLock { state } }
        set { lock.withLock { state = newValue } }
    }
}

private struct FailIfTouchedStorage: AccountStorageManaging {
    func ensureDirectories(for home: HeadroomOwnedHome) -> Result<Void, AccountStorageFailure> {
        Issue.record("Unexpected directory creation")
        return .failure(.createFailed)
    }

    func setupHandoffIsActive(for setup: SetupCapableAccount) async -> Bool {
        Issue.record("Unexpected setup check")
        return false
    }

    func removeDirectories(for home: HeadroomOwnedHome) async -> Result<Void, AccountStorageFailure> {
        Issue.record("Unexpected directory removal")
        return .failure(.removeFailed)
    }
}

private func demoProvider(_ row: ProviderAccount) -> any UsageProvider {
    DemoUsageProvider(id: row.providerID, displayName: "Codex", snapshot: .pending(for: row.providerID), accountID: row.id)
}

private func t3Home(_ id: String, name: String) throws -> T3CodexHome {
    let path = try #require(CanonicalHomePath(trustedCanonical: "/fixture/\(id)"))
    return T3CodexHome(instanceID: id, displayName: name, path: path, binaryPath: nil)
}

private func makeDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "HeadroomT3Tests.\(UUID())"))
}

func fixtureDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("HeadroomT3Tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    // Foundation can spell the temporary directory via /var even after URL resolution.
    return try #require(BorrowedHomePaths.existingDirectory(url)?.url)
}
