import Foundation
import Testing
@testable import HeadroomCore

/// Parsing-only coverage for the bounded login-shell search output. No real shell, npm,
/// or filesystem participates (KTD2).
struct CLIExecutableResolverSupplementalTests {
    private let executableMarker = "__HEADROOM_EXECUTABLE__"
    private let npmPrefixMarker = "__HEADROOM_NPM_PREFIX__"
    private let npmAbsentMarker = "__HEADROOM_NPM_ABSENT__"

    @Test func missingMarkerIsInvalidOutput() {
        #expect(parse("some startup noise") == .invalidOutput)
    }

    @Test func directHitLeavesNpmUnattempted() {
        let output = """
        startup noise
        \(executableMarker)
        /opt/homebrew/bin/claude
        """
        #expect(parse(output) == .completed(
            candidates: ["/opt/homebrew/bin/claude"],
            supplemental: .notAttempted
        ))
    }

    @Test func noneStrategyNeverAttemptsSupplementalDiscovery() {
        let output = "\(executableMarker)\n"
        #expect(parse(output, supplemental: .none) == .completed(
            candidates: [],
            supplemental: .notAttempted
        ))
    }

    @Test func npmAbsentMarkerReportsSourceUnavailable() {
        let output = """
        \(executableMarker)

        \(npmAbsentMarker)
        """
        #expect(parse(output) == .completed(candidates: [], supplemental: .sourceUnavailable))
    }

    @Test func validPrefixDerivesDocumentedBinLauncher() {
        let output = """
        \(executableMarker)

        \(npmPrefixMarker)
        /Users/Neil/.npm-global
        """
        #expect(parse(output) == .completed(
            candidates: [],
            supplemental: .candidate("/Users/Neil/.npm-global/bin/claude")
        ))
    }

    @Test func prefixIsNormalizedBeforeDerivation() {
        for prefix in [
            "/Users/Neil/.npm-global/",
            "/Users/Neil/tools/../.npm-global",
            "  /Users/Neil/.npm-global  ",
        ] {
            let output = "\(executableMarker)\n\n\(npmPrefixMarker)\n\(prefix)\n"
            #expect(parse(output) == .completed(
                candidates: [],
                supplemental: .candidate("/Users/Neil/.npm-global/bin/claude")
            ))
        }
    }

    @Test func malformedPrefixResponsesStayUnresolved() {
        let malformed = [
            "",
            "   ",
            ".npm-global",
            "npm-global/bin",
            "~/.npm-global",
            "npm warn config global deprecated\n/Users/Neil/.npm-global",
            "/Users/Neil/.npm-global\n/Users/Neil/.npm-global",
            "/Users/Neil/.npm\u{1B}[0m-global",
        ]
        for response in malformed {
            let output = "\(executableMarker)\n\n\(npmPrefixMarker)\n\(response)\n"
            #expect(
                parse(output) == .completed(candidates: [], supplemental: .unresolved),
                "Expected unresolved supplemental for \(response.debugDescription)"
            )
        }
    }

    @Test func brokenMarkerProtocolAfterDirectMissStaysUnresolved() {
        // The shell emits one npm marker whenever the direct lookup misses, so neither
        // marker after an empty direct section means the protocol broke.
        #expect(parse("\(executableMarker)\n") == .completed(
            candidates: [],
            supplemental: .unresolved
        ))
    }

    @Test func nonEmptyDirectSectionMeansTheShellDeliberatelySkippedNpm() {
        let output = """
        \(executableMarker)
        claude not found but printed anyway
        """
        #expect(parse(output) == .completed(
            candidates: ["claude not found but printed anyway"],
            supplemental: .notAttempted
        ))
    }

    @Test func aliasDefinitionIsCarriedAsOpaqueTextNeverParsedIntoAPath() {
        let output = """
        \(executableMarker)
        claude: aliased to /Users/Neil/.claude/local/claude
        """
        #expect(parse(output) == .completed(
            candidates: ["claude: aliased to /Users/Neil/.claude/local/claude"],
            supplemental: .notAttempted
        ))
    }

    @Test func npmQueryRunsInsideTheSameBoundedShellOperationAfterADirectMiss() {
        let command = CLIExecutableResolver.searchCommand(
            named: "claude",
            supplemental: .npmGlobalPrefix
        )
        #expect(command.contains(executableMarker))
        #expect(command.contains(npmPrefixMarker))
        #expect(command.contains(npmAbsentMarker))
        #expect(command.contains("command -v -- claude"))
        #expect(command.contains("npm prefix -g"))
        // KTD1a: npm is queried only after a direct miss, inside one shell invocation.
        #expect(command.contains("if [ -z \"$__headroom_found\" ]"))
        #expect(CLIExecutableResolver.loginShellTimeout == 5)

        let direct = CLIExecutableResolver.searchCommand(named: "codex", supplemental: .none)
        #expect(!direct.contains("npm"))
    }

    private func parse(
        _ output: String,
        supplemental: CLIExecutableSupplementalStrategy = .npmGlobalPrefix
    ) -> CLIExecutableShellResult {
        CLIExecutableResolver.parseSearchOutput(
            output,
            executableName: "claude",
            supplemental: supplemental
        )
    }
}
