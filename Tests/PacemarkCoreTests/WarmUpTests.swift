import Foundation
import Testing
@testable import PacemarkCore

struct WarmUpPlannerTests {
    private static let now = Date(timeIntervalSince1970: 1_800_036_000)
    private static let fiveHour: TimeInterval = 18_000
    private static let week: TimeInterval = 604_800
    private let account = ProviderAccount.builtIn(for: .claude).key

    @Test(arguments: [
        ResetSchedule.unresolved(.absent),
        .unresolved(.elapsed),
        .scheduled(now.addingTimeInterval(-1)),
        .scheduled(now),
        .scheduled(now.addingTimeInterval(fiveHour * 0.97)),
        .scheduled(now.addingTimeInterval(fiveHour)),
    ])
    func idleResetShapes(schedule: ResetSchedule) {
        #expect(decide([window(reset: schedule)]) == [WindowKind.fiveHour.persistentID])
    }

    @Test(arguments: [0.001, 20.0, 100.0, 110.0, -1.0, Double.nan])
    func rejectsAnythingExceptExactlyZero(used: Double) {
        #expect(decide([window(used: used)]).isEmpty)
        #expect(decide([window(used: used, reset: .scheduled(Self.now.addingTimeInterval(Self.fiveHour)))]).isEmpty)
    }

    @Test func absentFiveHourLimitCannotStartFromAWeeklyOnlyReading() {
        let weekly = window(kind: .weekly, reset: .unresolved(.absent))
        #expect(decide([weekly], enabled: [.fiveHour]).isEmpty)
        #expect(decide([weekly], enabled: [.fiveHour, .weekly]) == [WindowKind.weekly.persistentID])
    }

    @Test(arguments: [true, false])
    func legacyMasterSwitchFollowsSavedSelections(selected: Bool) throws {
        let selection = WarmUpSettings.Selection(account: account, window: .weekly)
        let original = WarmUpSettings(enabled: selected ? [selection] : [])
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "isEnabled")
        let restored = try JSONDecoder().decode(WarmUpSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(restored.isEnabled == selected)
        #expect(restored.enabled == original.enabled)
    }

    @Test func masterSwitchSuppressesSelectedLimits() {
        let settings = WarmUpSettings(isEnabled: false, enabled: [.init(account: account, window: .fiveHour)], activeHours: .anyTime)
        let snapshot = UsageSnapshot(providerID: .claude, windows: [window()], planLabel: nil, capturedAt: Self.now, freshness: .live)
        #expect(WarmUpPlanner.idleDeadlines(for: account, snapshot: snapshot, settings: settings, ledger: .init(), now: Self.now).isEmpty)
    }

    @Test func runningAndUnreliableResets() {
        #expect(decide([window(reset: .scheduled(Self.now.addingTimeInterval(Self.fiveHour * 0.97 - 1)))]).isEmpty)
        #expect(decide([window(reset: .unresolved(.unparseable))]).isEmpty)
        #expect(decide([window(reset: .unresolved(.invalidZone))]).isEmpty)
        #expect(decide([window(reset: .unresolved(.legacyUnknown))]).isEmpty)
    }

    @Test func staleUnavailableExpiredAndFutureEvidence() {
        let old = Self.now.addingTimeInterval(-WarmUpPlanner.maximumReadingAge - 1)
        #expect(decide([window()], freshness: .pending).isEmpty)
        #expect(decide([window()], freshness: .stale(.decode("Fixture"))).isEmpty)
        #expect(decide([window()], capturedAt: old).isEmpty)
        #expect(decide([window()], capturedAt: nil).isEmpty)
        #expect(decide([window()], capturedAt: Self.now.addingTimeInterval(10)).isEmpty)
        #expect(decide([window(freshness: .stale(observedAt: old))]).isEmpty)
        #expect(decide([window(freshness: .unavailable(since: old))]).isEmpty)
        #expect(decide([window(observedAt: old)]).isEmpty)
        #expect(decide([window(limited: true)]).isEmpty)
    }

    @Test func onlyGeminiPoolCanStartAntigravityLimits() {
        let account = ProviderAccount.builtIn(for: .antigravity).key
        let gemini = WarmUpSettings.windows(for: .antigravity)
        let kinds = gemini + [AntigravityProvider.windowKind(.claudeAndGPT, .weekly)]
        let settings = WarmUpSettings(enabled: Set(kinds.map { .init(account: account, window: $0) }), activeHours: .anyTime)
        let reading = UsageSnapshot(providerID: .antigravity, windows: kinds.map { window(kind: $0, reset: .unresolved(.absent)) },
                                    planLabel: nil, capturedAt: Self.now, freshness: .live)
        #expect(Set(WarmUpPlanner.idleDeadlines(for: account, snapshot: reading, settings: settings, ledger: .init(), now: Self.now).keys)
                == Set(gemini.map(\.persistentID)))
    }

    @Test func selectedLimitsShareOneDecision() {
        let fable = WindowKind.other("Weekly (Fable)")
        let spark = WindowKind.other("GPT-5.3-Codex-Spark Weekly")
        let windows = [
            window(), window(kind: .weekly, reset: .scheduled(Self.now.addingTimeInterval(Self.week - 600))),
            window(kind: fable, reset: .scheduled(Self.now.addingTimeInterval(Self.week))),
            window(kind: spark),
        ]
        let selection: Set<WindowKind> = [.fiveHour, .weekly, fable, spark]
        #expect(decide(windows, enabled: selection) == Set([WindowKind.fiveHour, .weekly].map(\.persistentID)))
        #expect(decide(windows, enabled: [.weekly]) == [WindowKind.weekly.persistentID])
        #expect(decide(windows, enabled: []).isEmpty)
        #expect(decide(windows, enabled: selection, selectedAccount: .init(providerID: .claude, accountID: AccountID("other"))).isEmpty)
    }

    @Test func onlyOverallLimitsHaveRollingDurations() {
        let weekly = WindowKind.other("Weekly (Fable)")
        #expect(decide([
            window(kind: weekly, reset: .scheduled(Self.now.addingTimeInterval(Self.week))),
        ], enabled: [weekly]).isEmpty)
        let billing = WindowKind.billingPeriod(label: "Monthly", duration: 30 * 86_400)
        #expect(decide([window(kind: billing)], enabled: [billing]).isEmpty)
        #expect(decide([window(kind: .other("Unknown"))], enabled: [.other("Unknown")]).isEmpty)
    }

    @Test func elapsedResetNeedsAnObservationAtOrAfterIt() {
        let reset = Self.now.addingTimeInterval(-30)
        let prior = reset.addingTimeInterval(-1)
        #expect(decide([window(reset: .scheduled(reset))], capturedAt: prior).isEmpty)
        #expect(decide([window(reset: .scheduled(reset), observedAt: prior)]).isEmpty)
        #expect(decide([window(reset: .scheduled(reset), observedAt: reset)]) == [WindowKind.fiveHour.persistentID])
        #expect(decide([window(reset: .scheduled(reset))]) == [WindowKind.fiveHour.persistentID])
    }

    @Test func weeklyFarAwayMarginIsCappedAtTenMinutes() {
        let withinMargin = window(kind: .weekly, reset: .scheduled(Self.now.addingTimeInterval(Self.week - 600)))
        let outsideMargin = window(kind: .weekly, reset: .scheduled(Self.now.addingTimeInterval(Self.week - 601)))
        #expect(decide([withinMargin], enabled: [.weekly]) == [WindowKind.weekly.persistentID])
        #expect(decide([outsideMargin], enabled: [.weekly]).isEmpty)
    }

    @Test(arguments: [true, false])
    func successfulWeeklySendBlocksFurtherZeroReadingsUntilFreshEvidenceAfterReset(hasDeadline: Bool) throws {
        let weeklyID = WindowKind.weekly.persistentID
        let sentAt = Self.now.addingTimeInterval(30)
        let scheduled = Self.now.addingTimeInterval(Self.week)
        let deadline = hasDeadline ? scheduled : sentAt.addingTimeInterval(Self.week)
        let reset: ResetSchedule = hasDeadline ? .scheduled(scheduled) : .unresolved(.absent)
        let settings = WarmUpSettings(enabled: [.init(account: account, window: .weekly)], activeHours: .anyTime)
        let snapshot = UsageSnapshot(providerID: account.providerID, windows: [window(kind: .weekly, reset: reset)],
                                     planLabel: nil, capturedAt: Self.now, freshness: .live)
        var ledger = WarmUpLedger()
        let deadlines = WarmUpPlanner.idleDeadlines(
            for: account, snapshot: snapshot, settings: settings, ledger: ledger, now: Self.now
        ).mapValues { $0.deadline(after: sentAt) }
        let plannedDeadline = try #require(deadlines[weeklyID])
        #expect(!(plannedDeadline < deadline) && !(plannedDeadline > deadline))
        let claim = ledger.reserve(account, identity: nil, at: Self.now)
        ledger.finish(claim, outcome: .sent, resetDeadlines: deadlines)
        let defaults = DemoMemoryDefaults()
        #expect(ledger.save(to: defaults))
        ledger = try #require(WarmUpLedger.load(from: defaults))

        for offset in [1_800.0, 3_600.0, 18_000.0] {
            let later = sentAt.addingTimeInterval(offset)
            // Even a new full-horizon reset cannot reopen the warmed cycle.
            let movedReset = window(kind: .weekly, reset: .scheduled(later.addingTimeInterval(Self.week)))
            #expect(decide([movedReset], enabled: [.weekly], at: later, capturedAt: later, ledger: ledger).isEmpty)
            #expect(decide([window(kind: .weekly)], enabled: [.weekly], at: later, capturedAt: later, ledger: ledger).isEmpty)
        }
        let afterReset = deadline.addingTimeInterval(1)
        let preResetZero = window(kind: .weekly, observedAt: deadline.addingTimeInterval(-1))
        let atResetZero = window(kind: .weekly, observedAt: deadline)
        for zero in [preResetZero, atResetZero] {
            #expect(decide([zero], enabled: [.weekly], at: afterReset, capturedAt: afterReset, ledger: ledger).isEmpty)
        }
        #expect(decide([window(kind: .weekly, used: 1)], enabled: [.weekly],
                       at: afterReset, capturedAt: afterReset, ledger: ledger).isEmpty)
        #expect(decide([window(kind: .weekly)], enabled: [.weekly],
                       at: afterReset, capturedAt: afterReset, ledger: ledger) == [weeklyID])
        // A weekly lock never blocks the five-hour window.
        let afterCooldown = Self.now.addingTimeInterval(1_800)
        #expect(decide([window()], at: afterCooldown, capturedAt: afterCooldown,
                       ledger: ledger) == [WindowKind.fiveHour.persistentID])
    }

    @Test func providerAndConsentIdentity() {
        let identity = AccountIdentity.codex(accountID: "fixture-identity")!
        let other = AccountIdentity.codex(accountID: "different-fixture-identity")!
        let codex = ProviderAccount.builtIn(for: .codex).key
        let settings = WarmUpSettings(enabled: [.init(account: codex, window: .fiveHour, identity: identity)], activeHours: .anyTime)
        func check(_ snapshotIdentity: AccountIdentity) -> Set<String> {
            let snapshot = UsageSnapshot(providerID: .codex, windows: [window()], planLabel: nil,
                                         capturedAt: Self.now, freshness: .live, identity: .known(snapshotIdentity))
            return Set(WarmUpPlanner.idleDeadlines(
                for: codex, snapshot: snapshot, settings: settings, ledger: .init(), now: Self.now
            ).keys)
        }
        #expect(check(identity) == [WindowKind.fiveHour.persistentID])
        #expect(check(other).isEmpty)
        for provider in [ProviderID.grok, .cursor, .copilot, .opencode, .antigravity] {
            let key = ProviderAccount.builtIn(for: provider).key
            let snapshot = UsageSnapshot(providerID: provider, windows: [window()], planLabel: nil,
                                         capturedAt: Self.now, freshness: .live)
            let settings = WarmUpSettings(enabled: [.init(account: key, window: .fiveHour)], activeHours: .anyTime)
            #expect(WarmUpPlanner.idleDeadlines(
                for: key, snapshot: snapshot, settings: settings, ledger: .init(), now: Self.now
            ).isEmpty)
        }
    }

    @Test func cooldownDailyCapAndIndependentAccounts() {
        let calendar = utcCalendar()
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 12))!
        var ledger = WarmUpLedger()
        let attempt = ledger.reserve(account, identity: nil, at: noon.addingTimeInterval(-1_799))
        ledger.finish(attempt, outcome: .failed(.timedOut))
        #expect(decide([window()], at: noon, capturedAt: noon, ledger: ledger).isEmpty)
        #expect(!decide([window()], at: noon.addingTimeInterval(1), capturedAt: noon, ledger: ledger).isEmpty)
        for hours in [1.0, 2, 3] {
            ledger.reserve(account, identity: nil, at: noon.addingTimeInterval(-hours * 3_600))
        }
        let later = noon.addingTimeInterval(3_600)
        #expect(decide([window()], at: later, capturedAt: later, ledger: ledger).isEmpty)
        let tomorrow = noon.addingTimeInterval(86_400)
        #expect(!decide([window()], at: tomorrow, capturedAt: tomorrow, ledger: ledger).isEmpty)
        let otherKey = AccountKey(providerID: .claude, accountID: AccountID("other"))
        #expect(ledger.canAttempt(otherKey, identity: nil, now: later, calendar: calendar))
        #expect(!ledger.canAttempt(account, identity: nil, now: noon.addingTimeInterval(-4_000), calendar: calendar))
    }

    @Test func localActiveHoursAndOvernight() {
        var calendar = utcCalendar()
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26))!
        func allowed(_ hours: WarmUpSettings.ActiveHours, _ minute: Int) -> Bool {
            let date = midnight.addingTimeInterval(Double(minute * 60))
            return !decide([window()], at: date, capturedAt: date, hours: hours, calendar: calendar).isEmpty
        }
        #expect(!allowed(.standard, 419))
        #expect(allowed(.standard, 420))
        #expect(allowed(.standard, 1379))
        #expect(!allowed(.standard, 1380))
        #expect(allowed(.anyTime, 0))
        let overnight = WarmUpSettings.ActiveHours.interval(startMinute: 22 * 60, endMinute: 7 * 60)
        #expect(allowed(overnight, 0))
        #expect(allowed(overnight, 23 * 60))
        #expect(!allowed(overnight, 7 * 60))
        #expect(!allowed(.interval(startMinute: 0, endMinute: 0), 0))
    }

    @Test(arguments: [true, false])
    func dstActiveHoursAndDailyCap(springForward: Bool) throws {
        var calendar = utcCalendar()
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        let dates = springForward
            ? ["2026-03-08T01:30:00-05:00", "2026-03-08T03:00:00-04:00", "2026-03-08T03:30:00-04:00"]
            : ["2026-11-01T01:30:00-04:00", "2026-11-01T01:30:00-05:00", "2026-11-01T02:00:00-05:00"]
        let readings = try dates.map { try #require(formatter.date(from: $0)) }
        let hours = WarmUpSettings.ActiveHours.interval(startMinute: 90, endMinute: springForward ? 210 : 120)
        #expect(hours.contains(readings[0], calendar: calendar))
        #expect(hours.contains(readings[1], calendar: calendar))
        #expect(!hours.contains(readings[2], calendar: calendar))

        let midnight = calendar.startOfDay(for: readings[0])
        let nextMidnight = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        #expect(nextMidnight.timeIntervalSince(midnight) == (springForward ? 23 : 25) * 3_600)
        var ledger = WarmUpLedger()
        for hour in [0.0, 1, 2, 3] {
            let attemptTime = midnight.addingTimeInterval(hour * 3_600)
            #expect(ledger.canAttempt(account, identity: nil, now: attemptTime, calendar: calendar))
            ledger.reserve(account, identity: nil, at: attemptTime)
        }
        #expect(!ledger.canAttempt(account, identity: nil, now: nextMidnight.addingTimeInterval(-1), calendar: calendar))
        #expect(ledger.canAttempt(account, identity: nil, now: nextMidnight, calendar: calendar))
    }

    private func window(
        kind: WindowKind = .fiveHour, used: Double = 0, reset: ResetSchedule = .unresolved(.absent),
        freshness: UsageWindowFreshness = .live, observedAt: Date? = nil, limited: Bool = false
    ) -> UsageWindow {
        UsageWindow(kind: kind, utilization: used, resetSchedule: reset,
                    freshness: freshness, observedAt: observedAt, isLimited: limited)
    }

    private func decide(
        _ windows: [UsageWindow], enabled: Set<WindowKind> = [.fiveHour], selectedAccount: AccountKey? = nil,
        at now: Date = Self.now, capturedAt: Date? = Self.now, freshness: Freshness = .live,
        hours: WarmUpSettings.ActiveHours = .anyTime, ledger: WarmUpLedger = .init(),
        calendar: Calendar = utcCalendar()
    ) -> Set<String> {
        let settings = WarmUpSettings(enabled: Set(enabled.map { .init(account: selectedAccount ?? account, window: $0) }),
                                      activeHours: hours)
        let snapshot = UsageSnapshot(providerID: account.providerID, windows: windows, planLabel: nil,
                                     capturedAt: capturedAt, freshness: freshness)
        return Set(WarmUpPlanner.idleDeadlines(for: account, snapshot: snapshot, settings: settings, ledger: ledger,
                                               now: now, calendar: calendar).keys)
    }
}

struct WarmUpPersistenceTests {
    @Test func failureWireFormat() throws {
        let cases: [(WarmUpFailure, String)] = [(.cliNotFound, "cliNotFound"), (.workspaceUnavailable, "workspaceUnavailable"),
            (.launchFailed, "launchFailed"), (.timedOut, "timedOut"), (.clientFailed, "clientFailed"),
            (.signedOut, "signedOut"), (.rejectedArguments, "rejectedArguments"), (.exitedNonZero(19), "19")]
        for (failure, wire) in cases {
            let data = try JSONEncoder().encode(wire)
            #expect(try JSONDecoder().decode(WarmUpFailure.self, from: data) == failure)
            #expect(try JSONEncoder().encode(failure) == data)
        }
    }

    @Test func geminiLimitsPersist() {
        let defaults = DemoMemoryDefaults()
        let key = ProviderAccount.builtIn(for: .antigravity).key
        let kinds = WarmUpSettings.windows(for: .antigravity)
        let valid = Set(kinds.map { WarmUpSettings.Selection(account: key, window: $0) })
        WarmUpSettings(enabled: valid.union([.init(account: key, window: .weekly)])).save(to: defaults)
        #expect(WarmUpSettings.load(from: defaults).enabled == valid)
        for (windows, expected) in [([], nil), ([kinds[0]], "5h"), ([kinds[1]], "weekly"), (kinds, "5h + weekly")] {
            var ledger = WarmUpLedger()
            let attempt = ledger.reserve(key, identity: nil, at: .now)
            ledger.finish(attempt, outcome: .sent, resetDeadlines: Dictionary(uniqueKeysWithValues: windows.map { ($0.persistentID, Date.now) }))
            #expect(ledger.attempts.last?.startedLimits == expected)
        }
    }

    @Test func settingsRoundTrip() {
        let defaults = DemoMemoryDefaults()
        #expect(WarmUpSettings.load(from: defaults) == .init())
        let key = ProviderAccount.builtIn(for: .claude).key
        let regular: Set<WarmUpSettings.Selection> = [.init(account: key, window: .fiveHour), .init(account: key, window: .weekly)]
        let settings = WarmUpSettings(enabled: regular.union([
            .init(account: key, window: .other("Weekly (Fable)")),
            .init(account: key, window: .other("Weekly (Sonnet)")),
            .init(account: key, window: .other("GPT-5.3-Codex-Spark Weekly")),
        ]), activeHours: .anyTime)
        settings.save(to: defaults)
        #expect(defaults.data(forKey: "t3.warmUp.v1") != nil)
        #expect(WarmUpSettings.load(from: defaults) == .init(enabled: regular, activeHours: .anyTime))
    }

    @Test func ledgerRoundTripAndAliasGuard() throws {
        let defaults = DemoMemoryDefaults()
        let claude = ProviderAccount.builtIn(for: .claude).key
        let alias = AccountKey(providerID: .claude, accountID: AccountID("alias"))
        let identity = try #require(AccountIdentity.claude(accountUUID: "35A235D1-A1B7-4A5F-B607-F02FC9490F6A", organizationUUID: nil))
        let now = Date(timeIntervalSince1970: 1_800_036_000)
        var ledger = WarmUpLedger()
        let claim = ledger.reserve(claude, identity: identity, at: now)
        #expect(ledger.save(to: defaults))
        let afterRestart = try #require(WarmUpLedger.load(from: defaults))
        #expect(afterRestart.lastAttempt(for: claude, identity: identity)?.outcome == .reserved)
        #expect(!afterRestart.canAttempt(alias, identity: identity, now: now, calendar: utcCalendar()))
        let weekly = WindowKind.weekly.persistentID
        let reset = now.addingTimeInterval(7 * 86_400)
        // A later reservation prunes the attempt after three days but keeps the weekly lock.
        ledger.finish(claim, outcome: .sent, resetDeadlines: [weekly: reset])
        let fourDaysLater = now.addingTimeInterval(4 * 86_400)
        ledger.reserve(claude, identity: identity, at: fourDaysLater)
        #expect(ledger.save(to: defaults))
        let persisted = try #require(WarmUpLedger.load(from: defaults))
        #expect(!persisted.attempts.contains { $0.id == claim.id })
        #expect(!persisted.canWarm(weekly, for: alias, identity: identity, now: fourDaysLater, observedAt: fourDaysLater))
        #expect(persisted.canWarm(weekly, for: claude, identity: nil, now: fourDaysLater, observedAt: fourDaysLater))
        defaults.set(Data("corrupt".utf8), forKey: "t3.warmUp.ledger.v1")
        #expect(WarmUpLedger.load(from: defaults) == nil)
    }

    @Test func legacyLedgerHasNoCycleRecordsAndPreservesSkippedOutcome() throws {
        let account = ProviderAccount.builtIn(for: .codex).key
        var ledger = WarmUpLedger()
        let claim = ledger.reserve(account, identity: nil, at: .now)
        ledger.finish(claim, outcome: .skipped)
        let data = try JSONEncoder().encode(ledger)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "warmedCycles")
        let decoded = try JSONDecoder().decode(WarmUpLedger.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decoded.attempts.first?.outcome == .skipped)
        #expect(decoded.attempts.first?.startedLimits == nil)
    }
}

struct WarmUpCLICommandTests {
    @Test func antigravityRequiresBuiltInAccountAndFixedArguments() throws {
        let command = try make(.builtIn(for: .antigravity))
        #expect(command.arguments == ["-p", "Reply only with OK. Do not use tools.", "--model", "Gemini 3.8 Flash",
            "--output-format", "json", "--mode", "plan", "--sandbox", "--disable-slash-commands", "--effort", "low"])
        let extra = ProviderAccount(id: AccountID("extra"), providerID: .antigravity, label: "Extra")
        let configuration = ProviderAccountConfiguration.make(for: extra, userHome: URL(filePath: "/fixture"),
                                                              accountsBase: URL(filePath: "/fixture/accounts"))
        #expect(WarmUpCLICommand(account: extra, configuration: configuration) == nil)
    }

    @Test func claudePrimaryAndOwnedHome() throws {
        let primary = try make(.builtIn(for: .claude))
        let work = try make(ProviderAccount(id: AccountID("work"), providerID: .claude, label: "Work"))
        #expect(primary.arguments == work.arguments)
        #expect(primary.arguments.starts(with: [
            "--print", "--model", "haiku", "--max-turns", "1", "--no-session-persistence",
        ]))
        let tools = try #require(primary.arguments.firstIndex(of: "--tools"))
        #expect(primary.arguments[tools + 1] == "")
        #expect(primary.arguments.contains("--strict-mcp-config"))
        #expect(primary.arguments.last == "Reply with OK.")
        #expect(environment(primary) == [
            "HOME": "/fixtures/user", "PATH": "/usr/bin", "PWD": "/fixture-run", "LANG": "en_US.UTF-8",
            "CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1", "USER": NSUserName(),
        ])
        #expect(environment(work)["CLAUDE_CONFIG_DIR"] == "/fixtures/accounts/claude/work/config")
    }

    @Test func codexPrimaryOwnedAndBorrowedHomes() throws {
        let primary = try make(.builtIn(for: .codex))
        let studio = try make(ProviderAccount(id: AccountID("studio"), providerID: .codex, label: "Studio"))
        let path = try #require(CanonicalHomePath(trustedCanonical: "/fixtures/shadow"))
        let borrowed = try make(.init(borrowing: BorrowedHome(path: path, source: .manual), providerID: .codex, label: "Borrowed"))
        #expect(primary.arguments == studio.arguments)
        #expect(primary.arguments == borrowed.arguments)
        #expect(primary.arguments.starts(with: ["exec", "--sandbox", "read-only", "--skip-git-repo-check", "--ephemeral"]))
        #expect(primary.arguments.contains("gpt-6-luna"))
        #expect(primary.arguments.contains("--ignore-user-config"))
        #expect(environment(primary) == [
            "HOME": "/fixtures/user", "PATH": "/usr/bin", "PWD": "/fixture-run", "LANG": "en_US.UTF-8",
        ])
        #expect(environment(studio)["CODEX_HOME"] == "/fixtures/accounts/codex/studio")
        #expect(environment(borrowed)["CODEX_HOME"] == "/fixtures/shadow")
    }

    private func make(_ account: ProviderAccount) throws -> WarmUpCLICommand {
        let configuration = ProviderAccountConfiguration.make(
            for: account, userHome: URL(filePath: "/fixtures/user"),
            accountsBase: URL(filePath: "/fixtures/accounts"),
            builtInClaudeWorkspace: URL(filePath: "/fixtures/probe")
        )
        return try #require(WarmUpCLICommand(account: account, configuration: configuration))
    }

    private func environment(_ command: WarmUpCLICommand) -> [String: String] {
        command.environment(userHome: "/fixtures/user", loginPath: "/usr/bin", workingDirectory: "/fixture-run")
    }
}

@MainActor
struct WarmUpRunnerTests {
    @Test(arguments: [ProviderPollingLane.concurrent, .serial("warm-up-fixture")])
    func liveMergeAndPostSendRefresh(lane: ProviderPollingLane) async throws {
        let account = ProviderAccount.builtIn(for: .codex)
        let identity = try #require(AccountIdentity.codex(accountID: "warm-up-fixture"))
        let date = Date.now
        let provider = WarmUpUsageProvider(pollingLane: lane, identity: identity, date: date)
        let defaults = DemoMemoryDefaults()
        WarmUpSettings(enabled: [
            .init(account: account.key, window: .fiveHour, identity: identity),
            .init(account: account.key, window: .weekly, identity: identity),
        ], activeHours: .anyTime).save(to: defaults)
        let sender = GatedWarmUpSender()
        let automation = WarmUpAutomation(defaults: defaults, sender: sender)
        let store = UsageStore(
            providers: [provider], preferences: Preferences(defaults: defaults),
            warmUp: automation, now: { date }
        )

        await store.refreshAll()
        await sender.waitForStart(count: 1)
        #expect(await sender.windowIDs == [[WindowKind.fiveHour.persistentID, WindowKind.weekly.persistentID]])
        provider.gate.suspendNextFetch()
        store.refreshAccountNow(account.key)
        await provider.gate.waitUntilStarted()

        // Finishing the send during an older probe must queue a separate fresh read.
        await sender.resume(account.key)
        let timeout = ContinuousClock.now.advanced(by: .seconds(2))
        while automation.activeAttemptID != nil, ContinuousClock.now < timeout {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(automation.ledger?.lastAttempt(for: account.key, identity: identity)?.outcome == .sent)
        let afterCooldown = date.addingTimeInterval(1_800)
        for window in WarmUpSettings.supportedWindows {
            #expect(automation.ledger?.canWarm(
                window.persistentID, for: account.key, identity: identity,
                now: afterCooldown, observedAt: afterCooldown
            ) == false)
        }
        provider.gate.release()
        await store.scheduler.waitUntilLanesIdle()
        #expect(await provider.fetchCount == 3)
        #expect(store.snapshot(for: account.key).windows.first?.utilization == 1)
        #expect(await sender.started == [account.key])
    }

    @Test func drainsOnceAcrossReentrantWakeAndMerge() async {
        let first = ProviderAccount.builtIn(for: .claude)
        let second = ProviderAccount.builtIn(for: .codex)
        let sender = GatedWarmUpSender()
        let runner = WarmUpRunner(sender: sender)
        var ledger = WarmUpLedger()
        var waiting = [first, second]
        var finished: [AccountKey] = []
        let next: @MainActor @Sendable () -> WarmUpRequest? = {
            guard !waiting.isEmpty else { return nil }
            let account = waiting.removeFirst()
            return WarmUpRequest(account: account, attempt: ledger.reserve(account.key, identity: nil, at: .now),
                                 windowIDs: [WindowKind.fiveHour.persistentID], attachmentGeneration: 0)
        }
        let complete: @MainActor @Sendable (WarmUpRequest, WarmUpOutcome) -> Void = { request, outcome in
            ledger.finish(request.attempt, outcome: outcome)
            finished.append(request.account.key)
        }

        let drain = Task { await runner.run(next: next, mayLaunch: { _ in true }, complete: complete) }
        await sender.waitForStart(count: 1)
        await runner.run(next: next, mayLaunch: { _ in true }, complete: complete)
        #expect(await sender.started == [first.key])
        #expect(finished.isEmpty)

        await sender.resume(first.key)
        await sender.waitForStart(count: 2)
        #expect(finished == [first.key])
        await sender.resume(second.key)
        await drain.value
        #expect(await sender.started == [first.key, second.key])
        #expect(finished == [first.key, second.key])
        #expect(ledger.attempts.map(\.outcome) == [.sent, .sent])
    }
}

@MainActor
struct WarmUpLaunchGuardTests {
    enum Change: CaseIterable {
        case remove, stopTracking, reset, optOut, usageRises, corruptLedger
    }

    @Test(arguments: Change.allCases)
    func finalLaunchCheckRejectsChangesAfterReservation(_ change: Change) async throws {
        let fixture = try Fixture()
        let store = fixture.store
        let key = change == .remove ? fixture.extra.key : fixture.primary.key
        store.setWarmUpEnabled(true, for: key, window: .weekly)
        let request = try #require(store.nextWarmUp())
        #expect(store.canLaunchWarmUp(request))

        switch change {
        case .remove:
            #expect(await store.removeAccount(key) == .removed)
        case .stopTracking:
            #expect(await store.stopTrackingBuiltInAccount(for: key.providerID) == .removed)
        case .reset:
            store.invalidateUsageForAccountReset(key)
        case .optOut:
            store.setWarmUpEnabled(false, for: key, window: .weekly)
        case .usageRises:
            store.snapshots[key] = fixture.snapshot(weeklyUsage: 1)
        case .corruptLedger:
            fixture.defaults.set(Data("corrupt".utf8), forKey: WarmUpLedger.defaultsKey)
        }
        #expect(!store.canLaunchWarmUp(request))
        switch change {
        case .remove, .stopTracking, .reset, .optOut:
            #expect(WarmUpSettings.load(from: fixture.defaults).enabled.isEmpty)
        case .usageRises:
            #expect(!WarmUpSettings.load(from: fixture.defaults).enabled.isEmpty)
        case .corruptLedger:
            #expect(store.warmUp.ledger == nil)
            #expect(store.nextWarmUp() == nil)
        }
        if change == .reset {
            // Even after the same login is verified and opts back in, the old claim is stale.
            store.snapshots[key] = fixture.snapshot()
            store.setWarmUpEnabled(true, for: key, window: .weekly)
            #expect(!store.canLaunchWarmUp(request))
        }
        store.completeWarmUp(request, outcome: .skipped)
        #expect(store.warmUp.activeAttemptID == nil)
    }

    @Test func rememberedRowsNeverBecomeCandidates() throws {
        let fixture = try Fixture()
        let store = fixture.store
        let remembered = RememberedAccountSummary(
            id: AccountID("remembered"), providerID: .codex, label: "Remembered", email: nil,
            snapshot: fixture.snapshot(), lastReadAt: nil, isHidden: false
        )
        store.rememberedAccountRows[.codex] = [remembered]
        store.warmUp.enable(.init(account: remembered.key, window: .weekly, identity: fixture.identity))
        #expect(store.displayAccounts(for: .codex).contains { $0.key == remembered.key && $0.isRemembered })
        #expect(!store.canEditWarmUp(for: remembered.key))
        #expect(store.nextWarmUp() == nil)
    }

    @Test(arguments: [
        WarmUpOutcome.sent, .failed(.timedOut), .failed(.clientFailed), .failed(.signedOut), .failed(.rejectedArguments), .failed(.exitedNonZero(9)),
        .failed(.cliNotFound), .failed(.workspaceUnavailable), .failed(.launchFailed), .skipped,
    ])
    func mergedPairSendsAndRefreshesThroughVisibleRowOnlyWhenTheClientRan(outcome: WarmUpOutcome) async throws {
        let fixture = try Fixture()
        let store = fixture.store
        let hidden = fixture.primary.key
        let shown = fixture.extra.key
        store.setWarmUpEnabled(true, for: hidden, window: .weekly)
        store.displayMergeMaps[.codex] = [hidden: shown]
        #expect(store.displayAccounts(for: .codex).map(\.key) == [shown])
        #expect(store.warmUpSelections(for: shown).map(\.account) == [hidden])
        store.setWarmUpEnabled(false, for: shown, window: .weekly)
        #expect(store.warmUp.settings.enabled.isEmpty)
        store.setWarmUpEnabled(true, for: hidden, window: .weekly)

        let request = try #require(store.nextWarmUp())
        #expect(request.account.key == shown)
        #expect(store.canLaunchWarmUp(request))
        store.completeWarmUp(request, outcome: outcome)
        await store.waitForAccountProbesToFinish()
        #expect(await fixture.primaryProvider.fetchCount == 0)
        let ranClient = [WarmUpOutcome.sent, .failed(.timedOut), .failed(.clientFailed), .failed(.signedOut), .failed(.rejectedArguments), .failed(.exitedNonZero(9))].contains(outcome)
        #expect(await (store.schedulerProvider(for: shown) as? WarmUpUsageProvider)?.fetchCount == (ranClient ? 1 : 0))
    }

    @MainActor
    private struct Fixture {
        let defaults: DemoMemoryDefaults
        let date: Date
        let identity: AccountIdentity
        let store: UsageStore
        let primary = ProviderAccount.builtIn(for: .codex)
        let primaryProvider: WarmUpUsageProvider
        let extra: ProviderAccount

        init() throws {
            let defaults = DemoMemoryDefaults()
            let date = Date.now
            let identity = try #require(AccountIdentity.codex(accountID: "warm-up-launch-guard-fixture"))
            let primaryProvider = WarmUpUsageProvider(pollingLane: .concurrent, identity: identity, date: date)
            WarmUpSettings(isEnabled: true, activeHours: .anyTime).save(to: defaults)
            let store = UsageStore(
                providers: [primaryProvider], preferences: Preferences(defaults: defaults),
                accountRegistry: AccountRegistry(defaults: defaults), accountStorage: DemoAccountStorage(),
                providerFactory: { account in
                    WarmUpUsageProvider(pollingLane: .concurrent, identity: identity, date: date, accountID: account.id)
                },
                warmUp: WarmUpAutomation(defaults: defaults, sender: GatedWarmUpSender()),
                now: { date }
            )
            self.defaults = defaults
            self.date = date
            self.identity = identity
            self.store = store
            self.primaryProvider = primaryProvider
            self.extra = try #require(store.addAccount(for: .codex, label: "Extra"))
            store.snapshots[primary.key] = snapshot()
            store.snapshots[extra.key] = snapshot()
        }

        func snapshot(weeklyUsage: Double = 0) -> UsageSnapshot {
            UsageSnapshot(
                providerID: .codex,
                windows: [.init(kind: .weekly, utilization: weeklyUsage, resetSchedule: .unresolved(.absent))],
                planLabel: nil, capturedAt: date, freshness: .live, identity: .known(identity)
            )
        }
    }
}

private actor GatedWarmUpSender: WarmUpSender {
    private(set) var started: [AccountKey] = []
    private(set) var windowIDs: [Set<String>] = []
    private var running: [AccountKey: CheckedContinuation<Void, Never>] = [:]
    private var startWaiter: (Int, CheckedContinuation<Void, Never>)?

    func send(_ request: WarmUpRequest, mayLaunch: @MainActor @Sendable () -> Bool) async -> WarmUpOutcome {
        guard await mayLaunch() else { return .skipped }
        let key = request.account.key
        await withCheckedContinuation { continuation in
            running[key] = continuation
            started.append(key)
            windowIDs.append(request.windowIDs)
            if let (count, waiter) = startWaiter, started.count >= count {
                startWaiter = nil
                waiter.resume()
            }
        }
        return .sent
    }

    func waitForStart(count: Int) async {
        guard started.count < count else { return }
        await withCheckedContinuation { startWaiter = (count, $0) }
    }

    func resume(_ key: AccountKey) {
        running.removeValue(forKey: key)?.resume()
    }
}

private actor WarmUpUsageProvider: UsageProvider {
    let id = ProviderID.codex
    let displayName = "Codex"
    let accountCapacity = 20
    let accountID: AccountID
    let pollingLane: ProviderPollingLane
    let gate = FetchGate()
    let identity: AccountIdentity
    let date: Date
    private(set) var fetchCount = 0

    init(pollingLane: ProviderPollingLane, identity: AccountIdentity, date: Date, accountID: AccountID = .primary) {
        self.pollingLane = pollingLane
        self.identity = identity
        self.date = date
        self.accountID = accountID
    }

    func fetchSnapshot() async -> UsageSnapshot {
        fetchCount += 1
        let used: Double = fetchCount < 3 ? 0 : 1
        await gate.enter()
        return UsageSnapshot(
            providerID: id,
            windows: [.fiveHour, .weekly].map { kind in
                UsageWindow(kind: kind, utilization: used, resetSchedule: .unresolved(.absent))
            },
            planLabel: nil, capturedAt: date, freshness: .live, identity: .known(identity)
        )
    }
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}
