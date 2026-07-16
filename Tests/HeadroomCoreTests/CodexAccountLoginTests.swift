import Foundation
import Testing
@testable import HeadroomCore

/// The account-scoped Codex handoff must route the official CLI at the account's
/// `CODEX_HOME` — and never leak anything else into the generated script.
@Suite struct CodexAccountLoginTests {
    @Test func builtInLoginCommandIsUnchanged() {
        #expect(CodexCLI.accountLoginCommand(codexHome: nil) == "codex login")
    }

    @Test func extraAccountCommandExportsCodexHomeQuoted() {
        let command = CodexCLI.accountLoginCommand(codexHome: "/Users/x/Library/Application Support/Headroom/Accounts/codex/abc")
        #expect(command == "CODEX_HOME='/Users/x/Library/Application Support/Headroom/Accounts/codex/abc' codex login")
    }

    @Test func loginScriptExportsCodexHomeForExtraAccounts() {
        let script = CodexCLI.loginScript(executablePath: "/opt/homebrew/bin/codex", codexHome: "/tmp/home")
        #expect(script.contains("export CODEX_HOME='/tmp/home'"))
        #expect(script.contains("exec '/opt/homebrew/bin/codex' login"))
        // The separate-account guidance appears only in the account variant.
        #expect(script.contains("kept separate"))
    }

    @Test func loginScriptOmitsCodexHomeForBuiltIn() {
        let script = CodexCLI.loginScript(executablePath: "/opt/homebrew/bin/codex")
        #expect(!script.contains("CODEX_HOME"))
        #expect(!script.contains("kept separate"))
    }

    @Test func codexHomeWithSingleQuoteIsShellSafe() {
        let command = CodexCLI.accountLoginCommand(codexHome: "/tmp/o'brien")
        #expect(command.contains("'/tmp/o'\\''brien'"))
    }
}
