import Foundation

public enum WidgetSnapshotCacheRead: Equatable, Sendable {
    case unavailable
    case empty
    case corrupt
    case snapshot(WidgetSnapshotEnvelope)

    public var envelope: WidgetSnapshotEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

/// App Group-backed widget cache. Production uses the app-group suite; tests inject an
/// isolated defaults suite so entitlement state never affects unit tests.
public struct WidgetSnapshotCache: @unchecked Sendable { // UserDefaults is thread-safe
    public static let appGroupSuiteName = "group.com.kylezantos.headroom"

    private static let key = "widgetSnapshotEnvelope"
    private let defaults: UserDefaults?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public static func appGroup() -> WidgetSnapshotCache {
        WidgetSnapshotCache(defaults: UserDefaults(suiteName: appGroupSuiteName))
    }

    public func read() -> WidgetSnapshotCacheRead {
        guard let defaults else { return .unavailable }
        guard let data = defaults.data(forKey: Self.key) else { return .empty }
        do {
            return .snapshot(try decoder.decode(WidgetSnapshotEnvelope.self, from: data))
        } catch {
            return .corrupt
        }
    }

    public func write(_ envelope: WidgetSnapshotEnvelope) throws {
        guard let defaults else { throw WidgetSnapshotCacheError.unavailable }
        defaults.set(try encoder.encode(envelope), forKey: Self.key)
    }
}

public enum WidgetSnapshotCacheError: Error, Equatable {
    case unavailable
}
