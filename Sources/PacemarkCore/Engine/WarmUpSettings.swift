import Foundation

public struct WarmUpSettings: Codable, Sendable, Equatable {
    public static let supportedWindows: [WindowKind] = [.fiveHour, .weekly]

    public static func windows(for provider: ProviderID) -> [WindowKind] {
        provider == .antigravity ? [.fiveHour, .weekly].map { AntigravityProvider.windowKind(.gemini, $0) } : supportedWindows
    }

    public struct Selection: Codable, Sendable, Hashable {
        public let account: AccountKey
        public let windowID: String
        /// Bind consent to the login that was displayed when the user enabled it.
        public let identity: AccountIdentity?

        public init(account: AccountKey, window: WindowKind, identity: AccountIdentity? = nil) {
            self.account = account
            self.windowID = window.persistentID
            self.identity = identity
        }
    }

    public enum ActiveHours: Codable, Sendable, Equatable {
        case anyTime
        case interval(startMinute: Int, endMinute: Int)

        public static let standard = Self.interval(startMinute: 7 * 60, endMinute: 23 * 60)

        public func contains(_ date: Date, calendar: Calendar) -> Bool {
            switch self {
            case .anyTime:
                return true
            case .interval(let start, let end):
                guard (0..<1440).contains(start), (0..<1440).contains(end), start != end else { return false }
                let time = calendar.dateComponents([.hour, .minute], from: date)
                let minute = (time.hour ?? 0) * 60 + (time.minute ?? 0)
                return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
            }
        }
    }

    public var isEnabled: Bool
    public var enabled: Set<Selection>
    public var activeHours: ActiveHours

    public init(isEnabled: Bool? = nil, enabled: Set<Selection> = [], activeHours: ActiveHours = .standard) {
        self.isEnabled = isEnabled ?? !enabled.isEmpty
        self.enabled = enabled
        self.activeHours = activeHours
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Set<Selection>.self, forKey: .enabled)
            .filter { selection in Self.windows(for: selection.account.providerID).contains { $0.persistentID == selection.windowID } }
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? !enabled.isEmpty
        activeHours = try container.decode(ActiveHours.self, forKey: .activeHours)
    }

    public static let defaultsKey = "t3.warmUp.v1"

    public static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
