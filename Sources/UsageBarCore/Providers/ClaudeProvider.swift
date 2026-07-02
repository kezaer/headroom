import Foundation

/// Best-effort `claude-code/<version>` User-Agent source (KTD1). Reads the installed
/// `claude` CLI version once, with a pinned static fallback so the header is never
/// empty. The U9 spike confirms whether this header actually clears the 429.
public enum ClaudeVersion {
    /// Pinned fallback used when the CLI can't be read. Bump when needed.
    public static let fallback = "2.0.0"

    public static func userAgent(_ version: String) -> String { "claude-code/\(version)" }

    /// Attempts `claude --version`; returns the fallback on any failure.
    public static func detected() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8),
               let match = text.firstMatch(of: /(\d+\.\d+\.\d+)/) {
                return String(match.1)
            }
        } catch {}
        return fallback
    }
}

/// Claude usage provider (U4). Reuses the Claude Code credential via `CredentialStore`,
/// calls the OAuth usage endpoint, decodes leniently, and maps failures to the typed
/// taxonomy (KTD7). Never throws — always returns a snapshot (KTD7 isolation).
public struct ClaudeProvider: UsageProvider {
    public let id = ProviderID.claude
    public let displayName = "Claude"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let version: @Sendable () -> String
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        version: @escaping @Sendable () -> String = { ClaudeVersion.fallback },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.version = version
        self.now = now
    }

    public func fetchSnapshot() async -> UsageSnapshot {
        switch await credentials.claudeAccessToken() {
        case .failure(let reason):
            return stale(reason)
        case .success(let token):
            let outcome = await call(token: token)
            switch outcome {
            case .success(let snapshot):
                return snapshot
            case .permanent(let reason):
                return stale(reason)
            case .transient(let reason):
                return stale(reason)
            case .unauthorized:
                // One refresh-and-retry (KTD7). A second 401 is permanent, but a
                // transient failure on the retry (429/network) stays transient — it
                // must not be misreported as a permanent re-login.
                switch await credentials.forceRefreshClaude() {
                case .failure(let reason):
                    return stale(reason)
                case .success(let refreshed):
                    switch await call(token: refreshed) {
                    case .success(let snapshot): return snapshot
                    case .permanent(let reason): return stale(reason)
                    case .transient(let reason): return stale(reason)
                    case .unauthorized: return stale(.needsReauth("Session expired — run `claude` to re-login"))
                    }
                }
            }
        }
    }

    private enum Outcome {
        case success(UsageSnapshot)
        case unauthorized
        case permanent(FailureReason)
        case transient(FailureReason)
    }

    private func call(token: String) async -> Outcome {
        let headers = [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "Content-Type": "application/json",
            "User-Agent": ClaudeVersion.userAgent(version()),
        ]
        switch await http.get(url: Self.endpoint, headers: headers) {
        case .failure(let reason):
            return .transient(reason)
        case .success(let result):
            switch result.status {
            case 200:
                return decode(result.body)
            case 401:
                return .unauthorized
            case 403:
                return .permanent(.scopeDenied("Re-authenticate in Claude Code (missing scope)"))
            default:
                return .transient(UsageWindowBuilder.genericFailure(for: result.status))
            }
        }
    }

    private func decode(_ body: Data) -> Outcome {
        guard let dto = try? JSONDecoder().decode(ClaudeUsageDTO.self, from: body) else {
            return .transient(.decode("Couldn't read Claude usage response"))
        }
        let windows = [
            UsageWindowBuilder.make(.fiveHour, utilization: dto.five_hour?.utilization, resetsAt: dto.five_hour?.resets_at, resetsInSeconds: nil, now: now),
            UsageWindowBuilder.make(.weekly, utilization: dto.seven_day?.utilization, resetsAt: dto.seven_day?.resets_at, resetsInSeconds: nil, now: now),
        ].compactMap { $0 }
        guard !windows.isEmpty else {
            return .transient(.decode("No usage windows in Claude response"))
        }
        return .success(UsageSnapshot(
            providerID: id,
            windows: windows,
            planLabel: dto.subscriptionType,
            capturedAt: now(),
            freshness: .live
        ))
    }

    private func stale(_ reason: FailureReason) -> UsageSnapshot {
        .stale(for: id, reason: reason)
    }
}
