import Foundation
import Testing
@testable import PacemarkCore

@Test func pacemarkImportPreservesPreferencesAndAccountHomes() throws {
    let domain = UUID().uuidString
    let defaults = DemoMemoryDefaults()

    defaults.setPersistentDomain(["existing": 1], forName: domain)
    let sourceDomain = UUID().uuidString
    let source = DemoMemoryDefaults()

    source.set(2, forKey: "existing")
    let account = try #require(AccountRegistry(defaults: source).addAccount(for: .claude))
    let path = try #require(CanonicalHomePath(trustedCanonical: "/tmp/example-codex"))
    let home = T3CodexHome(instanceID: "example", displayName: "Discovered", path: path, binaryPath: nil)
    T3DiscoveryCache(defaults: source).record(.found([home]))
    var decisions = BorrowedHomeDecisions()
    decisions.labels[.borrowedHome(path)] = "Custom"
    source.set(try JSONEncoder().encode(decisions), forKey: BorrowedHomeDecisions.storageKey)
    let old = try #require(source.persistentDomain(forName: sourceDomain))
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let base = temporary.appendingPathComponent("Pacemark/Accounts")
    let originalHome = AccountStorage.accountDirectoryURL(for: account, baseDirectoryURL: base)
    try FileManager.default.createDirectory(at: originalHome, withIntermediateDirectories: true)
    #expect(PacemarkImport.apply(from: { old }, to: defaults, domain: domain))
    #expect(defaults.integer(forKey: "existing") == 1)
    let imported = try #require(AccountRegistry(defaults: defaults).accounts(for: .claude).last)
    #expect(imported == account)
    #expect(T3DiscoveryCache(defaults: defaults).load() == [home])
    #expect(AccountRegistry(defaults: defaults).accounts(for: .codex).contains {
        $0.borrowedHome?.path == path && $0.label == "Custom"
    })
    let importedHome = AccountStorage.accountDirectoryURL(for: imported, baseDirectoryURL: base)
    #expect(importedHome == originalHome)
    #expect(FileManager.default.fileExists(atPath: importedHome.path))
    #expect(source.integer(forKey: "existing") == 2)
    #expect(defaults.bool(forKey: PacemarkImport.marker))
    #expect(!PacemarkImport.apply(from: { Issue.record("Read old domain twice"); return [:] }, to: defaults, domain: domain))
    #expect(AccountStorage.baseDirectoryURL.path.hasSuffix("/\(AccountStorage.sharedSupportFolder)/Accounts"))
    #expect(PacemarkImport.warnAboutRunningApp(running: true, defaults: defaults))
    defaults.set(true, forKey: PacemarkImport.keepBoth)
    #expect(!PacemarkImport.warnAboutRunningApp(running: true, defaults: defaults))
}

@Test func emptyOrExcludedPreferencesOnlyMarkImportComplete() throws {
    let prefixes = ["companionSync.", "SU", "NS", "Apple", "com.apple.", "WebKit", "AK",
                    "pacemark.import.", "co.zantos.headroom.bench."]
    let excluded = prefixes.map { $0 + "example" } + ["launchAtLogin", "sessionReliability.v1", "claudeSignOutRecord.v1"]
    for keys in [[], excluded] {
        let domain = UUID().uuidString
        let defaults = DemoMemoryDefaults()

        let source = Dictionary(uniqueKeysWithValues: keys.map { ($0, true) })
        #expect(!PacemarkImport.apply(from: { source }, to: defaults, domain: domain))
        #expect(defaults.persistentDomain(forName: domain) as? [String: Bool] == [PacemarkImport.marker: true])
    }
}
