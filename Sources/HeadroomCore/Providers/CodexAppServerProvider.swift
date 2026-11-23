import Foundation

enum CodexAppServerMessage: CaseIterable, Sendable {
    case initialize, initialized, accountRead, rateLimitsRead

    var method: String {
        switch self {
        case .initialize: "initialize"
        case .initialized: "initialized"
        case .accountRead: "account/read"
        case .rateLimitsRead: "account/rateLimits/read"
        }
    }

    func line(id: Int? = nil) -> Data {
        var body: [String: Any] = ["method": method]
        body["id"] = id
        switch self {
        case .initialize:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
            body["params"] = ["clientInfo": ["name": "headroom", "version": version]]
        case .initialized: break
        case .accountRead: body["params"] = ["refreshToken": false]
        case .rateLimitsRead: body["params"] = ["excludeResetCreditDetails": true]
        }
        return Self.line(body)
    }

    fileprivate static func line(_ body: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: body, options: .withoutEscapingSlashes)) ?? Data()
        data.append(0x0A)
        return data
    }
}

enum CodexAppServerStep: Int, CaseIterable, Sendable {
    case initialize = 1, accountBefore, rateLimits, accountAfter

    var message: CodexAppServerMessage {
        switch self {
        case .initialize: .initialize
        case .accountBefore, .accountAfter: .accountRead
        case .rateLimits: .rateLimitsRead
        }
    }
}

struct CodexAppServerTranscript: Sendable, Equatable {
    var replies: [CodexAppServerStep: Data] = [:]
    var spawnFailed = false
    var timedOut = false
    var overflowed = false
}

struct CodexAppServerLaunch: Sendable, Equatable {
    let executable: String
    let home: CanonicalHomePath
    let environment: [String: String]
    let workingDirectory: String
    let deadline: TimeInterval

    static let strippedEnvironment = ["OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL"]
    static let replySizeCap = 256 * 1_024
}

protocol CodexAppServerConversing: Sendable {
    func converse(_ launch: CodexAppServerLaunch) async -> CodexAppServerTranscript
}

struct CodexAppServerProcessConversation: CodexAppServerConversing {
    func converse(_ launch: CodexAppServerLaunch) async -> CodexAppServerTranscript {
        await CLIProcessThread.run { Self.run(launch) }
    }

    private static func run(_ launch: CodexAppServerLaunch) -> CodexAppServerTranscript {
        guard (try? FileManager.default.createDirectory(
            atPath: launch.workingDirectory, withIntermediateDirectories: true
        )) != nil,
              let process = StdioChildProcess.spawn(
                  path: launch.executable, arguments: [launch.executable, "app-server"],
                  environment: launch.environment, workingDirectory: launch.workingDirectory
              )
        else { return .init(spawnFailed: true) }
        defer { process.terminate() }

        var transcript = CodexAppServerTranscript()
        var buffer = Data()
        var bytesRead = 0
        let end = Date().addingTimeInterval(launch.deadline)
        for step in CodexAppServerStep.allCases {
            guard process.writeWithoutBlocking(step.message.line(id: step.rawValue)) else { break }
            while Date() < end, transcript.replies[step] == nil {
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer.prefix(upTo: newline))
                    buffer.removeSubrange(...newline)
                    guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
                    else { continue }
                    if json["method"] is String {
                        if let id = json["id"], id is NSNumber || ((id as? String)?.utf8.count ?? Int.max) <= 128 {
                            let refusal = CodexAppServerMessage.line([
                                "id": id, "error": ["code": -32601, "message": "Method not found"]
                            ])
                            guard process.writeWithoutBlocking(refusal) else { return transcript }
                        }
                    } else if json["id"] as? Int == step.rawValue {
                        transcript.replies[step] = line
                        if json["error"] != nil { return transcript }
                        if step == .accountBefore, CodexAppServerClassifier.accountFailure(from: json) != nil {
                            return transcript
                        }
                    }
                } else {
                    let previous = buffer.count
                    guard process.readOutput(into: &buffer, deadline: end) else { return transcript }
                    bytesRead += buffer.count - previous
                    if bytesRead > CodexAppServerLaunch.replySizeCap {
                        transcript.overflowed = true
                        return transcript
                    }
                }
            }
            guard transcript.replies[step] != nil else { break }
            if step == .initialize, !process.writeWithoutBlocking(CodexAppServerMessage.initialized.line()) {
                return transcript
            }
        }
        transcript.timedOut = transcript.replies[.accountAfter] == nil && Date() >= end
        return transcript
    }
}

struct CodexHomeReading: Sendable, Equatable {
    let identityBefore: AccountIdentityRead
    let identityAfter: AccountIdentityRead
    let email: String?
    let planType: String?
    let buckets: [CodexLimitBucket]
    let resetCredits: CodexResetCreditsField
}

enum CodexAppServerFailure: Sendable, Equatable {
    case cliMissing, homeMissing, signedOut, nonSubscriptionLogin, unsupportedServer
    case transient(Cause)

    enum Cause: Sendable, Equatable { case spawnFailed, deadline, unexpectedExit, overflow, serverError }

    func outcome(for source: BorrowedHomeSource) -> ProviderSetupOutcome {
        switch self {
        case .cliMissing: .codexCLIMissing
        case .homeMissing: .codexHomeMissing
        case .signedOut: source.isT3 ? .codexSignedOutInT3 : .codexSignedOutInFolder
        case .nonSubscriptionLogin: .codexAPIKeyHome
        case .unsupportedServer: .codexAppServerUnsupported
        case .transient: .codexAppServerUnavailable
        }
    }
}

enum CodexAppServerCapture: Sendable, Equatable {
    case reading(CodexHomeReading)
    case failed(CodexAppServerFailure)
}

enum CodexAppServerClassifier {
    static func classify(_ transcript: CodexAppServerTranscript) -> CodexAppServerCapture {
        if transcript.spawnFailed { return .failed(.transient(.spawnFailed)) }
        if transcript.overflowed { return .failed(.transient(.overflow)) }
        let replies = transcript.replies.compactMapValues {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        let before = decode(AccountResult.self, from: replies[.accountBefore])
        if let failure = accountFailure(from: replies[.accountBefore]) { return .failed(failure) }
        for step in CodexAppServerStep.allCases {
            guard let reply = replies[step] else {
                return .failed(.transient(transcript.timedOut ? .deadline : .unexpectedExit))
            }
            if let error = reply["error"] as? [String: Any] {
                return .failed(error["code"] as? Int == -32601 ? .unsupportedServer : .transient(.serverError))
            }
        }
        guard let before, let after = decode(AccountResult.self, from: replies[.accountAfter]),
              let limits = decode(LimitsResult.self, from: replies[.rateLimits])
        else { return .failed(.unsupportedServer) }

        let identities = bracket(before: before, after: after, limitsAccountID: limits.accountId)
        var buckets = [limits.rateLimits.bucket(label: nil)]
        for (key, value) in (limits.rateLimitsByLimitId ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard key != "codex", key != limits.rateLimits.limitId, value.limitId != "codex" else { continue }
            buckets.append(value.bucket(label: value.limitName ?? value.limitId ?? key))
        }
        let limitsObject = replies[.rateLimits]?["result"] as? [String: Any]
        let creditShape: CodexResetCreditsField
        switch limitsObject?["rateLimitResetCredits"] {
        case nil: creditShape = .absent
        case is NSNull: creditShape = .nullObject
        default:
            if let credits = decode(Credits.self, object: limitsObject?["rateLimitResetCredits"]),
               credits.availableCount >= 0 {
                creditShape = .count(credits.availableCount)
            } else {
                creditShape = .notReported
            }
        }
        return .reading(CodexHomeReading(
            identityBefore: identities.0, identityAfter: identities.1,
            email: AccountEmail.normalized(before.account?.email),
            planType: limits.rateLimits.planType ?? before.account?.planType,
            buckets: buckets, resetCredits: creditShape
        ))
    }

    /// The initialize reply already carries the server binary version in its user agent.
    static func cliVersion(from transcript: CodexAppServerTranscript) -> String? {
        guard let data = transcript.replies[.initialize],
              let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = reply["result"] as? [String: Any],
              let userAgent = result["userAgent"] as? String,
              let version = userAgent.firstMatch(of: /^[^\s\/]+\/([0-9]+\.[0-9]+\.[0-9]+)(?:\s|$|-)/)
        else { return nil }
        return "v" + version.1
    }

    fileprivate static func accountFailure(from reply: [String: Any]?) -> CodexAppServerFailure? {
        guard let read = decode(AccountResult.self, from: reply) else { return nil }
        if read.account == nil, read.requiresOpenaiAuth { return .signedOut }
        return read.account?.type == "chatgpt" ? nil : .nonSubscriptionLogin
    }

    private static func bracket(
        before: AccountResult, after: AccountResult, limitsAccountID: String?
    ) -> (AccountIdentityRead, AccountIdentityRead) {
        // Use the quota response as a fallback only when both reads agree on the
        // signed-in user and neither supplies a workspace account id.
        let matchingUser = before.userId.map { !$0.isEmpty && $0 == after.userId } == true
        let fallback = before.workspaceRouting?.chatgptAccountId == nil
            && after.workspaceRouting?.chatgptAccountId == nil && matchingUser ? limitsAccountID : nil
        let first = AccountIdentity.codex(accountID: before.workspaceRouting?.chatgptAccountId ?? fallback)
        let last = AccountIdentity.codex(accountID: after.workspaceRouting?.chatgptAccountId ?? fallback)
        let limits = AccountIdentity.codex(accountID: limitsAccountID)
        guard after.account?.type == "chatgpt", before.userId == after.userId,
              before.account?.email == after.account?.email,
              let first, let last, limits == nil || limits == first
        else { return (.unreadable, .absent) }
        return (.identity(first, email: nil), .identity(last, email: nil))
    }

    private static func decode<T: Decodable>(_ type: T.Type, from reply: [String: Any]?) -> T? {
        decode(type, object: reply?["result"])
    }

    private static func decode<T: Decodable>(_ type: T.Type, object: Any?) -> T? {
        guard let object, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private struct AccountResult: Decodable {
        struct Account: Decodable { let type: String; let email: String?; let planType: String? }
        struct Routing: Decodable { let chatgptAccountId: String? }
        let account: Account?
        let requiresOpenaiAuth: Bool
        let workspaceRouting: Routing?
        let userId: String?
    }

    private struct LimitsResult: Decodable {
        let rateLimits: RateLimits
        let rateLimitsByLimitId: [String: RateLimits]?
        let accountId: String?
    }

    private struct RateLimits: Decodable {
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Double?
            let resetsAt: Double?

            var domain: CodexLimitWindow {
                .init(
                    usedPercent: usedPercent, windowSeconds: windowDurationMins.map { $0 * 60 },
                    resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }
        }

        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
        let planType: String?

        func bucket(label: String?) -> CodexLimitBucket {
            .init(label: label, primary: primary?.domain, secondary: secondary?.domain)
        }
    }

    private struct Credits: Decodable { let availableCount: Int }
}

public struct CodexAppServerProvider: UsageProvider {
    public let id = ProviderID.codex
    public let accountID: AccountID
    public let displayName = "Codex"
    public var pollingLane: ProviderPollingLane { .serial("codex-app-server") }

    private let home: BorrowedHome
    private let resolveExecutable: @Sendable (BorrowedHome) -> String?
    private let conversation: any CodexAppServerConversing
    private let loginPath: @Sendable (String) -> String
    private let now: @Sendable () -> Date

    public init(
        accountID: AccountID, home: BorrowedHome,
        resolveExecutable: @escaping @Sendable (BorrowedHome) -> String? = CodexAppServerProvider.defaultExecutable,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.init(
            accountID: accountID, home: home, resolveExecutable: resolveExecutable,
            conversation: CodexAppServerProcessConversation(), now: now,
            loginPath: { CLIExecutableResolver.resolveLoginPath(fallback: $0) }
        )
    }

    init(
        accountID: AccountID, home: BorrowedHome,
        resolveExecutable: @escaping @Sendable (BorrowedHome) -> String?,
        conversation: any CodexAppServerConversing, now: @escaping @Sendable () -> Date,
        loginPath: @escaping @Sendable (String) -> String = { $0 }
    ) {
        self.accountID = accountID
        self.home = home
        self.resolveExecutable = resolveExecutable
        self.conversation = conversation
        self.loginPath = loginPath
        self.now = now
    }

    public static let defaultExecutable: @Sendable (BorrowedHome) -> String? = { home in
        if let preferred = home.preferredExecutable, preferred.hasPrefix("/"),
           FileManager.default.isExecutableFile(atPath: preferred) { return preferred }
        return CLIExecutableResolver.resolve(named: "codex", fallbackPaths: [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", NSHomeDirectory() + "/.local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ])
    }

    public func fetchSnapshot() async -> UsageSnapshot { await fetchResult().snapshot }

    public func fetchResult() async -> UsageProviderFetchResult {
        guard BorrowedHomePaths.existingDirectory(home.path.url) == home.path else { return stale(.homeMissing) }
        let locate = resolveExecutable
        let home = home
        guard let executable = await CLIProcessThread.run({ locate(home) }) else { return stale(.cliMissing) }
        var environment = ProcessInfo.processInfo.environment
        for name in CodexAppServerLaunch.strippedEnvironment { environment.removeValue(forKey: name) }
        environment["CODEX_HOME"] = home.path.rawPath
        let fallbackPath = environment["PATH"] ?? "/usr/bin:/bin"
        let loginPath = loginPath
        environment["PATH"] = await CLIProcessThread.run { loginPath(fallbackPath) }
        let cwd = AccountStorage.baseDirectoryURL.deletingLastPathComponent()
            .appendingPathComponent("CodexProbe", isDirectory: true)
        // A chosen folder must not double as Headroom’s private working directory.
        let probePath = BorrowedHomePaths.referencePath(cwd)
        guard probePath != home.path.rawPath, !probePath.hasPrefix(home.path.rawPath + "/")
        else { return stale(.homeMissing) }
        let launch = CodexAppServerLaunch(
            executable: executable, home: home.path, environment: environment,
            workingDirectory: cwd.path, deadline: 12
        )

        let transcript = await conversation.converse(launch)
        let version = CodexAppServerClassifier.cliVersion(from: transcript)
        switch CodexAppServerClassifier.classify(transcript) {
        case .failed(let failure):
            return stale(failure).withCLIVersion(version)
        case .reading(let reading):
            let identity = AccountIdentityOutcome.bracketing(
                before: reading.identityBefore, after: reading.identityAfter
            )
            guard identity != .unreadable else { return .identityUnreadable(for: id) }
            let windows = CodexWindowMapping.windows(reading.buckets)
            guard !windows.isEmpty else {
                return UsageProviderFetchResult(snapshot: .stale(for: id, reason: .decode("No usage windows in Codex response")))
            }
            return UsageProviderFetchResult(snapshot: UsageSnapshot(
                providerID: id, windows: windows, planLabel: reading.planType,
                accountEmail: reading.email, bankedResets: reading.resetCredits.bankedResets,
                codexResetCreditsField: reading.resetCredits, capturedAt: now(), freshness: .live
            ).withIdentity(identity), cliVersion: version)
        }
    }

    private func stale(_ failure: CodexAppServerFailure) -> UsageProviderFetchResult {
        UsageProviderFetchResult(snapshot: .stale(for: id, reason: .providerSetup(failure.outcome(for: home.source))))
    }
}
