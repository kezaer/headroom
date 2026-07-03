import Foundation
@testable import HeadroomCore

/// Codex reader double.
struct MockCodexReader: CodexAuthReading {
    var credential: CodexCredential?
    func readCodexCredential() throws -> CodexCredential {
        guard let credential else { throw CredentialError.notLoggedIn }
        return credential
    }
}

/// HTTP double for the Codex provider. Returns a queued response and captures the last
/// request's headers.
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

/// Claude usage-source double — returns a fixed panel/result so the provider is tested
/// without spawning the real CLI.
struct MockClaudeSource: ClaudeUsageSource {
    let result: ClaudePanelResult
    func capturePanel() async -> ClaudePanelResult { result }
}

/// Provider double for engine tests.
struct StubProvider: UsageProvider {
    let id: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    func fetchSnapshot() async -> UsageSnapshot { snapshot }
}

/// Provider double whose returned snapshot can change between refreshes.
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

/// Provider double that counts how many times it was fetched.
final class CountingProvider: UsageProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    private let lock = NSLock()
    private var _count = 0
    var fetchCount: Int { lock.withLock { _count } }
    init(id: ProviderID, displayName: String = "P") { self.id = id; self.displayName = displayName }
    func fetchSnapshot() async -> UsageSnapshot {
        lock.withLock { _count += 1 }
        return .live(id, windows: [UsageWindow(kind: .fiveHour, utilization: 10, resetsAt: Date(timeIntervalSince1970: 3_000_000))])
    }
}

extension UsageSnapshot {
    static func live(_ id: ProviderID, windows: [UsageWindow], plan: String? = nil, at: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(providerID: id, windows: windows, planLabel: plan, capturedAt: at, freshness: .live)
    }
}
