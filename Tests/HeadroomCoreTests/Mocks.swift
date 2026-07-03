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
    private(set) var lastURL: URL?
    private(set) var requestCount = 0

    init(_ responses: [Result<HTTPResult, FailureReason>]) { self.responses = responses }
    convenience init(status: Int, body: String) {
        self.init([.success(HTTPResult(status: status, body: Data(body.utf8)))])
    }

    func get(url: URL, headers: [String: String]) async -> Result<HTTPResult, FailureReason> {
        lock.withLock {
            lastHeaders = headers
            lastURL = url
            requestCount += 1
            let r = responses[min(index, responses.count - 1)]
            index += 1
            return r
        }
    }
}

/// In-memory API key store double.
final class MockAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [APIKeyProvider: String]
    var shouldFail = false

    init(keys: [APIKeyProvider: String] = [:]) {
        self.keys = keys
    }

    func readAPIKey(for provider: APIKeyProvider) throws -> String {
        try lock.withLock {
            if shouldFail { throw CredentialError.keychainStatus(-1) }
            guard let key = keys[provider] else { throw CredentialError.notLoggedIn }
            return key
        }
    }

    func saveAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        try lock.withLock {
            if shouldFail { throw CredentialError.keychainStatus(-1) }
            keys[provider] = key
        }
    }

    func deleteAPIKey(for provider: APIKeyProvider) throws {
        try lock.withLock {
            if shouldFail { throw CredentialError.keychainStatus(-1) }
            keys.removeValue(forKey: provider)
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

/// Widget exporter double for store tests.
final class SpyWidgetExporter: WidgetSnapshotExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _exports: [WidgetSnapshotEnvelope] = []
    var exports: [WidgetSnapshotEnvelope] { lock.withLock { _exports } }

    func export(_ envelope: WidgetSnapshotEnvelope) {
        lock.withLock { _exports.append(envelope) }
    }
}

/// API spend provider double that counts how many times it was fetched.
final class CountingSpendProvider: APISpendProvider, @unchecked Sendable {
    let id: ProviderID
    let displayName: String
    private let lock = NSLock()
    private var _count = 0
    let snapshot: APISpendSnapshot
    var fetchCount: Int { lock.withLock { _count } }

    init(id: ProviderID, displayName: String = "API", snapshot: APISpendSnapshot? = nil) {
        self.id = id
        self.displayName = displayName
        self.snapshot = snapshot ?? APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: 1,
            currency: "usd",
            periodLabel: APISpendPeriod.currentMonth.label,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            freshness: .live
        )
    }

    func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        lock.withLock { _count += 1 }
        return snapshot
    }
}

extension UsageSnapshot {
    static func live(_ id: ProviderID, windows: [UsageWindow], plan: String? = nil, at: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(providerID: id, windows: windows, planLabel: plan, capturedAt: at, freshness: .live)
    }
}
