import Foundation

/// Codex/ChatGPT usage provider (U5). Reads `~/.codex/auth.json` via `CredentialStore`
/// and calls the `wham/usage` endpoint. Does not attempt OpenAI's refresh — on 401 it
/// degrades to "run codex" (KTD3). Never throws (KTD7 isolation).
public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex
    public let displayName = "Codex"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await credentials.codexAccessToken() {
        case .failure(let reason):
            return stale(reason)
        case .success(let token):
            switch await http.get(url: Self.endpoint, headers: ["Authorization": "Bearer \(token)"]) {
            case .failure(let reason):
                return stale(reason)
            case .success(let result):
                switch result.status {
                case 200:
                    return decode(result.body)
                case 401:
                    return stale(.needsReauth("Session expired — run `codex` to refresh"))
                default:
                    return stale(UsageWindowBuilder.genericFailure(for: result.status))
                }
            }
        }
    }

    private func decode(_ body: Data) -> UsageSnapshot {
        guard let dto = try? JSONDecoder().decode(CodexUsageDTO.self, from: body) else {
            return stale(.decode("Couldn't read Codex usage response"))
        }
        var windows: [UsageWindow] = []
        if let w = dto.rate_limit?.primary_window,
           let win = UsageWindowBuilder.make(.fiveHour, w.utilizationValue, w.resets_at, w.resets_in_seconds, now: now) {
            windows.append(win)
        }
        if let w = dto.rate_limit?.secondary_window,
           let win = UsageWindowBuilder.make(.weekly, w.utilizationValue, w.resets_at, w.resets_in_seconds, now: now) {
            windows.append(win)
        }
        for extra in dto.additional_rate_limits ?? [] {
            if let win = UsageWindowBuilder.make(.other(extra.displayLabel), extra.utilizationValue, extra.resets_at, extra.resets_in_seconds, now: now) {
                windows.append(win)
            }
        }
        guard !windows.isEmpty else {
            return stale(.decode("No usage windows in Codex response"))
        }
        return UsageSnapshot(
            providerID: id,
            windows: windows,
            planLabel: dto.plan_type,        // lenient: any string, incl. new tiers (#709)
            capturedAt: now(),
            freshness: .live
        )
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}
