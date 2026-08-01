import Foundation

/// Wire shape returned by the Grok Build billing surface. The endpoint has shipped
/// both percentage/period fields and older cent-based fields, so decoding stays
/// additive and the provider decides which representation is authoritative.
struct GrokBillingResponseDTO: Decodable {
    let config: GrokBillingConfigDTO?
    let subscriptionTier: String?
}

struct GrokBillingConfigDTO: Decodable {
    let creditUsagePercent: Double?
    let currentPeriod: GrokUsagePeriodDTO?
    let monthlyLimit: GrokCentDTO?
    let used: GrokCentDTO?
    let onDemandCap: GrokCentDTO?
    let onDemandUsed: GrokCentDTO?
    let prepaidBalance: GrokCentDTO?
    let isUnifiedBillingUser: Bool?
    let billingPeriodStart: String?
    let billingPeriodEnd: String?
}

struct GrokUsagePeriodDTO: Decodable {
    let type: String?
    let start: String?
    let end: String?
}

struct GrokCentDTO: Decodable {
    let val: Double

    private enum CodingKeys: String, CodingKey { case val }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Double.self, forKey: .val) {
            val = value
        } else if let value = try? container.decode(Int.self, forKey: .val) {
            val = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .val),
                  let parsed = Double(value) {
            val = parsed
        } else if !container.contains(.val) {
            // proto3 JSON omits zero-valued scalars, so a zero Cent is `{}`.
            val = 0
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .val,
                in: container,
                debugDescription: "Unsupported cent value"
            )
        }
    }
}

enum GrokPeriodType {
    static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.uppercased() {
        case "USAGE_PERIOD_TYPE_WEEKLY": return "weekly"
        case "USAGE_PERIOD_TYPE_MONTHLY": return "monthly"
        default: return raw
        }
    }
}
