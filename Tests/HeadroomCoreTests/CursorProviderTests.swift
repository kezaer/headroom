import Foundation
import Testing
@testable import HeadroomCore

private struct StubCursorSource: CursorUsageSource {
    let result: CursorPanelResult
    func capturePanel() async -> CursorPanelResult { result }
}

@Suite struct CursorProviderTests {
    private func fixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "cursor-usage", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private var augustFirst2026: Date {
        ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z")!
    }

    @Test func liveOfficialPanelFixtureDecodesMonthlyIncludedUsage() async throws {
        let text = try fixture()
        let provider = CursorProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        )
        let snapshot = await provider.fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.providerID == .cursor)
        #expect(snapshot.planLabel == "Pro+")
        #expect(snapshot.windows.count == 1)
        // Fixture is a real non-zero live capture (Included 1% used); pins that the parser
        // reads the rendered percentage, not a hardcoded zero.
        #expect(snapshot.windows.first?.utilization == 1)
        #expect(snapshot.windows.first?.percentRemaining == 99)
        #expect(snapshot.windows.first?.kind == .billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60))
        #expect(snapshot.windows.first?.resetSchedule == .scheduled(
            ISO8601DateFormatter().date(from: "2026-09-01T23:59:59Z")!
        ))
        #expect(snapshot.windows.first?.resetLabel == "Resets Sep 1")
    }

    @Test func includedPercentReadsAnArbitraryMidRangeValue() throws {
        let text = try fixture().replacingOccurrences(
            of: "Included        1% used",
            with: "Included        73% used"
        )
        let parsed = try #require(CursorUsageParser.parse(text, now: augustFirst2026))
        #expect(parsed.includedPercentUsed == 73)
    }

    @Test func displayedResetDayDoesNotExpireAtMidnight() throws {
        let middayOnReset = try #require(ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z"))
        let parsed = try #require(CursorUsageParser.parse(try fixture(), now: middayOnReset))

        #expect(parsed.resetsAt == ISO8601DateFormatter().date(from: "2026-09-01T23:59:59Z"))
        #expect(parsed.resetLabel == "Resets Sep 1")
    }

    @Test func fixedOnDemandSpendDecodesWithoutChangingIncludedUsage() async throws {
        let text = try fixture().replacingOccurrences(
            of: "On-Demand       Disabled",
            with: "On-Demand       $12.50 / $100.00"
        )
        let parsed = try #require(CursorUsageParser.parse(text, now: augustFirst2026))
        #expect(parsed.includedPercentUsed == 1)
        #expect(parsed.onDemand == .fixed(usedDollars: 12.5, limitDollars: 100))

        let spend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(text)),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)
        #expect(spend.freshness == .live)
        #expect(spend.amount == 12.5)
        #expect(spend.currency == "usd")
        #expect(spend.periodLabel == "Resets Sep 1")
    }

    @Test func disabledOnDemandProducesAnExplicitNonApplicableSnapshot() async throws {
        let spend = await CursorOnDemandSpendProvider(
            source: StubCursorSource(result: .panel(try fixture())),
            now: { augustFirst2026 }
        ).fetchSpend(period: .currentMonth)
        #expect(spend.freshness == .live)
        #expect(spend.amount == nil)
        #expect(spend.currency == nil)
    }

    @Test func cliFailuresMapToTypedRedactedOutcomes() async {
        let cases: [(CursorPanelResult, ProviderSetupOutcome)] = [
            (.cliNotFound, .cursorCLIMissing),
            (.loginRequired, .cursorAuthAbsent),
            (.workspaceTrustRequired, .cursorTrustRequired),
            (.mcpApprovalRequired, .cursorMCPApprovalRequired),
            (.unknownUI, .cursorUnknownUI),
            (.transientCapture, .cursorTransientCapture),
        ]
        for (result, expected) in cases {
            let snapshot = await CursorProvider(source: StubCursorSource(result: result)).fetchSnapshot()
            guard case .stale(let reason) = snapshot.freshness else {
                Issue.record("expected stale Cursor snapshot")
                continue
            }
            #expect(reason == .providerSetup(expected))
        }
    }

    @Test func malformedPanelFailsSafe() async {
        let snapshot = await CursorProvider(
            source: StubCursorSource(result: .panel("Usage unavailable"))
        ).fetchSnapshot()
        #expect(snapshot.freshness == .stale(.providerSetup(.cursorTransientCapture)))
    }

    @Test func authStatusReadsOnlyTheOfficialBoolean() {
        #expect(CursorUsageCLIProbe.classifyAuthStatus(Data(#"{"isAuthenticated":true,"userEmail":"ignored@example.com"}"#.utf8)) == .loggedIn)
        #expect(CursorUsageCLIProbe.classifyAuthStatus(Data(#"{"isAuthenticated":false}"#.utf8)) == .loggedOut)
        #expect(CursorUsageCLIProbe.classifyAuthStatus(Data(#"{"status":"authenticated"}"#.utf8)) == .unsupported)
    }

    @Test func tuiInputRequiresThePromptAndSelectedUsageCommand() {
        #expect(CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nAsk (shift+tab to cycle)\nAuto"))
        #expect(CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nv2026.09.15-d2fe57e\nPlan, search, build anything\nAuto Balance"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nA new onboarding screen"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Ask (shift+tab to cycle)"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nWorkspace Trust Required\n[a] Trust this workspace"))
        #expect(!CursorUsageCLIProbe.isReadyPrompt("Cursor Agent\nMCP Server Approval Required\nPlan, search, build anything"))
        #expect(CursorUsageCLIProbe.isMCPApprovalPrompt("MCP Server Approval Required\nReview servers"))
        #expect(CursorUsageCLIProbe.isWorkspaceTrustPrompt("/!\\ Workspace Trust Required\n[a] Trust this workspace\n[q] Quit"))

        #expect(CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /usage\n/context"))
        // The live TUI pads the arrow-to-command gap with several spaces and trails the
        // row with a description; both must still classify as the selected /usage row.
        #expect(CursorUsageCLIProbe.isUsageAutocompleteSelected("→  /usage    Show plan and on-demand usage"))
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("/usage\n/context"))
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /context\n/usage"))
        // Token boundary: a differently-named command must never satisfy the gate.
        #expect(!CursorUsageCLIProbe.isUsageAutocompleteSelected("→ /usages\n/context"))

        #expect(CursorUsageCLIProbe.isUsagePanel("Monthly plan and on-demand usage\nIncluded 1% used"))
        #expect(!CursorUsageCLIProbe.isUsagePanel("Monthly plan and on-demand usage\nLoading…"))
        #expect(!CursorUsageCLIProbe.isUsagePanel("Included 1% used"))
    }

    @Test func cursorIsExplicitlySingleAccount() {
        #expect(CursorProvider(source: StubCursorSource(result: .transientCapture)).accountCapacity == 1)
    }

    @Test func executableDisappearingBeforeProbeFailsClosedWithoutPTYInput() async {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-removed-cursor-\(UUID().uuidString)")
        #expect(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data(),
            attributes: [.posixPermissions: 0o700]
        ))
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        try? FileManager.default.removeItem(at: executable)

        #expect(await CursorUsageCLIProbe(cursorPath: executable.path).capturePanel() == .cliNotFound)
    }

    @Test func freshWorkspaceTrustNeverReceivesPTYInput() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-trust")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        #expect(await probe.capturePanel() == .workspaceTrustRequired)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    @Test func mcpApprovalNeverReceivesPTYInput() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-mcp")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        #expect(await probe.capturePanel() == .mcpApprovalRequired)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    /// R2: the gate can paint after the ready frame. The old sleep-then-type path would
    /// have sent `/usage`, whose `a` is the trust menu's approve key.
    @Test(arguments: ["cursor-agent-late-trust", "cursor-agent-late-mcp"])
    func gatePaintedAfterReadyPromptNeverReceivesPTYInput(_ fixture: String) async throws {
        let (executable, workspace) = try fakeCursorAgent(named: fixture)
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )

        let expected: CursorPanelResult = fixture.hasSuffix("trust")
            ? .workspaceTrustRequired : .mcpApprovalRequired
        #expect(await probe.capturePanel() == expected)
        #expect(!FileManager.default.fileExists(atPath: workspace.appendingPathComponent("unexpected-input").path))
    }

    @Test func currentCursorPromptOpensUsagePanelThroughPTY() async throws {
        let (executable, workspace) = try fakeCursorAgent(named: "cursor-agent-ready")
        defer { try? FileManager.default.removeItem(at: workspace.deletingLastPathComponent()) }
        let probe = CursorUsageCLIProbe(
            cursorPath: executable.path,
            workingDirectory: workspace.path,
            bootTimeout: 4,
            panelTimeout: 4
        )
        let snapshot = await CursorProvider(source: probe, now: { augustFirst2026 }).fetchSnapshot()

        #expect(snapshot.freshness == .live)
        #expect(snapshot.planLabel == "Pro+")
        #expect(snapshot.windows.first?.utilization == 1)
        // The probe trusts only its own empty workspace up front; current CLIs honour
        // the flag, so most users never see the trust handoff.
        let argv = try String(contentsOf: workspace.appendingPathComponent("argv"), encoding: .utf8)
        #expect(argv.contains("--trust"))
    }

    private func fakeCursorAgent(named name: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-cursor-pty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(forResource: name, withExtension: "zsh"))
        let executable = root.appendingPathComponent("cursor-agent")
        try FileManager.default.copyItem(at: fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return (executable, root.appendingPathComponent("workspace", isDirectory: true))
    }

    @Test func probeRecoversWhenCursorAgentIsInstalledAfterProbeCreation() async {
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-late-cursor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: executable) }
        let path = MutableCursorExecutablePath()
        let probe = CursorUsageCLIProbe(cursorPathResolver: { path.value })

        #expect(await probe.capturePanel() == .cliNotFound)

        let script = """
        #!/bin/sh
        printf '%s' '{"isAuthenticated":false}'
        """
        #expect(FileManager.default.createFile(
            atPath: executable.path,
            contents: Data(script.utf8),
            attributes: [.posixPermissions: 0o700]
        ))
        path.value = executable.path

        #expect(await probe.capturePanel() == .loginRequired)
    }
}

private final class MutableCursorExecutablePath: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    var value: String? {
        get { lock.withLock { path } }
        set { lock.withLock { path = newValue } }
    }
}

@Suite struct CursorConnectionTests {
    @Test func workspaceTrustScriptUsesExactQuotedFolderWithoutAutoApproval() throws {
        let workspace = "/Users/test/Library/Application Support/Headroom/CursorProbe"
        let script = CursorCLI.workspaceTrustScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            workspaceDirectory: workspace,
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("--mode ask --workspace '/Users/test/Library/Application Support/Headroom/CursorProbe'"))
        #expect(script.contains("unset CURSOR_API_KEY CURSOR_API_ENDPOINT"))
        #expect(script.contains("[a] Trust this workspace"))
        // The handoff exists for CLIs that ignore `--trust`; the user decides there.
        #expect(!script.contains("--trust"))
        #expect(!script.contains("--force"))

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

    @Test func mcpApprovalScriptUsesOfficialCLIWithoutAutomaticApproval() throws {
        let script = CursorCLI.mcpApprovalScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            workspaceDirectory: "/tmp/Headroom CursorProbe",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("Review Cursor Agent’s external tools"))
        #expect(script.contains("--workspace '/tmp/Headroom CursorProbe'"))
        #expect(!script.contains("--approve-mcps"))

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

    @Test func loginHandoffClearsAPIOverridesBeforeRunningOfficialCLI() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-cursor-login-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("cursor-agent")
        try """
        #!/bin/zsh
        [[ "$1" == login && -z "${CURSOR_API_KEY-}" && -z "${CURSOR_API_ENDPOINT-}" ]]
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let script = root.appendingPathComponent("login.command")
        try CursorCLI.loginScript(executablePath: executable.path)
            .write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path]
        process.environment = [
            "TERM": "xterm-256color",
            "CURSOR_API_KEY": "test-override",
            "CURSOR_API_ENDPOINT": "https://example.invalid",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test func generatedLoginScriptUsesOnlyOfficialCommandAndParsesAsZsh() throws {
        let script = CursorCLI.loginScript(
            executablePath: "/Users/test/.local/bin/cursor-agent",
            completionMarker: SetupCompletionMarker(
                pendingPath: "/tmp/cursor pending",
                completedPath: "/tmp/cursor complete"
            )
        )
        #expect(script.contains("'/Users/test/.local/bin/cursor-agent' login"))
        #expect(script.contains("unset CURSOR_API_KEY CURSOR_API_ENDPOINT"))
        #expect(CursorCLI.manualLoginCommand(executablePath: "/Users/test/.local/bin/cursor-agent")
            == "env -u CURSOR_API_KEY -u CURSOR_API_ENDPOINT '/Users/test/.local/bin/cursor-agent' login")
        #expect(script.contains("complete:${setup_purpose}:${handoff_generation}:${setup_status}"))
        #expect(!script.localizedCaseInsensitiveContains("token"))

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
}
