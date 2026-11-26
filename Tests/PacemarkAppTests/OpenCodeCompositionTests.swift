import Foundation
import Testing
import PacemarkCore
@testable import Pacemark

/// U4 of the OpenCode plan: OpenCode registration, its one shared read path (KTD8), the
/// DEBUG-only executable override (KTD18) and the launches that never start the client.
@MainActor
struct OpenCodeCompositionTests {
    private let realLaunch: [String: String] = [:]

    @Test func everyRegistrationCapacityMatchesItsProvider() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("pacemark-capacity-\(UUID().uuidString)/ClaudeProbe", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let registry = AppComposition.subscriptionProviderRegistry
        #expect(registry.contains { $0.id == .opencode })
        for registration in registry {
            let provider = AppComposition.provider(
                for: .builtIn(for: registration.id),
                credentials: CredentialStore(),
                builtInClaudeWorkspace: workspace
            )
            #expect(provider.accountCapacity == registration.accountCapacity, "\(registration.id)")
        }
        let opencode = try #require(registry.first { $0.id == .opencode })
        #expect(opencode.accountCapacity == AccountRegistry.testedEnvelope)
    }

    @Test func extraOpenCodeAccountsGetTheirOwnProviderOnTheOpenCodeLane() {
        let extra = ProviderAccount(id: AccountID("work"), providerID: .opencode, label: "Work")
        let provider = AppComposition.provider(for: extra, credentials: CredentialStore())
        #expect(provider is OpenCodeProvider)
        #expect(provider.accountKey == extra.key)
        #expect(provider.pollingLane == .serial("opencode-cli"))
    }

    @Test func demosHarnessesAndTheTestHostNeverStartTheClient() {
        for arguments in [
            ["Pacemark", "--demo"],
            ["Pacemark", "--demo", "multi-20"],
            ["Pacemark", "--render-popover", "/tmp/out"],
            ["Pacemark", "--bench-ui", "settings"],
        ] {
            #expect(AppComposition.usesInertOpenCode(arguments: arguments, environment: realLaunch), "\(arguments)")
            #expect(AppComposition.makeOpenCodeCLISource(arguments: arguments, environment: realLaunch) is InertOpenCodeUsageSource)
        }
        let testHost = ["XCTestConfigurationFilePath": "/tmp/probe.xctestconfiguration"]
        #expect(AppComposition.makeOpenCodeCLISource(arguments: ["Pacemark"], environment: testHost) is InertOpenCodeUsageSource)
        // This process is the XCTest host, so the launch's shared source is inert too.
        #expect(AppComposition.usesInertOpenCode())
        #expect(!AppComposition.usesInertOpenCode(arguments: ["Pacemark"], environment: realLaunch))
    }

    @Test func theInertSourceStartsNothing() async {
        #expect(await InertOpenCodeUsageSource().capture(home: .builtIn) == .failed(.transient(.spawnFailed)))
    }

    @Test func aRealLaunchReadsThroughTheOfficialClient() {
        #expect(AppComposition.makeOpenCodeCLISource(arguments: ["Pacemark"], environment: realLaunch) is OpenCodeCLIUsageSource)
    }

    /// KTD18: the override only ever routes extra homes, and a release build ignores it.
    @Test func theExecutableOverrideIsDebugOnlyAndRoutedByHome() {
        let arguments = ["Pacemark", "--opencode-executable", "/tmp/opencode-v2"]
        #expect(AppComposition.makeOpenCodeCLISource(
            arguments: arguments, environment: realLaunch, buildAllowsOverride: true
        ) is OpenCodeExecutableOverrideRouter)
        #expect(AppComposition.makeOpenCodeCLISource(
            arguments: arguments, environment: realLaunch, buildAllowsOverride: false
        ) is OpenCodeCLIUsageSource)
        #expect(AppComposition.makeOpenCodeCLISource(
            arguments: arguments + ["--demo"], environment: realLaunch, buildAllowsOverride: true
        ) is InertOpenCodeUsageSource)
    }

    @Test func onlyTheOpenCodeGroupCarriesTheWorkspaceNote() {
        #expect(AccountsSettingsInteractions.providerGroupNote(for: .opencode) == "OpenCode reports only the active Console workspace")
        for providerID in [ProviderID.claude, .codex, .grok, .cursor, .copilot] {
            #expect(AccountsSettingsInteractions.providerGroupNote(for: providerID) == nil, "\(providerID)")
        }
    }
}
