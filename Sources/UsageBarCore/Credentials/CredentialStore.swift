import Foundation

/// Refreshes a Claude access token from a refresh token (KTD3). Behind a protocol
/// because the real parameters (token URL, client_id, grant_type) are resolved by
/// the U9 spike and MUST be confirmed non-rotating before self-refresh is enabled.
public protocol ClaudeTokenRefreshing: Sendable {
    func refresh(using refreshToken: String) async -> Result<ClaudeCredential, FailureReason>
}

/// Safe default until U9 (Q1/Q4/Q5) confirms the refresh parameters and, critically,
/// that Anthropic's refresh token is **non-rotating**. Refreshing with Claude Code's
/// rotating token would invalidate Claude Code's own session (the P0 desync risk), so
/// until proven safe we do not self-refresh — we degrade to an actionable re-login.
public struct ReauthOnlyRefresher: ClaudeTokenRefreshing {
    public init() {}
    public func refresh(using refreshToken: String) async -> Result<ClaudeCredential, FailureReason> {
        .failure(.needsReauth("Session expired — run `claude` to re-login"))
    }
}

/// Central credential access (U3). An `actor` so the concurrent per-cycle fetch from
/// both providers is data-race-free under Swift 6 strict concurrency (KTD10).
///
/// Token precedence (KTD3): once it holds its own token it reads only its own item,
/// touching `Claude Code-credentials` on bootstrap only. Single-flight (KTD3):
/// concurrent callers await one in-progress refresh, never issuing parallel refreshes
/// against a possibly single-use refresh token.
public actor CredentialStore {
    private let keychain: ClaudeCodeKeychainReading
    private let ownStore: OwnCredentialStoring
    private let codexReader: CodexAuthReading
    private let refresher: ClaudeTokenRefreshing
    private let now: @Sendable () -> Date

    private var cachedClaude: ClaudeCredential?
    private var claudeBootstrapReads = 0            // test-observable: proves precedence
    private var inFlightRefresh: Task<Result<ClaudeCredential, FailureReason>, Never>?

    /// Access-token freshness margin — refresh a little before actual expiry.
    private static let expiryMargin: TimeInterval = 60

    public init(
        keychain: ClaudeCodeKeychainReading = SystemKeychain(),
        ownStore: OwnCredentialStoring = SystemKeychain(),
        codexReader: CodexAuthReading = CodexAuthFileReader(),
        refresher: ClaudeTokenRefreshing = ReauthOnlyRefresher(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychain = keychain
        self.ownStore = ownStore
        self.codexReader = codexReader
        self.refresher = refresher
        self.now = now
    }

    /// Test hook: how many times the Claude Code (bootstrap) item was read.
    public var bootstrapReadCount: Int { claudeBootstrapReads }

    public func claudeAccessToken() async -> Result<String, FailureReason> {
        // Load into cache once: prefer our own item (precedence), else bootstrap.
        if cachedClaude == nil {
            if let own = try? ownStore.readOwnClaude() {
                cachedClaude = own
            } else {
                do {
                    cachedClaude = try keychain.readClaudeCodeCredential()
                    claudeBootstrapReads += 1
                } catch CredentialError.notLoggedIn {
                    return .failure(.notLoggedIn("Claude Code isn't logged in — run `claude`"))
                } catch {
                    return .failure(.notLoggedIn("Claude Code credential unreadable"))
                }
            }
        }
        guard let cred = cachedClaude else {
            return .failure(.notLoggedIn("Claude Code isn't logged in — run `claude`"))
        }
        if cred.expiresAt > now().addingTimeInterval(Self.expiryMargin) {
            return .success(cred.accessToken)
        }
        return await refreshClaude(cred)
    }

    /// Force a refresh even if the cached token still looks valid — used by the
    /// provider after a server-side 401 (one retry, then permanent per KTD7).
    public func forceRefreshClaude() async -> Result<String, FailureReason> {
        guard let cred = cachedClaude else {
            return .failure(.needsReauth("Session expired — run `claude` to re-login"))
        }
        return await refreshClaude(cred)
    }

    private func refreshClaude(_ cred: ClaudeCredential) async -> Result<String, FailureReason> {
        // Single-flight: set inFlight before the first suspension so concurrent
        // callers entering during the await share this one refresh.
        let result: Result<ClaudeCredential, FailureReason>
        if let task = inFlightRefresh {
            result = await task.value
        } else {
            let refresher = self.refresher
            let task = Task<Result<ClaudeCredential, FailureReason>, Never> {
                await refresher.refresh(using: cred.refreshToken)
            }
            inFlightRefresh = task
            result = await task.value
            inFlightRefresh = nil
            // The creator persists the full refreshed credential — the server's real
            // expiry and (possibly rotated) refresh token, not a fabricated expiry.
            if case .success(let fresh) = result {
                cachedClaude = fresh
                try? ownStore.writeOwnClaude(fresh)
            }
        }
        return result.map(\.accessToken)
    }

    public func codexAccessToken() async -> Result<String, FailureReason> {
        do {
            return .success(try codexReader.readCodexCredential().accessToken)
        } catch CredentialError.notLoggedIn {
            return .failure(.notLoggedIn("Codex isn't logged in — run `codex`"))
        } catch {
            return .failure(.notLoggedIn("Codex credential unreadable"))
        }
    }
}
