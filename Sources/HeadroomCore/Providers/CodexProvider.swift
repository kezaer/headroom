import Foundation

/// Codex/ChatGPT usage provider (U5). Reads `~/.codex/auth.json` via `CredentialStore`
/// and calls the `wham/usage` endpoint. Does not attempt OpenAI's refresh — on 401 it
/// degrades to the official CLI login handoff (KTD3). Never throws (KTD7 isolation).
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
                    return stale(.needsReauth("Session expired — run `\(CodexCLI.loginCommand)` to reconnect"))
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
           let win = UsageWindowBuilder.make(.fiveHour, utilization: w.utilizationValue, resetsAt: w.resetAtValue, resetEpochSeconds: w.resetEpochValue, resetsInSeconds: w.resetSecondsValue, now: now) {
            windows.append(win)
        }
        if let w = dto.rate_limit?.secondary_window,
           let win = UsageWindowBuilder.make(.weekly, utilization: w.utilizationValue, resetsAt: w.resetAtValue, resetEpochSeconds: w.resetEpochValue, resetsInSeconds: w.resetSecondsValue, now: now) {
            windows.append(win)
        }
        for extra in dto.additional_rate_limits ?? [] {
            let label = extra.displayLabel
            if let w = extra.rate_limit?.primary_window,
               let win = UsageWindowBuilder.make(.other("\(label) 5h"), utilization: w.utilizationValue, resetsAt: w.resetAtValue, resetEpochSeconds: w.resetEpochValue, resetsInSeconds: w.resetSecondsValue, now: now) {
                windows.append(win)
            }
            if let w = extra.rate_limit?.secondary_window,
               let win = UsageWindowBuilder.make(.other("\(label) weekly"), utilization: w.utilizationValue, resetsAt: w.resetAtValue, resetEpochSeconds: w.resetEpochValue, resetsInSeconds: w.resetSecondsValue, now: now) {
                windows.append(win)
            }
            if extra.rate_limit == nil,
               let win = UsageWindowBuilder.make(.other(label), utilization: extra.utilizationValue, resetsAt: extra.resetAtValue, resetEpochSeconds: extra.resetEpochValue, resetsInSeconds: extra.resetSecondsValue, now: now) {
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
