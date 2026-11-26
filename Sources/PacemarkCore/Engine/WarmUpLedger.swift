import Foundation

public enum WarmUpFailure: Codable, Sendable, Equatable {
    case cliNotFound
    case workspaceUnavailable
    case launchFailed
    case timedOut
    case clientFailed

    case signedOut
    case rejectedArguments
    case exitedNonZero(Int32)

    // Preserve the original single-string ledger format across upgrades.
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "cliNotFound": self = .cliNotFound
        case "workspaceUnavailable": self = .workspaceUnavailable
        case "launchFailed": self = .launchFailed
        case "timedOut": self = .timedOut
        case "clientFailed": self = .clientFailed
        case "signedOut": self = .signedOut
        case "rejectedArguments": self = .rejectedArguments
        default:
            guard let code = Int32(value) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown warm-up failure")) }
            self = .exitedNonZero(code)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let value: String = switch self {
        case .cliNotFound: "cliNotFound"
        case .workspaceUnavailable: "workspaceUnavailable"
        case .launchFailed: "launchFailed"
        case .timedOut: "timedOut"
        case .clientFailed: "clientFailed"
        case .signedOut: "signedOut"
        case .rejectedArguments: "rejectedArguments"
        case .exitedNonZero(let code): String(code)
        }
        try container.encode(value)
    }

    public var message: String {
        switch self {
        case .cliNotFound: "CLI not found"
        case .workspaceUnavailable: "Working folder unavailable"
        case .launchFailed: "Could not start the CLI"
        case .timedOut: "CLI timed out"
        case .signedOut: "Signed out"
        case .rejectedArguments: "CLI rejected the arguments"
        case .exitedNonZero(let code): "CLI exited with code \(code)"
        case .clientFailed: "CLI returned an error"
        }
    }
}

public enum WarmUpOutcome: Codable, Sendable, Equatable {
    case reserved
    case sent
    case failed(WarmUpFailure)
    case skipped

    var ranClient: Bool {
        switch self {
        case .sent, .failed(.timedOut), .failed(.clientFailed), .failed(.signedOut), .failed(.rejectedArguments), .failed(.exitedNonZero): true
        default: false
        }
    }
}

public struct WarmUpLedger: Codable, Sendable, Equatable {
    public struct Attempt: Codable, Sendable, Equatable {
        public let id: UUID
        public let account: AccountKey
        public let identity: AccountIdentity?
        public let startedAt: Date
        public fileprivate(set) var startedLimits: String?
        public fileprivate(set) var outcome: WarmUpOutcome
    }

    private struct WarmedCycle: Codable, Sendable, Equatable {
        let account: AccountKey
        let identity: AccountIdentity?
        let windowID: String
        let resetDeadline: Date

        func matches(_ account: AccountKey, identity: AccountIdentity?, windowID: String) -> Bool {
            self.windowID == windowID && self.identity == identity
                && (identity != nil || self.account == account)
        }
    }

    public private(set) var attempts: [Attempt] = []
    private var warmedCycles: [WarmedCycle] = []

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attempts = try container.decode([Attempt].self, forKey: .attempts)
        warmedCycles = try container.decodeIfPresent([WarmedCycle].self, forKey: .warmedCycles) ?? []
    }

    public func lastAttempt(for account: AccountKey, identity: AccountIdentity? = nil) -> Attempt? {
        attempts.last { $0.account == account && $0.identity == identity }
    }

    public func canAttempt(
        _ account: AccountKey, identity: AccountIdentity?, now: Date, calendar: Calendar,
        excludingAttemptID: UUID? = nil
    ) -> Bool {
        // Protect both the slot and aliases of the same known subscription.
        let matching = attempts.filter {
            $0.id != excludingAttemptID && ($0.account == account || (identity != nil && $0.identity == identity))
        }
        guard !matching.contains(where: { now.timeIntervalSince($0.startedAt) < WarmUpPlanner.minimumSpacing })
        else { return false }
        return matching.filter { calendar.isDate($0.startedAt, inSameDayAs: now) }.count < WarmUpPlanner.dailyLimit
    }

    /// Persist the claim before launching. A quit between dispatch and completion still
    /// leaves a claim for cooldown and the daily cap.
    @discardableResult
    public mutating func reserve(_ account: AccountKey, identity: AccountIdentity?, at now: Date) -> Attempt {
        let cutoff = now.addingTimeInterval(-3 * 86_400)
        attempts.removeAll { $0.startedAt < cutoff }
        warmedCycles.removeAll { $0.resetDeadline < cutoff }
        let attempt = Attempt(id: UUID(), account: account, identity: identity, startedAt: now, outcome: .reserved)
        attempts.append(attempt)
        return attempt
    }

    public mutating func finish(_ attempt: Attempt, outcome: WarmUpOutcome, resetDeadlines: [String: Date] = [:]) {
        guard let index = attempts.lastIndex(where: { $0.id == attempt.id && $0.outcome == .reserved }) else { return }
        attempts[index].outcome = outcome
        guard outcome == .sent else { return }
        let limits = WarmUpSettings.windows(for: attempt.account.providerID).enumerated().compactMap { index, kind in
            resetDeadlines[kind.persistentID] == nil ? nil : (index == 0 ? "5h" : "weekly")
        }.joined(separator: " + ")
        attempts[index].startedLimits = limits.isEmpty ? nil : limits
        for (windowID, deadline) in resetDeadlines {
            warmedCycles.removeAll { $0.matches(attempt.account, identity: attempt.identity, windowID: windowID) }
            warmedCycles.append(.init(account: attempt.account, identity: attempt.identity,
                                      windowID: windowID, resetDeadline: deadline))
        }
    }

    func canWarm(
        _ windowID: String, for account: AccountKey, identity: AccountIdentity?, now: Date, observedAt: Date
    ) -> Bool {
        !warmedCycles.contains {
            $0.matches(account, identity: identity, windowID: windowID)
                && !(now > $0.resetDeadline && observedAt > $0.resetDeadline)
        }
    }

    public static let defaultsKey = "t3.warmUp.ledger.v1"

    /// A corrupt ledger cannot prove the account still has attempts available.
    public static func load(from defaults: UserDefaults) -> Self? {
        guard let data = defaults.object(forKey: defaultsKey) else { return Self() }
        guard let data = data as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    @discardableResult
    public func save(to defaults: UserDefaults) -> Bool {
        guard let data = try? JSONEncoder().encode(self) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }
}
