import Foundation

// Decoders are lenient (KTD6): unknown keys are ignored by `Decodable`, unknown
// enum-ish values pass through as strings, and one unrecognized field never blanks
// the whole snapshot. Exact field names for both undocumented endpoints must be
// verified against a live capture (U9 for Claude; a Codex `wham/usage` capture).

// MARK: - Claude (api.anthropic.com/api/oauth/usage)

struct ClaudeUsageDTO: Decodable {
    let five_hour: ClaudeWindowDTO?
    let seven_day: ClaudeWindowDTO?
    let subscriptionType: String?
}

struct ClaudeWindowDTO: Decodable {
    let utilization: Double?
    let resets_at: String?
}

// MARK: - Codex (chatgpt.com/backend-api/wham/usage)

struct CodexUsageDTO: Decodable {
    let rate_limit: CodexRateLimitDTO?
    let plan_type: String?
    let additional_rate_limits: [CodexNamedWindowDTO]?
}

struct CodexRateLimitDTO: Decodable {
    let primary_window: CodexWindowDTO?
    let secondary_window: CodexWindowDTO?
}

struct CodexWindowDTO: Decodable {
    // Accept several plausible field names for percent-used; whichever is present wins.
    let used_percent: Double?
    let usage_percent: Double?
    let utilization: Double?
    let resets_at: String?
    let resets_in_seconds: Double?

    var utilizationValue: Double? { used_percent ?? usage_percent ?? utilization }
}

struct CodexNamedWindowDTO: Decodable {
    let name: String?
    let label: String?
    let used_percent: Double?
    let usage_percent: Double?
    let utilization: Double?
    let resets_at: String?
    let resets_in_seconds: Double?

    var displayLabel: String { name ?? label ?? "other" }
    var utilizationValue: Double? { used_percent ?? usage_percent ?? utilization }
}

// MARK: - Shared window construction

/// Builds a `UsageWindow` from decoded parts, tolerating either an ISO reset time or
/// a relative `resets_in_seconds`. Shared by both providers so window assembly and the
/// generic HTTP-status failure mapping live in one place.
enum UsageWindowBuilder {
    static func make(
        _ kind: WindowKind,
        _ utilization: Double?,
        _ resetsAt: String?,
        _ resetsInSeconds: Double?,
        now: () -> Date
    ) -> UsageWindow? {
        guard let utilization else { return nil }
        let reset: Date
        if let d = DateParsing.iso8601(resetsAt) {
            reset = d
        } else if let seconds = resetsInSeconds {
            reset = now().addingTimeInterval(seconds)
        } else {
            return nil
        }
        return UsageWindow(kind: kind, utilization: utilization, resetsAt: reset)
    }

    /// Failure reason for HTTP statuses both providers handle identically.
    static func genericFailure(for status: Int) -> FailureReason {
        status == 429 ? .transient("Rate limited — will retry")
                      : .transient("Service error (\(status))")
    }
}
