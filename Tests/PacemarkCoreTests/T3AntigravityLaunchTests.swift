import Foundation
import Testing
@testable import PacemarkCore

struct T3AntigravityLaunchTests {
    @Test func autoRequiresBinaryAndStatOnlyTokenAndSystemIsExplicit() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileManager.default
        let settings = root.appendingPathComponent(".t3/userdata/settings.json")
        let tools = root.appendingPathComponent(".t3/tools/antigravity-acp/darwin-arm64")
        let executable = tools.appendingPathComponent("versions/fixture/antigravity")
        let expectedHash = "ac0a3dfd6dddb20962cecff6ee5fe65e19d3923be20e52c5ab52ff877f7e4c32"
        let directory = root.appendingPathComponent(".t3/userdata/providers/antigravity/\(expectedHash)/antigravity-acp")
        let token = directory.appendingPathComponent("antigravity-oauth-token")
        let probeHomes = root.appendingPathComponent("Pacemark/AntigravityHomes")
        for location in [settings.deletingLastPathComponent(), executable.deletingLastPathComponent(), directory] {
            try files.createDirectory(at: location, withIntermediateDirectories: true)
        }
        try Data(#"{"providerInstances":{"antigravity":{"driver":"antigravity","enabled":true}}}"#.utf8).write(to: settings)
        try Data(#"{"releaseId":"fixture"}"#.utf8).write(to: tools.appendingPathComponent("active.json"))
        try Data().write(to: executable)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let t3 = T3Installation(userHome: root, architecture: .arm64)
        let resolver = AntigravityLaunchResolver(
            t3: t3, probeHomesRoot: probeHomes, resolveSystemExecutable: { "/fixture/bin/agy" }
        )
        #expect(t3.antigravity() == nil)
        #expect(resolver.resolve()?.signInHome == .system)
        #expect(!files.fileExists(atPath: probeHomes.path))
        // An unreadable, empty fixture still qualifies by existence. It contains no token bytes.
        try Data().write(to: token)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: token.path)
        let result = try #require(resolver.resolve())
        #expect(result.executable == executable.path)
        #expect(t3.antigravity()?.dataDirectory.path == directory.path)
        guard case .t3Managed(let instance, let home) = result.signInHome else {
            Issue.record("Expected T3 launch")
            return
        }
        #expect(instance == "antigravity")
        #expect(result.signInHome.environmentOverrides == ["HOME": home.path])
        let link = home.appendingPathComponent(".gemini/antigravity-cli")
        #expect(try files.destinationOfSymbolicLink(atPath: link.path) == directory.path)
        #expect(resolver.resolve(preference: .systemCLI) == .init(executable: "/fixture/bin/agy", signInHome: .system))

        try Data(#"{"releaseId":"../fixture"}"#.utf8).write(to: tools.appendingPathComponent("active.json"))
        #expect(t3.antigravity() == nil)
        #expect(resolver.resolve()?.signInHome == .system)
    }

    @Test func probeLinkReplacementAndParentChecksFailClosed() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileManager.default
        let home = root.appendingPathComponent("Pacemark/AntigravityHomes/instance")
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let location = home.appendingPathComponent(".gemini/antigravity-cli")
        let linker = ProbeHomeLinker()
        for folder in [first, second] {
            try files.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        #expect(linker.ensureSignInLink(probeHome: home, target: first))
        let firstLink = try files.attributesOfItem(atPath: location.path)[.systemFileNumber] as? UInt64
        #expect(linker.ensureSignInLink(probeHome: home, target: first))
        #expect(try files.attributesOfItem(atPath: location.path)[.systemFileNumber] as? UInt64 == firstLink)
        #expect(linker.ensureSignInLink(probeHome: home, target: second))
        #expect(try files.destinationOfSymbolicLink(atPath: location.path) == second.path)
        #expect(try files.contentsOfDirectory(atPath: location.deletingLastPathComponent().path) == ["antigravity-cli"])
        try files.removeItem(at: location)
        try Data("keep".utf8).write(to: location)
        #expect(!linker.ensureSignInLink(probeHome: home, target: second))
        #expect(try String(contentsOf: location, encoding: .utf8) == "keep")
        try files.removeItem(at: location.deletingLastPathComponent())
        try files.createSymbolicLink(at: location.deletingLastPathComponent(), withDestinationURL: first)
        #expect(!linker.ensureSignInLink(probeHome: home, target: second))
        #expect(try files.contentsOfDirectory(atPath: first.path).isEmpty)
    }

    @Test func signedOutMemoryMigratesAndSticksToEachHome() async throws {
        let defaults = DemoMemoryDefaults()
        let prefs = Preferences(defaults: defaults)
        #expect(prefs.antigravitySourcePreference == .autoPreferT3)
        prefs.antigravitySourcePreference = .systemCLI
        #expect(Preferences(defaults: defaults).antigravitySourcePreference == .systemCLI)
        prefs.antigravitySignedOut = true
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fake-agy")
        let probeHome = root.appendingPathComponent("probe-home")
        let log = root.appendingPathComponent("calls")
        try Data(#"""
        case "$1" in
          --version) printf '%s\n' '1.5.13' ;;
          *) printf '%s\n' "$HOME" >> "$CALL_LOG"
             if [ "$(command -v open)" = /usr/bin/open ] || open; then exit 2; fi
             printf '%s\n' 'Authentication required. Please visit the URL to log in:' >&2
             exit 1 ;;
        esac
        """#.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let system = AntigravityLaunchPlan(executable: script.path, signInHome: .system)
        let t3 = AntigravityLaunchPlan(
            executable: script.path, signInHome: .t3Managed(instanceID: "fixture", probeHome: probeHome)
        )
        let source = AntigravityCLIUsageSource(
            resolveLaunch: { prefs.antigravitySourcePreference == .systemCLI ? system : t3 },
            rechecksLaunch: true, resolveLoginPath: { "/usr/bin:/bin" },
            inheritedEnvironment: { ["CALL_LOG": log.path, "HOME": root.path] },
            workingDirectory: root.appendingPathComponent("work").path, deadline: 3, versionDeadline: 3,
            interpreter: "/bin/sh", memory: .preferences(prefs)
        )
        #expect(!prefs.antigravitySignedOut)
        #expect(prefs.antigravitySignedOutHomes == ["system"])
        #expect(await source.capture() == .failed(.signedOut))
        #expect(!FileManager.default.fileExists(atPath: log.path))
        prefs.antigravitySourcePreference = .autoPreferT3
        #expect(await source.capture() == .failed(.signedOutInT3))
        let selection = await UserRequestedProbeContext.$origins.withValue([.sourceSelection]) {
            await source.capture()
        }
        #expect(selection == .failed(.signedOutInT3))
        #expect(try String(contentsOf: log, encoding: .utf8) == probeHome.path + "\n")
        let refresh = await UserRequestedProbeContext.$origins.withValue([.fullRefresh]) {
            await source.capture()
        }
        #expect(refresh == .failed(.signedOutInT3))
        #expect(prefs.antigravitySignedOutHomes == ["system", "t3:fixture"])
        prefs.antigravitySourcePreference = .systemCLI
        #expect(await source.capture() == .failed(.signedOut))
        #expect(try String(contentsOf: log, encoding: .utf8) == String(repeating: probeHome.path + "\n", count: 2))
    }

    @Test func switchingSourcesDoesNotForgetTheNoTurnSafetyStop() async throws {
        let defaults = DemoMemoryDefaults()
        let prefs = Preferences(defaults: defaults)
        let root = try fixtureDirectory()
        let calls = root.appendingPathComponent("calls")
        defer { try? FileManager.default.removeItem(at: root) }
        let system = root.appendingPathComponent("system-agy")
        let unmanaged = root.appendingPathComponent("t3-agy")
        let sourceScript = #"""
        case "$1" in
          --version) printf '%s\n' '1.5.13' ;;
          *) printf '%s\n' "$0" >> "$CALL_LOG"
             printf '%s\n' '{"status":"SUCCESS","stats":{"num_turns":1,"total_tokens":3}}' ;;
        esac
        """#
        for script in [system, unmanaged] {
            try Data(sourceScript.utf8).write(to: script)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        }
        @Sendable func makeSource() -> AntigravityCLIUsageSource {
            AntigravityCLIUsageSource(
                resolveLaunch: {
                    prefs.antigravitySourcePreference == .systemCLI
                        ? .init(executable: system.path, signInHome: .system)
                        : .init(executable: unmanaged.path, signInHome: .t3Managed(instanceID: "t3-fixture", probeHome: root))
                },
                rechecksLaunch: true, resolveLoginPath: { "/usr/bin:/bin" },
                inheritedEnvironment: { ["CALL_LOG": calls.path] },
                workingDirectory: root.path, deadline: 3, versionDeadline: 3,
                interpreter: "/bin/sh", memory: .preferences(prefs)
            )
        }
        let source = makeSource()
        #expect(await source.capture() == .failed(.unsupportedClient))
        prefs.antigravitySourcePreference = .systemCLI
        #expect(await source.capture() == .failed(.unsupportedClient))
        prefs.antigravitySourcePreference = .autoPreferT3
        #expect(await source.capture() == .failed(.unsupportedClient))
        #expect(await makeSource().capture() == .failed(.unsupportedClient))
        let attempts = try String(contentsOf: calls, encoding: .utf8).split(whereSeparator: \.isNewline)
        #expect(attempts.map(String.init) == [unmanaged.path, system.path])
    }
}
