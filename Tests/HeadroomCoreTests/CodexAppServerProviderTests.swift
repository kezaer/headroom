import Foundation
import Testing
@testable import HeadroomCore

struct CodexAppServerProviderTests {
    @Test func subscriptionWindowsAndCreditsMatchTheAppServerSchema() async throws {
        let home = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = try #require(CanonicalHomePath(trustedCanonical: home.path))
        for plan in ["prolite", "pro"] {
            let fixture = CodexConversationFixture(transcript(plan: plan))
            let provider = CodexAppServerProvider(
                accountID: .borrowedHome(path), home: .init(path: path, source: .manual),
                resolveExecutable: { _ in "/fixture/bin/codex" }, conversation: fixture, now: { .distantPast }
            )
            let result = await provider.fetchResult()
            #expect(provider.pollingLane == .serial("codex-app-server"))
            #expect(result.snapshot.freshness == .live)
            #expect(result.snapshot.planLabel == plan)
            #expect(result.cliVersion == "v0.171.0")
            #expect(result.snapshot.accountEmail == "headroom@example.com")
            #expect(result.snapshot.bankedResets == 2)
            #expect(result.snapshot.codexResetCreditsField == .count(2))
            #expect(result.snapshot.identity == AccountIdentity.codex(accountID: "workspace-test").map(AccountIdentityOutcome.known))
            #expect(result.snapshot.windows.map(\.kind) == (
                plan == "pro"
                    ? [.fiveHour, .weekly, .other("GPT-5.3-Codex-Spark 5h")]
                    : [.weekly, .other("GPT-5.3-Codex-Spark 5h")]
            ))
            #expect(result.snapshot.windows.last?.resetSchedule == .scheduled(Date(timeIntervalSince1970: 2_000_000_000)))
            let launches = await fixture.launches
            let launched = try #require(launches.first)
            #expect(launched.environment["CODEX_HOME"] == path.rawPath)
            #expect(launched.home == path)
            #expect(launched.executable == "/fixture/bin/codex")
            #expect(CodexAppServerLaunch.strippedEnvironment.allSatisfy { launched.environment[$0] == nil })
        }
    }

    @Test func accountChangesAcrossTheUsageReadAreRefused() async throws {
        let home = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = try #require(CanonicalHomePath(trustedCanonical: home.path))
        let fixture = CodexConversationFixture(transcript(plan: "pro", afterID: "other-account"))
        let provider = CodexAppServerProvider(
            accountID: .borrowedHome(path), home: .init(path: path, source: .manual),
            resolveExecutable: { _ in "/fixture/bin/codex" }, conversation: fixture, now: { .distantPast }
        )
        let result = await provider.fetchResult()
        #expect(result == .identityUnreadable(for: .codex))
        #expect(result.snapshot.windows.isEmpty)
    }

    @Test func classifierDistinguishesSignedOutAPIKeyUnsupportedAndTransient() {
        var capture = transcript(plan: "pro")
        capture.replies[.accountBefore] = reply(#"{"account":null,"requiresOpenaiAuth":true}"#)
        #expect(CodexAppServerClassifier.classify(capture) == .failed(.signedOut))
        #expect(CodexAppServerFailure.signedOut.outcome(for: .manual) == .codexSignedOutInFolder)
        #expect(CodexAppServerFailure.signedOut.outcome(for: .t3Instance(instanceID: "codex", displayName: nil)) == .codexSignedOutInT3)

        capture.replies[.accountBefore] = reply(#"{"account":{"type":"apiKey"},"requiresOpenaiAuth":false}"#)
        #expect(CodexAppServerClassifier.classify(capture) == .failed(.nonSubscriptionLogin))

        capture = transcript(plan: "pro")
        capture.replies[.rateLimits] = Data(#"{"error":{"code":-32601}}"#.utf8)
        #expect(CodexAppServerClassifier.classify(capture) == .failed(.unsupportedServer))
        capture.replies[.rateLimits] = reply("{}")
        #expect(CodexAppServerClassifier.classify(capture) == .failed(.unsupportedServer))
        capture.replies.removeValue(forKey: .rateLimits)
        capture.timedOut = true
        #expect(CodexAppServerClassifier.classify(capture) == .failed(.transient(.deadline)))
        capture.overflowed = true
        #expect(CodexAppServerClassifier.classify(capture) == .failed(.transient(.overflow)))
    }

    @Test func processSendsOnlyTheReadOnlyExchangeAndRefusesServerRequests() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // /bin/sh reads this fixture as the app-server argument. No executable fixture,
        // network, installed Codex or credential file is needed.
        let script = #"""
        IFS= read -r request || exit 1
        case "$request" in *'"method":"initialize"'*) ;; *) exit 2 ;; esac
        printf '%s\n' '{"method":"account/login/start","id":"server-request"}'
        IFS= read -r refusal || exit 3
        case "$refusal" in *'"code":-32601'*) ;; *) exit 4 ;; esac
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r notification || exit 5
        case "$notification" in *'"method":"initialized"'*) ;; *) exit 6 ;; esac
        IFS= read -r before || exit 7
        case "$before" in *'"method":"account/read"'*) ;; *) exit 8 ;; esac
        case "$before" in *'"refreshToken":false'*) ;; *) exit 9 ;; esac
        printf '%s\n' '{"id":2,"result":{}}'
        IFS= read -r limits || exit 10
        case "$limits" in *'"method":"account/rateLimits/read"'*) ;; *) exit 11 ;; esac
        case "$limits" in *'"excludeResetCreditDetails":true'*) ;; *) exit 12 ;; esac
        printf '%s\n' '{"id":3,"result":{}}'
        IFS= read -r after || exit 13
        case "$after" in *'"method":"account/read"'*) ;; *) exit 14 ;; esac
        case "$after" in *'"refreshToken":false'*) ;; *) exit 15 ;; esac
        printf '%s\n' '{"id":4,"result":{}}'
        """#
        try Data(script.utf8).write(to: directory.appendingPathComponent("app-server"))
        let path = try #require(CanonicalHomePath(trustedCanonical: directory.path))
        let capture = await CodexAppServerProcessConversation().converse(.init(
            executable: "/bin/sh", home: path, environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: directory.path, deadline: 5
        ))
        #expect(Set(capture.replies.keys) == Set(CodexAppServerStep.allCases))
        #expect(!capture.spawnFailed && !capture.timedOut && !capture.overflowed)
    }

    private func transcript(plan: String, afterID: String = "workspace-test") -> CodexAppServerTranscript {
        let weekly = #"{"usedPercent":15,"windowDurationMins":10080,"resetsAt":2000000000}"#
        let fiveHour = #"{"usedPercent":44,"windowDurationMins":300,"resetsAt":2000000000}"#
        let main = """
        {"limitId":"codex","limitName":null,"normalModelSlug":null,"planType":"\(plan)",
         "primary":\(plan == "prolite" ? weekly : fiveHour),"secondary":\(plan == "prolite" ? "null" : weekly),
         "credits":{"hasCredits":false,"unlimited":false,"balance":null}}
        """
        let rates = """
        {"ordinaryUsageAllowed":true,"accountId":"workspace-test","rateLimits":\(main),
         "rateLimitsByLimitId":{"codex":\(main),"spark":{"limitId":"spark","limitName":"GPT-5.3-Codex-Spark",
         "primary":\(fiveHour),"secondary":null}},"rateLimitResetCredits":{"availableCount":2,"credits":null}}
        """
        func account(_ id: String) -> String {
            """
            {"account":{"type":"chatgpt","email":" Headroom@Example.com ","planType":"\(plan)","workspaceName":null},
             "requiresOpenaiAuth":true,"userId":"user-test","workspaceRouting":{"chatgptAccountId":"\(id)"}}
            """
        }
        return .init(replies: [
            .initialize: reply(#"{"platformFamily":"unix","platformOs":"macos","userAgent":"headroom/0.171.0 (Mac OS 27.0; arm64) fixture"}"#),
            .accountBefore: reply(account("workspace-test")), .rateLimits: reply(rates),
            .accountAfter: reply(account(afterID)),
        ])
    }

    private func reply(_ result: String) -> Data { Data("{\"result\":\(result)}".utf8) }
}

private actor CodexConversationFixture: CodexAppServerConversing {
    let fixture: CodexAppServerTranscript
    private(set) var launches: [CodexAppServerLaunch] = []
    init(_ fixture: CodexAppServerTranscript) { self.fixture = fixture }

    func converse(_ launch: CodexAppServerLaunch) -> CodexAppServerTranscript {
        launches.append(launch)
        return fixture
    }
}
