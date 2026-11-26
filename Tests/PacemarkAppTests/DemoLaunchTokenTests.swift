import Foundation
import Testing
import PacemarkCore
@testable import Pacemark

/// The launch-time seams demo captures depend on: which UserDefaults domain a run may touch,
/// and the two diagnostic style overrides.
@MainActor
@Suite(.sharedAppState)
struct DemoLaunchTokenTests {
    @Test func generatedGrokAccountsHaveDistinctEmails() async {
        let accounts = DemoFixture.generatedAccounts(provider: .grok, count: 20)
        for (index, entry) in accounts.enumerated() {
            let snapshot = await entry.provider.fetchSnapshot()
            #expect(snapshot.accountEmail == (index == 0 ? "personal@example.com" : "account\(index + 1)@example.com"))
        }
    }

    // MARK: Isolated demo defaults

    /// A `--demo` run must not read or write the user's settings. `PacemarkApp.init` used to
    /// build `Preferences()` on `.standard` while the store took the demo suite, so demo runs
    /// wrote `appearancePreference` / `settingsPane` / `showMenuBarPercentage` /
    /// `menuBarFillSource` into the real domain — and read their theme back out of it.
    @Test func everyDemoLaunchWritesOutsideTheStandardDomain() {
        for arguments in [
            ["Pacemark", "--demo"],
            ["Pacemark", "--demo", "multi-2"],
            ["Pacemark", "--demo", "multi-4", "--meter-style", "full.chip.ghost"],
        ] {
            let key = "pacemark-launch-domain-probe-\(UUID().uuidString)"
            let defaults = AppComposition.resolveLaunchDefaults(arguments: arguments)
            #expect(defaults !== UserDefaults.standard)
            defaults.set(true, forKey: key)
            defer { defaults.removeObject(forKey: key) }
            #expect(UserDefaults.standard.object(forKey: key) == nil)
        }
    }

    /// Non-demo behavior stays byte-identical: the shipping app still reads and writes
    /// `.standard`, even though the hosted unit suite itself launches isolated fixtures.
    @Test func aNormalLaunchKeepsTheStandardDomain() {
        #expect(AppComposition.resolveLaunchDefaults(arguments: ["Pacemark"], environment: [:]) === UserDefaults.standard)
        #expect(AppComposition.resolveLaunchDefaults(
            arguments: ["Pacemark", "--render-popover", "shots"], environment: [:]
        ) !== UserDefaults.standard)
    }

    @Test func hostedLaunchWithoutDemoArgumentUsesIsolatedDefaults() {
        #expect(AppComposition.resolveLaunchDefaults(
            arguments: ["Pacemark"],
            environment: ["XCTestConfigurationFilePath": "/tmp/fixture.xctestconfiguration"]
        ) !== UserDefaults.standard)
    }

    @Test func hostedUnitSuiteUsesIsolatedLaunchDefaults() {
        #expect(DemoFixture.isEnabled)
        #expect(AppComposition.launchDefaults !== UserDefaults.standard)
        let key = "pacemark-hosted-suite-domain-probe-\(UUID().uuidString)"
        AppComposition.launchDefaults.set(true, forKey: key)
        defer { AppComposition.launchDefaults.removeObject(forKey: key) }
        #expect(AppComposition.launchDefaults.bool(forKey: key))
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test func sessionReliabilityCollectionIsAbsentFromEveryInertLaunch() {
        let defaults = DemoMemoryDefaults()
        for flag in ["--demo", "--render-popover", "--render-loading-preview", "--bench-ui"] {
            #expect(AppComposition.makeSessionReliabilityRecord(
                arguments: ["Pacemark", flag], environment: [:], defaults: defaults
            ) == nil)
        }
        #expect(AppComposition.makeSessionReliabilityRecord(
            arguments: ["Pacemark"],
            environment: ["XCTestConfigurationFilePath": "/tmp/fixture.xctestconfiguration"],
            defaults: defaults
        ) == nil)
        #expect(AppComposition.makeSessionReliabilityRecord(
            arguments: ["Pacemark"], environment: [:], defaults: defaults
        ) != nil)
        #expect(defaults.dictionaryRepresentation()["sessionReliability.v1"] == nil)
    }

    // MARK: --account-title-ink

    /// The review seam `AccountTitleInk.brand` had no path to: the demo prefs suite cannot be
    /// preset by hand and the popover is not an accessibility window (round-3 residual).
    @Test func accountTitleInkTokenParsesLikeMeterStyle() {
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Pacemark", "--demo", "--account-title-ink", "brand"]
        ) == .brand)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Pacemark", "--demo", "--account-title-ink", "neutral"]
        ) == .neutral)
    }

    /// An absent or malformed token reseeds the landed default, exactly like `demoMeterStyle`,
    /// so a previous run cannot leak into a later capture. Entry rejects the malformed ones
    /// before the menu bar launches.
    @Test func absentOrMalformedAccountTitleInkFallsBackToTheDefault() {
        #expect(AppComposition.demoAccountTitleInk(arguments: ["Pacemark", "--demo"]) == .neutral)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Pacemark", "--demo", "--account-title-ink"]
        ) == .neutral)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Pacemark", "--demo", "--account-title-ink", "Brand"]
        ) == .neutral)
        #expect(AppComposition.demoAccountTitleInk(
            arguments: ["Pacemark", "--demo", "--account-title-ink", "rainbow"]
        ) == .neutral)
    }

    // MARK: --account-layout

    @Test func accountLayoutTokenSeedsTheDemoLayout() {
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Pacemark", "--demo", "multi-7", "--account-layout", "compact"]
        ) == .compact)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Pacemark", "--demo", "--account-layout", "standard"]
        ) == .standard)
    }

    /// Like `--account-title-ink`, an absent or malformed token reseeds the default so one
    /// capture cannot leak into the next; entry rejects the malformed ones under `--demo`.
    @Test func absentOrMalformedAccountLayoutFallsBackToLedger() {
        #expect(AppComposition.demoAccountLayout(arguments: ["Pacemark", "--demo"]) == .ledger)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Pacemark", "--demo", "--account-layout"]
        ) == .ledger)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Pacemark", "--demo", "--account-layout", "Compact"]
        ) == .ledger)
        #expect(AppComposition.demoAccountLayout(
            arguments: ["Pacemark", "--demo", "--account-layout", "columns"]
        ) == .ledger)
    }

    // MARK: Claude identity reader (default-login plan U2)

    /// Only a real launch reads `.claude.json`. Demo scenarios (`remembered`, `merged`,
    /// `multi-3` and the rest), the render and bench harnesses and this XCTest host get no
    /// reader, so their Claude providers read no file. The decision is asserted without
    /// reading: building a reader opens nothing until a fetch runs.
    @Test func onlyARealLaunchWiresTheClaudeIdentityReaderAndEachRowGetsItsOwnFile() throws {
        for arguments in [
            ["Pacemark", "--demo", "remembered"],
            ["Pacemark", "--demo", "merged"],
            ["Pacemark", "--demo", "multi-3"],
            ["Pacemark", "--render-popover", "/tmp/x"],
            ["Pacemark", "--bench-ui", "popover"],
        ] {
            #expect(AppComposition.claudeIdentityReader(configDirectory: nil, arguments: arguments, environment: [:]) == nil,
                    "\(arguments)")
        }
        #expect(AppComposition.claudeIdentityReader(configDirectory: nil) == nil)

        let builtIn = try #require(AppComposition.claudeIdentityReader(
            configDirectory: nil, arguments: ["Pacemark"], environment: [:]
        ) as? ClaudeAccountEmailFileReader)
        #expect(builtIn.accountFile.path
            == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json").path)
        let extraHome = URL(fileURLWithPath: "/tmp/pacemark-tests/claude/work/config", isDirectory: true)
        let extra = try #require(AppComposition.claudeIdentityReader(
            configDirectory: extraHome, arguments: ["Pacemark"], environment: [:]
        ) as? ClaudeAccountEmailFileReader)
        #expect(extra.accountFile.path == "/tmp/pacemark-tests/claude/work/config/.claude.json")
    }



    @Test func meterStyleAndAccountTitleInkTokensCoexist() {
        let arguments = [
            "Pacemark", "--demo", "multi-2",
            "--meter-style", "full.segmented.ghost",
            "--account-title-ink", "brand",
        ]
        #expect(AppComposition.demoMeterStyle(arguments: arguments) == MeterStyle(
            format: .full,
            shape: .segmented,
            fill: .ghost
        ))
        #expect(AppComposition.demoAccountTitleInk(arguments: arguments) == .brand)
    }
}
