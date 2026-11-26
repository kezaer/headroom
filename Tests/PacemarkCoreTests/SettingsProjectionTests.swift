import Foundation
import Testing
@testable import PacemarkCore

struct SettingsProjectionTests {
    @Test func otherPoolFiltersBothWindowLengthsEvenWhenGeminiIsMissing() {
        let snapshot = UsageSnapshot(providerID: .antigravity, windows: [
            UsageWindow(kind: .other("Other 5h"), utilization: 90, resetSchedule: .unresolved(.absent)),
            UsageWindow(kind: .other("Other weekly"), utilization: 60, resetSchedule: .unresolved(.absent)),
        ], planLabel: "Ultra", capturedAt: .now, freshness: .live)
        let visible = AntigravityOtherModels.visibleSnapshot(snapshot, showsOtherModels: false)
        #expect(visible.windows.isEmpty)
        #expect(visible.planLabel == snapshot.planLabel)
        let both = AntigravityOtherModels.visibleSnapshot(snapshot, showsOtherModels: true)
        #expect(both.windows.map(\.kind) == snapshot.windows.map(\.kind))
        #expect(both.windows.map(\.displayLabel) == ["Claude & GPT 5h", "Claude & GPT weekly"])
    }

    @Test func onlyGeminiRemindsWhenTheOtherPoolIsHidden() {
        let now = Date()
        let kinds: [WindowKind] = [.other("Gemini 5h"), .other("Gemini weekly"), .other("Other 5h"), .other("Other weekly")]
        let snapshot = UsageSnapshot(providerID: .antigravity, windows: kinds.map {
            UsageWindow(kind: $0, utilization: 2, resetsAt: now.addingTimeInterval(1_800))
        }, planLabel: nil, capturedAt: now, freshness: .live)
        let account = AccountKey(providerID: .antigravity, accountID: .primary)
        let settings = UseItUpSettings(isEnabled: true, rules: [.init(amount: 1, unit: .hours, threshold: 50)],
                                       scope: [.fiveHour, .weekly], showCodexSparkCounters: false)
        let visible = AntigravityOtherModels.visibleSnapshot(snapshot, showsOtherModels: false)
        let proposals = UseItUpEvaluator.evaluate(snapshot: visible, account: account, settings: settings, ledger: [], now: now)
        #expect(proposals.map(\.kind) == [.other("Gemini 5h"), .other("Gemini weekly")])
    }

    @Test func cadenceRowsOnlyIncludeStretchedIntervalsInProviderOrder() {
        let chosen: TimeInterval = 300
        let cadences: [ProviderID: PollCadence] = [
            .claude: .init(chosenInterval: chosen, effectiveInterval: chosen, accountCount: 1),
            .grok: .init(chosenInterval: chosen, effectiveInterval: 480, accountCount: 16),
            .codex: .init(chosenInterval: chosen, effectiveInterval: 601, accountCount: 20),
            .cursor: .init(chosenInterval: chosen, effectiveInterval: 240, accountCount: 1),
        ]
        let rows = PollCadencePresentation.effectiveIntervals(
            for: [.codex, .claude, .cursor, .antigravity, .grok], cadences: cadences
        )
        #expect(rows.map(\.providerID) == [.codex, .grok])
        #expect(rows.map(\.minutes) == [11, 8])
    }

    @Test func cadenceRowsAreEmptyWhenEveryIntervalMatchesTheChosenOne() {
        let chosen: TimeInterval = 300
        let cadence = PollCadence(chosenInterval: chosen, effectiveInterval: chosen, accountCount: 1)
        let rows = PollCadencePresentation.effectiveIntervals(
            for: [.claude, .codex], cadences: [.claude: cadence, .codex: cadence]
        )
        #expect(rows.isEmpty)
    }

    @Test func issueDraftUsesTheEmailDiagnosticsAndFitsTheURLBudget() throws {
        let privateAddress = ["private", "example.invalid"].joined(separator: "@")
        let accounts = (1...160).map {
            FeedbackDiagnostics.Account(providerID: .claude, position: $0,
                                        status: .init(freshness: .stale(.notLoggedIn("\(privateAddress) token=private"))))
        }
        let diagnostics = FeedbackDiagnostics(appVersion: "1.2.3+4", operatingSystem: "macOS 26.5 & test",
                                              accounts: accounts)
        let issue = FeedbackIssue(diagnostics: diagnostics)
        let components = try #require(URLComponents(url: issue.url, resolvingAgainstBaseURL: false))
        #expect(components.host == "github.com")
        #expect(components.path == "/kezaer/pacemark/issues/new")
        #expect(components.queryItems?.first(where: { $0.name == "title" })?.value == "[Pacemark Mac] Feedback")
        let body = try #require(components.queryItems?.first(where: { $0.name == "body" })?.value)
        #expect(body.contains("Pacemark 1.2.3+4 · macOS 26.5 & test"))
        #expect(body.contains("Claude #1: stale (notLoggedIn)"))
        #expect(body.contains("Some diagnostics were left out"))
        #expect(!body.contains(privateAddress))
        #expect(!body.contains("token="))
        #expect(issue.url.absoluteString.utf8.count < 1_800)
        let rawItems = try #require(components.percentEncodedQueryItems)
        #expect(rawItems.map(\.name) == ["title", "body"])
        let rawBody = try #require(rawItems.last?.value)
        #expect(rawBody.contains("1.2.3%2B4"))
        #expect(rawBody.contains("%26"))
        #expect(rawItems.allSatisfy { item in
            guard let value = item.value else { return false }
            return !value.contains("+") && !value.contains("&")
        })
    }

    @Test func issueDraftWithoutDiagnosticsContainsOnlyTheFeedbackPrompts() throws {
        let issue = FeedbackIssue(diagnostics: nil)
        let items = try #require(URLComponents(url: issue.url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items == [
            URLQueryItem(name: "title", value: "[Pacemark Mac] Feedback"),
            URLQueryItem(name: "body", value: "What happened?\n\n\nWhat did you expect instead?\n\n"),
        ])
    }
}
