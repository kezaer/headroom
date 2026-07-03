import Foundation

public struct OpenAIAPISpendProvider: APISpendProvider {
    public let id = ProviderID.codex
    public let displayName = "OpenAI API"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://api.openai.com/v1/organization/costs")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.now = now
    }

    public func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        let range = period.range(now: now())
        switch await credentials.apiKey(for: .openAI) {
        case .failure(let reason):
            return stale(range, reason)
        case .success(let key):
            switch await http.get(url: Self.endpoint.withOpenAICostQuery(range), headers: ["Authorization": "Bearer \(key)"]) {
            case .failure(let reason):
                return stale(range, reason)
            case .success(let result):
                switch result.status {
                case 200:
                    return decode(result.body, range: range)
                case 401:
                    return stale(range, .needsReauth("OpenAI admin key rejected"))
                case 403:
                    return stale(range, .scopeDenied("OpenAI key lacks organization cost access"))
                default:
                    return stale(range, UsageWindowBuilder.genericFailure(for: result.status))
                }
            }
        }
    }

    private func decode(_ body: Data, range: APISpendRange) -> APISpendSnapshot {
        guard let dto = try? JSONDecoder().decode(OpenAICostsDTO.self, from: body),
              let total = CostAccumulator.total(from: dto.data.flatMap(\.results), emptyIsZero: true)
        else { return stale(range, .decode("Couldn't read OpenAI cost response")) }
        return APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: total.amount,
            currency: total.currency,
            periodLabel: range.label,
            capturedAt: now(),
            freshness: .live
        )
    }

    private func stale(_ range: APISpendRange, _ reason: FailureReason) -> APISpendSnapshot {
        .stale(providerID: id, displayName: displayName, periodLabel: range.label, reason: reason)
    }
}

public struct AnthropicAPISpendProvider: APISpendProvider {
    public let id = ProviderID.claude
    public let displayName = "Anthropic API"

    private let credentials: CredentialStore
    private let http: UsageFetching
    private let now: @Sendable () -> Date

    static let endpoint = URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!

    public init(
        credentials: CredentialStore,
        http: UsageFetching = RedirectBlockingHTTPClient(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.http = http
        self.now = now
    }

    public func fetchSpend(period: APISpendPeriod) async -> APISpendSnapshot {
        let range = period.range(now: now())
        switch await credentials.apiKey(for: .anthropic) {
        case .failure(let reason):
            return stale(range, reason)
        case .success(let key):
            let headers = [
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
            ]
            switch await http.get(url: Self.endpoint.withAnthropicCostQuery(range), headers: headers) {
            case .failure(let reason):
                return stale(range, reason)
            case .success(let result):
                switch result.status {
                case 200:
                    return decode(result.body, range: range)
                case 401:
                    return stale(range, .needsReauth("Anthropic admin key rejected"))
                case 403:
                    return stale(range, .scopeDenied("Anthropic key lacks cost report access"))
                default:
                    return stale(range, UsageWindowBuilder.genericFailure(for: result.status))
                }
            }
        }
    }

    private func decode(_ body: Data, range: APISpendRange) -> APISpendSnapshot {
        guard let dto = try? JSONDecoder().decode(AnthropicCostReportDTO.self, from: body),
              let total = CostAccumulator.total(from: dto.costResults, emptyIsZero: dto.hasCostContainer)
        else { return stale(range, .decode("Couldn't read Anthropic cost response")) }
        return APISpendSnapshot(
            providerID: id,
            displayName: displayName,
            amount: total.amount,
            currency: total.currency,
            periodLabel: range.label,
            capturedAt: now(),
            freshness: .live
        )
    }

    private func stale(_ range: APISpendRange, _ reason: FailureReason) -> APISpendSnapshot {
        .stale(providerID: id, displayName: displayName, periodLabel: range.label, reason: reason)
    }
}

private extension URL {
    func withOpenAICostQuery(_ range: APISpendRange) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(Int(range.start.timeIntervalSince1970))"),
            URLQueryItem(name: "end_time", value: "\(Int(range.end.timeIntervalSince1970))"),
            URLQueryItem(name: "bucket_width", value: "1d"),
        ]
        return components.url ?? self
    }

    func withAnthropicCostQuery(_ range: APISpendRange) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: DateFormatting.apiDate(range.start)),
            URLQueryItem(name: "ending_at", value: DateFormatting.apiDate(range.end)),
        ]
        return components.url ?? self
    }
}

private enum DateFormatting {
    static func apiDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
