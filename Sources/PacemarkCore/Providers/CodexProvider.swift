import Foundation

/// Codex/ChatGPT usage provider (U5). Reads `~/.codex/auth.json` via `CredentialStore`
/// and calls the `wham/usage` endpoint. On 401, rereads a session the official client
/// may have renewed while the request was in flight (session-reliability KTD4).
/// Never rotates credentials itself. Never throws (KTD7 isolation).
public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex
    public let accountID: AccountID
    public let displayName = "Codex"

    private let creditCache = ResetCreditCache()
    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public init(
        credentials: CredentialStore,
        accountID: AccountID = .primary,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.accountID = accountID
        self.http = http
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        await fetchResult().snapshot
    }

    /// KTD2 (default-login plan): the token and `account_id` come from one file read, so
    /// the session a request used names its own account. A live reading is kept only when
    /// the session the fetch started with, the session whose token was accepted (they
    /// differ after a 401 reload) and a re-read after the request all name one account.
    public func fetchResult() async -> UsageProviderFetchResult {
        switch await credentials.codexSession() {
        case .failure(let reason):
            return UsageProviderFetchResult(snapshot: stale(reason))
        case .success(let session):
            let (snapshot, used) = await fetch(session: session, mayReload: true)
            guard snapshot.freshness == .live else { return UsageProviderFetchResult(snapshot: snapshot) }
            let after: AccountIdentityRead
            switch await credentials.codexSession() {
            case .success(let current): after = current.identityRead
            case .failure: after = .unreadable
            }
            let outcome = used.identity == session.identity
                ? AccountIdentityOutcome.bracketing(before: used.identityRead, after: after)
                : .unreadable
            guard outcome != .unreadable else { return .identityUnreadable(for: id) }
            return UsageProviderFetchResult(snapshot: snapshot.withIdentity(outcome))
        }
    }

    /// Returns the snapshot and the session whose token produced it.
    private func fetch(session: CodexSession, mayReload: Bool) async -> (UsageSnapshot, CodexSession) {
        switch await http.get(url: Self.endpoint, headers: ["Authorization": "Bearer \(session.accessToken)"]) {
        case .failure(let reason):
            return (stale(reason), session)
        case .success(let result):
            switch result.status {
            case 200:
                var snapshot = decode(result.body, accountEmail: session.accountEmail)
                if snapshot.freshness == .live {
                    snapshot.bankedCreditDetails = await creditCache.read(
                        count: snapshot.bankedResets, identity: session.identity, now: now()
                    ) {
                        guard case .success(let list) = await http.get(
                            url: ResetCreditEndpoint.list.url, headers: ["Authorization": "Bearer \(session.accessToken)"]
                        ), list.status == 200,
                           let object = (try? JSONSerialization.jsonObject(with: list.body)) as? [String: Any]
                        else { return nil }
                        return BankedCreditDetails.credits(from: object["credits"])
                    }
                }
                return (snapshot, session)
            case 401:
                if mayReload {
                    switch await credentials.codexSession() {
                    case .success(let current) where current.accessToken != session.accessToken:
                        return await fetch(session: current, mayReload: false)
                    case .failure(let reason):
                        return (stale(reason), session)
                    default:
                        // KTD6: an unchanged expired session is not evidence that
                        // the login was revoked. Keep retry and manual recovery.
                        return (stale(.providerSetup(.codexSessionUnverified)), session)
                    }
                }
                return (stale(.providerSetup(.codexRejectedAuth)), session)
            default:
                return (stale(UsageWindowBuilder.genericFailure(for: result.status)), session)
            }
        }
    }

    private func decode(_ body: Data, accountEmail: String?) -> UsageSnapshot {
        guard let dto = try? JSONDecoder().decode(CodexUsageDTO.self, from: body) else {
            return stale(.decode("Couldn’t read Codex usage response"))
        }
        let capturedAt = now()
        let main = CodexLimitBucket(
            label: nil, primary: CodexLimitWindow(dto.rate_limit?.primary_window, now: capturedAt),
            secondary: CodexLimitWindow(dto.rate_limit?.secondary_window, now: capturedAt)
        )
        // Preserve the response order, including older flat model counters.
        var windows = CodexWindowMapping.windows([main])
        for extra in dto.additional_rate_limits ?? [] {
            if let limit = extra.rate_limit {
                let bucket = CodexLimitBucket(
                    label: extra.displayLabel, primary: CodexLimitWindow(limit.primary_window, now: capturedAt),
                    secondary: CodexLimitWindow(limit.secondary_window, now: capturedAt)
                )
                windows += CodexWindowMapping.windows([bucket])
            } else if let window = UsageWindowBuilder.make(
                .other(extra.displayLabel), utilization: extra.utilizationValue, resetsAt: extra.resetAtValue,
                resetEpochSeconds: extra.resetEpochValue, resetsInSeconds: extra.resetSecondsValue, now: { capturedAt }
            ) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else {
            return stale(.decode("No usage windows in Codex response"))
        }
        return UsageSnapshot(
            providerID: id,
            windows: windows,
            planLabel: dto.plan_type,        // lenient: any string, incl. new tiers (#709)
            accountEmail: accountEmail,
            bankedResets: dto.resetCreditsField.bankedResets,
            codexResetCreditsField: dto.resetCreditsField,
            capturedAt: capturedAt,
            freshness: .live
        )
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}

enum ResetCreditEndpoint: CaseIterable {
    case list

    var url: URL {
        switch self {
        case .list: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
        }
    }
}

extension BankedCreditDetails {
    static func credits(from object: Any?, appServer: Bool = false) -> [Credit]? {
        guard let rows = object as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            if let status = row["status"] as? String, status.lowercased() != "available" { return nil }
            func date(_ wire: String, _ rpc: String) -> Date? {
                if appServer {
                    return (row[rpc] as? Double).map(Date.init(timeIntervalSince1970:))
                }
                return DateParsing.iso8601(row[wire] as? String)
            }
            return Credit(expiresAt: date("expires_at", "expiresAt"), grantedAt: date("granted_at", "grantedAt"))
        }
    }
}

actor ResetCreditCache {
    private var identity: AccountIdentity?
    private var count: Int?
    private var attempted: Date?
    private var details: BankedCreditDetails?
    private var generation = 0

    func read(count: Int?, identity: AccountIdentity?, now: Date,
              load: @Sendable () async -> [BankedCreditDetails.Credit]?) async -> BankedCreditDetails? {
        if identity != self.identity || count == 0 {
            details = nil
            attempted = nil
            generation += 1
        }
        self.identity = identity
        guard let count, count > 0 else { return nil }
        if self.count != count || attempted.map({ now.timeIntervalSince($0) >= 21600 }) != false {
            self.count = count
            attempted = now
            generation += 1
            let request = generation
            let credits = await load()
            guard request == generation else { return nil }
            if let credits { details = .init(credits: credits, observedAt: now) }
        }
        return details
    }
}
