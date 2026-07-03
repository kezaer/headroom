import Foundation

// Decoders are lenient (KTD6): unknown keys are ignored by `Decodable`, unknown
// enum-ish values pass through as strings, and one unrecognized field never blanks
// the whole snapshot. Exact field names must be verified against a live Codex
// `wham/usage` capture.

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
    let reset_at: String?
    let resetAtEpoch: Double?
    let resets_at: String?
    let reset_after_seconds: Double?
    let resets_in_seconds: Double?

    var utilizationValue: Double? { used_percent ?? usage_percent ?? utilization }
    var resetAtValue: String? { resets_at ?? reset_at }
    var resetEpochValue: Double? { resetAtEpoch }
    var resetSecondsValue: Double? { resets_in_seconds ?? reset_after_seconds }

    enum CodingKeys: String, CodingKey {
        case used_percent, usage_percent, utilization
        case reset_at, resets_at, reset_after_seconds, resets_in_seconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        used_percent = c.flexibleDouble(.used_percent)
        usage_percent = c.flexibleDouble(.usage_percent)
        utilization = c.flexibleDouble(.utilization)
        resets_at = c.flexibleString(.resets_at)
        reset_at = c.flexibleString(.reset_at)
        resetAtEpoch = c.flexibleDouble(.reset_at)
        reset_after_seconds = c.flexibleDouble(.reset_after_seconds)
        resets_in_seconds = c.flexibleDouble(.resets_in_seconds)
    }
}

struct CodexNamedWindowDTO: Decodable {
    let name: String?
    let label: String?
    let limit_name: String?
    let metered_feature: String?
    let used_percent: Double?
    let usage_percent: Double?
    let utilization: Double?
    let reset_at: String?
    let resetAtEpoch: Double?
    let resets_at: String?
    let reset_after_seconds: Double?
    let resets_in_seconds: Double?
    let rate_limit: CodexRateLimitDTO?

    var displayLabel: String { name ?? label ?? limit_name ?? metered_feature ?? "other" }
    var utilizationValue: Double? { used_percent ?? usage_percent ?? utilization }
    var resetAtValue: String? { resets_at ?? reset_at }
    var resetEpochValue: Double? { resetAtEpoch }
    var resetSecondsValue: Double? { resets_in_seconds ?? reset_after_seconds }

    enum CodingKeys: String, CodingKey {
        case name, label, limit_name, metered_feature
        case used_percent, usage_percent, utilization
        case reset_at, resets_at, reset_after_seconds, resets_in_seconds
        case rate_limit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexibleString(.name)
        label = c.flexibleString(.label)
        limit_name = c.flexibleString(.limit_name)
        metered_feature = c.flexibleString(.metered_feature)
        used_percent = c.flexibleDouble(.used_percent)
        usage_percent = c.flexibleDouble(.usage_percent)
        utilization = c.flexibleDouble(.utilization)
        resets_at = c.flexibleString(.resets_at)
        reset_at = c.flexibleString(.reset_at)
        resetAtEpoch = c.flexibleDouble(.reset_at)
        reset_after_seconds = c.flexibleDouble(.reset_after_seconds)
        resets_in_seconds = c.flexibleDouble(.resets_in_seconds)
        rate_limit = try? c.decode(CodexRateLimitDTO.self, forKey: .rate_limit)
    }
}

// MARK: - Shared window construction

/// Builds a `UsageWindow` from decoded parts, tolerating either an ISO reset time or
/// a relative `resets_in_seconds`. Shared by both providers so window assembly and the
/// generic HTTP-status failure mapping live in one place.
enum UsageWindowBuilder {
    static func make(
        _ kind: WindowKind,
        utilization: Double?,
        resetsAt: String?,
        resetEpochSeconds: Double? = nil,
        resetsInSeconds: Double?,
        now: () -> Date
    ) -> UsageWindow? {
        guard let utilization else { return nil }
        let reset: Date
        if let d = DateParsing.iso8601(resetsAt) {
            reset = d
        } else if let epoch = resetEpochSeconds {
            reset = Date(timeIntervalSince1970: epoch)
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

private extension KeyedDecodingContainer {
    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func flexibleString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        return nil
    }
}
