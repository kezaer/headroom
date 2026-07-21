import Testing
import Foundation
@testable import HeadroomCore

/// A real (ANSI-stripped) capture of `claude`'s `/usage` panel, including the messy
/// intermediate render states the parser must survive. The settled values are:
/// session 100% used, week (all models) 38% used, week (Fable) 62% used.
private let usagePanelFixture = """
Settings Status Config Usage Stats
Session
Usage: 0 input, 0 output, 0 cache read, 0 cache write
Current session
██████████████████████████████████████████████████ 100% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
██████████████████▌ 37% used
Resets Jul 2 at 10am (America/Los_Angeles)
Scanning local sessions…
Settings Status Config Usage Stats
Current session
██████████████████████████████████████████████████ 100% used
Resets 10:10am (America/Los_Angeles)
Current week (all models)
███████████████████ 38% used
Resets Jul 2 at 10am (America/Los_Angeles)
Current week (Fable)
███████████████████████████████ 62% used
Resets Jul 2 at 10am (America/Los_Angeles)
What's contributing to your limits usage?
"""

struct ClaudeUsageParserTests {
    @Test func parsesSettledWindows() {
        let windows = ClaudeUsageParser.parse(usagePanelFixture)
        // Three windows, in canonical order: session, weekly (all models), other.
        #expect(windows.count == 3)
        #expect(windows[0].kind == .fiveHour)
        #expect(windows[0].percentUsed == 100)
        #expect(windows[0].resetLabel == "Resets 10:10am")

        #expect(windows[1].kind == .weekly)
        #expect(windows[1].percentUsed == 38)          // settled value, not the 37 mid-scan
        #expect(windows[1].resetLabel == "Resets Jul 2 at 10am")

        #expect(windows[2].kind == .other("Weekly (Fable)"))
        #expect(windows[2].percentUsed == 62)
    }

    @Test func lastRenderWins() {
        // The weekly window appears as 37% then 38%; the settled 38% must win.
        let windows = ClaudeUsageParser.parse(usagePanelFixture)
        #expect(windows.first { $0.kind == .weekly }?.percentUsed == 38)
    }

    @Test func toleratesUnknownAndEmpty() {
        #expect(ClaudeUsageParser.parse("").isEmpty)
        #expect(ClaudeUsageParser.parse("garbage with no windows\nRandom line").isEmpty)
    }

    @Test func ignoresParagraphMentioningWeeklyLimit() {
        // A long sentence mentioning "weekly usage limit" must not be parsed as a window.
        let text = "Until July 7, you can use up to 50% of your plan's weekly usage limit on Fable 5."
        #expect(ClaudeUsageParser.parse(text).isEmpty)
    }

    @Test func normalizesResetLabelRenderArtifacts() {
        let text = """
        Current week (all models)
        █████ 5% used
        Resets Jul 9  t 10am (America/Los_Angeles)
        """
        #expect(ClaudeUsageParser.parse(text).first?.resetLabel == "Resets Jul 9 at 10am")
    }

    @Test func toleratesDroppedLettersFromTUIRepaint() {
        let text = """
        Current week (Fable)
        ████████████████████████████████████████████▌ 89% us d
        R sets Jul 9 at 9:59am (America/Los_Angeles)
        """
        let window = ClaudeUsageParser.parse(text).first
        #expect(window?.kind == .other("Weekly (Fable)"))
        #expect(window?.percentUsed == 89)
        #expect(window?.resetLabel == "Resets Jul 9 at 9:59am")
    }

    @Test func extractsPlanTierFromHeader() {
        // The tier appears in the panel header line, e.g. "… · Claude Max".
        #expect(ClaudeUsageParser.plan(in: "Fable 5 with high effort · Claude Max  ~/dir") == "Max")
        #expect(ClaudeUsageParser.plan(in: "Sonnet 5 · Claude Pro") == "Pro")
        #expect(ClaudeUsageParser.plan(in: "Opus 4.8 · Claude Max 20x") == "Max 20x")
    }

    @Test func planTierDoesNotMatchClaudeCodeOrPromoText() {
        // "Claude Code" (the product name) and promo copy must not be read as a tier.
        #expect(ClaudeUsageParser.plan(in: "Claude Code v2.1.199") == nil)
        #expect(ClaudeUsageParser.plan(in: "up to 50% of your plan's weekly usage limit") == nil)
        #expect(ClaudeUsageParser.plan(in: "") == nil)
    }
}

struct ClaudeProviderTests {
    private func provider(_ result: ClaudePanelResult) -> ClaudeProvider {
        ClaudeProvider(source: MockClaudeSource(result: result),
                       now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    @Test func panelBecomesLiveSnapshot() async {
        let snap = await provider(.panel(usagePanelFixture)).fetchSnapshot()
        #expect(snap.freshness == .live)
        #expect(snap.windows.count == 3)
        // percentUsed 100 -> 0 remaining; 38 -> 62 remaining.
        #expect(snap.windows.first { $0.kind == .fiveHour }?.percentRemaining == 0)
        #expect(snap.windows.first { $0.kind == .weekly }?.percentRemaining == 62)
        #expect(snap.windows.first { $0.kind == .weekly }?.resetLabel == "Resets Jul 2 at 10am")
    }

    @Test func liveSnapshotCarriesPlanTier() async {
        let panel = """
        Fable 5 with high effort · Claude Max  ~/dir
        Current session
        ████ 16% used
        Resets 8:10pm (America/Los_Angeles)
        """
        let snap = await provider(.panel(panel)).fetchSnapshot()
        #expect(snap.planLabel == "Max")
    }

    @Test func missingCLIDegradesToNotLoggedIn() async {
        let snap = await provider(.cliNotFound).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeCLIMissing)
    }

    @Test func captureFailureIsTransient() async {
        let snap = await provider(.transientCapture).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeTransientCapture)
    }

    @Test func loggedOutPanelAsksToLogIn() async {
        let snap = await provider(.loginRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeLoginRequired)
    }

    @Test func loginRequiredResultReadsAsNeedsSignIn() async {
        // A fresh CLAUDE_CONFIG_DIR (extra account before its first sign-in) boots into
        // a first-run screen; the probe bails there before typing (an Enter on the
        // login selector would start a browser sign-in) and types the result. Must be
        // permanent — a transient blip would hide the account's Sign in affordance.
        let snap = await provider(.loginRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeLoginRequired)
    }

    @Test func probeClassifiesFirstRunScreens() {
        #expect(ClaudeUsageCLIProbe.isFirstRunScreen("Welcome!\nChoose the text style that looks best with your terminal"))
        #expect(ClaudeUsageCLIProbe.isFirstRunScreen("Select login method: 1. Claude account with subscription"))
        #expect(!ClaudeUsageCLIProbe.isFirstRunScreen("Current session\n38% used\nResets 2:15pm"))
    }

    @Test func bootClassifierFailsClosedBeforeInput() {
        #expect(ClaudeUsageCLIProbe.classifyBootText("") == .noOutput)
        #expect(ClaudeUsageCLIProbe.classifyBootText("Quick safety check: Is this a project you trust?") == .trustRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("Choose the text style that looks best") == .loginRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("""
        Claude Code v2.1.216
        Quick safety check: Is this a project you trust?
        ❯ Continue
        manual mode on · ← for agents
        """) == .trustRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("""
        Claude Code v2.1.216
        Select login method
        ❯ Claude account with subscription
        manual mode on · ← for agents
        """) == .loginRequired)
        #expect(ClaudeUsageCLIProbe.classifyBootText("A brand new onboarding screen") == .unknown)
        #expect(ClaudeUsageCLIProbe.classifyBootText("Claude Code\n? for shortcuts") == .ready)
    }

    @Test func bootClassifierRecognizesCurrentPrompt() {
        let currentPrompt = """
        Claude Code v2.1.216
        Opus 4.8 with high effort
        ────────────────────────────────────────────────
        ❯ Try "how do I log an error?"
        ────────────────────────────────────────────────
        manual mode on · ← for agents
        """

        #expect(ClaudeUsageCLIProbe.classifyBootText(currentPrompt) == .ready)
    }

    @Test func authStatusClassifierIsTypedAndFailsClosed() {
        #expect(ClaudeUsageCLIProbe.classifyAuthStatus(Data(#"{"loggedIn":true}"#.utf8)) == .loggedIn)
        #expect(ClaudeUsageCLIProbe.classifyAuthStatus(Data(#"{"loggedIn":false}"#.utf8)) == .loggedOut)
        #expect(ClaudeUsageCLIProbe.classifyAuthStatus(Data("unsupported".utf8)) == .unsupported)
    }

    @Test func builtInProbeCannotInheritAnotherClaudeHome() {
        let builtIn = ClaudeUsageCLIProbe.environment(
            inherited: ["CLAUDE_CONFIG_DIR": "/wrong", "PATH": "/bin"],
            overrides: [:],
            loginPath: "/resolved/bin",
            workingDirectory: "/workspace"
        )
        let extra = ClaudeUsageCLIProbe.environment(
            inherited: ["CLAUDE_CONFIG_DIR": "/wrong"],
            overrides: ["CLAUDE_CONFIG_DIR": "/exact"],
            loginPath: "/resolved/bin",
            workingDirectory: "/workspace"
        )
        #expect(builtIn["CLAUDE_CONFIG_DIR"] == nil)
        #expect(extra["CLAUDE_CONFIG_DIR"] == "/exact")
    }

    @Test func loginMethodSelectorReadsAsNeedsSignIn() async {
        let snap = await provider(.loginRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeLoginRequired)
    }

    @Test func trustPromptAsksUserToOpenClaude() async {
        let snap = await provider(.workspaceTrustRequired).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeTrustRequired)
    }

    @Test func unknownInteractiveSurfaceNeverMasqueradesAsLoginOrTrust() async {
        let snap = await provider(.unknownUI).fetchSnapshot()
        guard case .stale(let reason) = snap.freshness else { Issue.record("expected stale"); return }
        #expect(reason.providerSetupOutcome == .claudeUnknownUI)
    }
}
