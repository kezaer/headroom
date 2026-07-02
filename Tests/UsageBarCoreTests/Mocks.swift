import Foundation
@testable import UsageBarCore

/// In-memory Keychain double. Counts bootstrap reads so tests can prove token
/// precedence, and can simulate an absent item (`errSecItemNotFound`).
final class MockKeychain: ClaudeCodeKeychainReading, OwnCredentialStoring, @unchecked Sendable {
    var claudeCode: ClaudeCredential?
    var ownItem: ClaudeCredential?
    private(set) var claudeCodeReadCount = 0

    init(claudeCode: ClaudeCredential? = nil, ownItem: ClaudeCredential? = nil) {
        self.claudeCode = claudeCode
        self.ownItem = ownItem
    }

    func readClaudeCodeCredential() throws -> ClaudeCredential {
        claudeCodeReadCount += 1
        guard let claudeCode else { throw CredentialError.notLoggedIn }
        return claudeCode
    }

    func readOwnClaude() throws -> ClaudeCredential? { ownItem }
    func writeOwnClaude(_ credential: ClaudeCredential) throws { ownItem = credential }
}

/// Codex reader double.
struct MockCodexReader: CodexAuthReading {
    var credential: CodexCredential?
    func readCodexCredential() throws -> CodexCredential {
        guard let credential else { throw CredentialError.notLoggedIn }
        return credential
    }
}

/// Claude refresher double. Counts calls (single-flight proof) and can suspend to
/// widen the concurrency window.
final class MockRefresher: ClaudeTokenRefreshing, @unchecked Sendable {
    var result: Result<ClaudeCredential, FailureReason>
    var delay: Duration = .zero
    private let lock = NSLock()
    private var _count = 0
    var callCount: Int { lock.withLock { _count } }

    init(result: Result<ClaudeCredential, FailureReason> = .failure(.needsReauth("re-login"))) {
        self.result = result
    }

    func refresh(using refreshToken: String) async -> Result<ClaudeCredential, FailureReason> {
        lock.withLock { _count += 1 }
        if delay > .zero { try? await Task.sleep(for: delay) }
        return result
    }
}

/// HTTP double. Returns a queued response and captures the last request's headers so
/// tests can assert the User-Agent format and header presence.
final class MockFetcher: UsageFetching, @unchecked Sendable {
    var responses: [Result<HTTPResult, FailureReason>]
    private let lock = NSLock()
    private var index = 0
    private(set) var lastHeaders: [String: String] = [:]
    private(set) var requestCount = 0

    init(_ responses: [Result<HTTPResult, FailureReason>]) { self.responses = responses }
    convenience init(status: Int, body: String) {
        self.init([.success(HTTPResult(status: status, body: Data(body.utf8)))])
    }

    func get(url: URL, headers: [String: String]) async -> Result<HTTPResult, FailureReason> {
        lock.withLock {
            lastHeaders = headers
            requestCount += 1
            let r = responses[min(index, responses.count - 1)]
            index += 1
            return r
        }
    }
}

/// Provider double for engine tests.
struct StubProvider: UsageProvider {
    let id: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    func fetchSnapshot() async -> UsageSnapshot { snapshot }
}

/// Provider double whose returned snapshot can change between refreshes — used to
/// test the store's continuity/merge behavior.
final class MutableStubProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    private let lock = NSLock()
    private var _snapshot: UsageSnapshot
    init(id: ProviderID, displayName: String, snapshot: UsageSnapshot) {
        self.id = id
        self.displayName = displayName
        self._snapshot = snapshot
    }
    func set(_ s: UsageSnapshot) { lock.withLock { _snapshot = s } }
    func fetchSnapshot() async -> UsageSnapshot { lock.withLock { _snapshot } }
}

extension UsageSnapshot {
    static func live(_ id: ProviderID, windows: [UsageWindow], plan: String? = nil, at: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(providerID: id, windows: windows, planLabel: plan, capturedAt: at, freshness: .live)
    }
}

extension ClaudeCredential {
    static func valid(now: Date = Date()) -> ClaudeCredential {
        ClaudeCredential(accessToken: "access-tok", refreshToken: "refresh-tok",
                         expiresAt: now.addingTimeInterval(3600))
    }
    static func expired(now: Date = Date()) -> ClaudeCredential {
        ClaudeCredential(accessToken: "old-tok", refreshToken: "refresh-tok",
                         expiresAt: now.addingTimeInterval(-10))
    }
}
