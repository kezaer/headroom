import Foundation
import Testing
@testable import PacemarkCore

/// The account-scoped Grok handoff routes the official CLI through `GROK_HOME`.
/// Generated scripts contain only the executable, allowlisted arguments, and paths.
@Suite struct GrokAccountLoginTests {
    @Test func builtInLoginCommandUsesTheDefaultCLIHome() {
        #expect(GrokCLI.accountLoginCommand(grokHome: nil) == "env -u GROK_HOME grok login")
    }

    @Test func extraAccountCommandExportsGrokHomeQuoted() {
        let command = GrokCLI.accountLoginCommand(
            grokHome: "/Users/x/Library/Application Support/Pacemark/Accounts/grok/abc"
        )
        #expect(command == "GROK_HOME='/Users/x/Library/Application Support/Pacemark/Accounts/grok/abc' grok login")
    }

    @Test func clipboardFallbackUsesTheResolvedExecutable() {
        let command = GrokCLI.accountLoginCommand(
            grokHome: "/tmp/grok home",
            executablePath: "/Users/test/.grok/bin/grok"
        )
        #expect(command == "GROK_HOME='/tmp/grok home' '/Users/test/.grok/bin/grok' login")
    }

    @Test func deviceCodeUsesTheSameIsolatedAccountHome() {
        let command = GrokCLI.accountLoginCommand(grokHome: "/tmp/grok-home", mode: .deviceCode)
        let script = GrokCLI.loginScript(
            executablePath: "/opt/homebrew/bin/grok",
            grokHome: "/tmp/grok-home",
            mode: .deviceCode
        )

        #expect(command == "GROK_HOME='/tmp/grok-home' grok login --device-auth")
        #expect(script.contains("export GROK_HOME='/tmp/grok-home'"))
        #expect(script.contains("exec '/opt/homebrew/bin/grok' login --device-auth"))
        #expect(script.contains("device-code instructions"))
    }

    @Test func twoDeviceCodeScriptsRemainBoundToDistinctCredentialHomes() throws {
        let accountsBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("pacemark-grok-device-code-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: accountsBase) }
        let accounts = [
            ProviderAccount(id: AccountID("grok-personal"), providerID: .grok, label: "Personal", isBuiltIn: false),
            ProviderAccount(id: AccountID("grok-work"), providerID: .grok, label: "Work", isBuiltIn: false),
        ]

        let bindings = try accounts.map { account in
            let home = try AccountStorage.ensureDirectories(for: PacemarkOwnedHome(account)!, baseDirectoryURL: accountsBase)
            let configuredHome = ProviderAccountConfiguration.make(
                for: account,
                accountsBase: accountsBase
            ).grokHomeDirectory
            let script = GrokCLI.loginScript(
                executablePath: "/opt/homebrew/bin/grok",
                grokHome: configuredHome?.path,
                mode: .deviceCode
            )
            return (home, configuredHome, script)
        }

        #expect(bindings[0].0 != bindings[1].0)
        for binding in bindings {
            #expect(binding.0 == binding.1)
            #expect(FileManager.default.fileExists(atPath: binding.0.path))
            #expect(binding.2.contains("export GROK_HOME='\(binding.0.path)'"))
            #expect(binding.2.contains("exec '/opt/homebrew/bin/grok' login --device-auth"))
        }
        #expect(!bindings[0].2.contains(bindings[1].0.path))
        #expect(!bindings[1].2.contains(bindings[0].0.path))
    }

    @Test func loginHandoffUsesOnlyTheSelectedGrokHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pacemark-grok-login-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("grok")
        try """
        #!/bin/zsh
        [[ "$1" == login && "${GROK_HOME-}" == "$EXPECTED_GROK_HOME" ]]
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        for (name, home) in [("built-in", nil as String?), ("extra", root.appendingPathComponent("account").path)] {
            let script = root.appendingPathComponent("\(name).command")
            try GrokCLI.loginScript(executablePath: executable.path, grokHome: home)
                .write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path]
            process.environment = [
                "TERM": "xterm-256color",
                "GROK_HOME": "/tmp/wrong-account",
                "EXPECTED_GROK_HOME": home ?? "",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
    }

    @Test func generatedScriptIsRedactedAndParsesAsZsh() throws {
        let sensitiveSentinel = "credential-material-must-never-appear"
        let script = GrokCLI.loginScript(
            executablePath: "/opt/homebrew/bin/grok",
            grokHome: "/tmp/grok-home",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/setup pending",
                completedPath: "/tmp/setup complete"
            )
        )

        #expect(!script.contains(sensitiveSentinel))
        #expect(script.contains("'/opt/homebrew/bin/grok' login"))
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(script.contains("PACEMARK_SETUP_OWNER=\"${setup_purpose}:standard:${handoff_generation}:$$\""))

        let process = Process()
        let input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-n"]
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data(script.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func accountHomeWithSingleQuoteIsShellSafe() {
        let command = GrokCLI.accountLoginCommand(grokHome: "/tmp/o'brien")
        #expect(command.contains("'/tmp/o'\\''brien'"))
    }
}
