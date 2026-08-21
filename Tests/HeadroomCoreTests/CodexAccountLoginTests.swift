import Foundation
import Testing
@testable import HeadroomCore

/// The account-scoped Codex handoff must route the official CLI at the account's
/// `CODEX_HOME` — and never leak anything else into the generated script.
@Suite struct CodexAccountLoginTests {
    @Test func builtInLoginCommandForcesReadableFileStoreAndDefaultHome() {
        #expect(CodexCLI.accountLoginCommand(codexHome: nil) == "env -u CODEX_HOME codex -c cli_auth_credentials_store=file login")
    }

    @Test func extraAccountCommandExportsCodexHomeQuoted() {
        let command = CodexCLI.accountLoginCommand(codexHome: "/Users/x/Library/Application Support/Headroom/Accounts/codex/abc")
        #expect(command == "CODEX_HOME='/Users/x/Library/Application Support/Headroom/Accounts/codex/abc' codex -c cli_auth_credentials_store=file login")
    }

    @Test func loginScriptExportsCodexHomeForExtraAccounts() {
        let script = CodexCLI.loginScript(executablePath: "/opt/homebrew/bin/codex", codexHome: "/tmp/home")
        #expect(script.contains("export CODEX_HOME='/tmp/home'"))
        #expect(script.contains("exec '/opt/homebrew/bin/codex' -c cli_auth_credentials_store=file login"))
        // The separate-account guidance appears only in the account variant.
        #expect(script.contains("kept separate"))
    }

    @Test func loginScriptOmitsCodexHomeForBuiltIn() {
        let script = CodexCLI.loginScript(executablePath: "/opt/homebrew/bin/codex")
        #expect(!script.contains("kept separate"))
        #expect(script.contains("unset CODEX_HOME"))
    }

    @Test func codexHomeWithSingleQuoteIsShellSafe() {
        let command = CodexCLI.accountLoginCommand(codexHome: "/tmp/o'brien")
        #expect(command.contains("'/tmp/o'\\''brien'"))
    }

    @Test func deviceCodeUsesTheSameAccountAndFileStoreDescriptor() {
        let command = CodexCLI.accountLoginCommand(codexHome: "/tmp/home", mode: .deviceCode)
        let script = CodexCLI.loginScript(executablePath: "/opt/homebrew/bin/codex", codexHome: "/tmp/home", mode: .deviceCode)

        #expect(command == "CODEX_HOME='/tmp/home' codex -c cli_auth_credentials_store=file login --device-auth")
        #expect(script.contains("export CODEX_HOME='/tmp/home'"))
        #expect(script.contains("exec '/opt/homebrew/bin/codex' -c cli_auth_credentials_store=file login --device-auth"))
        #expect(script.contains("device-code instructions"))
        #expect(!script.contains("Complete sign-in in the browser"))
    }

    @Test func completionMarkerUsesSameOfficialInvocationAndParsesAsZsh() throws {
        let script = CodexCLI.loginScript(
            executablePath: "/opt/homebrew/bin/codex",
            codexHome: "/tmp/home",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/setup pending",
                completedPath: "/tmp/setup complete"
            )
        )
        #expect(script.contains("'/opt/homebrew/bin/codex' -c cli_auth_credentials_store=file login"))
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(script.contains("HEADROOM_SETUP_OWNER=\"${setup_purpose}:standard:${handoff_generation}:$$\""))

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

    @Test func completionWrapperRecordsExitAndDeletesPendingScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-codex-wrapper-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scriptURL = directory.appendingPathComponent("setup.command")
        let marker = SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent("pending").path,
            completedPath: directory.appendingPathComponent("complete").path
        )
        let script = CodexCLI.loginScript(
            executablePath: "/usr/bin/true",
            codexHome: directory.path,
            completionMarker: marker
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try AccountStorage.prepareSetupCompletionMarker(
            marker,
            mode: .standard,
            purpose: .setup
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        process.environment = ["TERM": "xterm-256color"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.pendingPath))
        #expect(!FileManager.default.fileExists(atPath: scriptURL.path))
        #expect(AccountStorage.setupHandoffCompletion(marker: marker) == .succeeded)
        #expect(AccountStorage.setupHandoffPurpose(marker: marker) == .setup)
    }
}
