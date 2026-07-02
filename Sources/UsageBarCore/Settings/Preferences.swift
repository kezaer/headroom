import Foundation

/// UserDefaults-backed preferences (U8). Renewal dates and poll interval are
/// non-secret, so they live here, not the Keychain (KTD4). The `Preferences` type
/// lands early (with U2) because U6 reads the interval and U7 reads renewal dates.
public struct Preferences: @unchecked Sendable { // UserDefaults is thread-safe
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let interval = "pollIntervalMinutes"
        static func renewal(_ id: ProviderID) -> String { "renewalDate.\(id.raw)" }
    }

    public static let defaultIntervalMinutes = 5

    public var pollIntervalMinutes: Int {
        get {
            let v = defaults.integer(forKey: Key.interval)
            return v > 0 ? v : Self.defaultIntervalMinutes
        }
        nonmutating set { defaults.set(max(1, newValue), forKey: Key.interval) }
    }

    public func renewalDate(for id: ProviderID) -> Date? {
        let t = defaults.double(forKey: Key.renewal(id))
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    public func setRenewalDate(_ date: Date?, for id: ProviderID) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: Key.renewal(id))
        } else {
            defaults.removeObject(forKey: Key.renewal(id))
        }
    }
}
