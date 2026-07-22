import Foundation

/// Redaction-safe persistence for last-known subscription windows. This cache stores
/// only display-ready usage values keyed by provider/account; credentials, raw provider
/// responses, CLI output, paths, and failure details never cross this boundary.
public protocol UsageContinuityCaching: Sendable {
    func load() -> [AccountKey: UsageSnapshot]
    func save(_ snapshot: UsageSnapshot, for key: AccountKey)
    func remove(for key: AccountKey)
}

/// UserDefaults-backed continuity across app launches. `UsageStore` still owns freshness
/// and expiry decisions; this type only round-trips bounded, non-secret snapshot data.
public struct UsageContinuityCache: UsageContinuityCaching, @unchecked Sendable {
    private static let storageKey = "usageContinuitySnapshots.v1"
    private static let maximumRecords = AccountRegistry.maxPerProvider * 2

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [AccountKey: UsageSnapshot] {
        Dictionary(
            records().compactMap { record in
                guard let snapshot = record.snapshot else { return nil }
                return (record.key, snapshot)
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    public func save(_ snapshot: UsageSnapshot, for key: AccountKey) {
        guard snapshot.providerID == key.providerID else { return }
        var stored = records().filter { $0.key != key }
        if !snapshot.windows.isEmpty {
            stored.append(StoredSnapshot(key: key, snapshot: snapshot))
        }
        write(Array(stored.suffix(Self.maximumRecords)))
    }

    public func remove(for key: AccountKey) {
        write(records().filter { $0.key != key })
    }

    private func records() -> [StoredSnapshot] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let records = try? JSONDecoder().decode([StoredSnapshot].self, from: data)
        else { return [] }
        return records
    }

    private func write(_ records: [StoredSnapshot]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

private struct StoredSnapshot: Codable {
    let key: AccountKey
    let windows: [StoredWindow]
    let planLabel: String?
    let capturedAt: Date?

    init(key: AccountKey, snapshot: UsageSnapshot) {
        self.key = key
        self.windows = snapshot.windows.map(StoredWindow.init)
        self.planLabel = snapshot.planLabel
        self.capturedAt = snapshot.capturedAt
    }

    var snapshot: UsageSnapshot? {
        let restoredWindows = windows.compactMap(\.usageWindow)
        guard !restoredWindows.isEmpty else { return nil }
        return UsageSnapshot(
            providerID: key.providerID,
            windows: restoredWindows,
            planLabel: planLabel,
            capturedAt: capturedAt,
            freshness: .stale(.transient("Last known usage — refreshing"))
        )
    }
}

private struct StoredWindow: Codable {
    private enum Kind: String, Codable {
        case fiveHour
        case weekly
        case other
    }

    private let kind: Kind
    let otherLabel: String?
    let utilization: Double
    let resetsAt: Date
    let resetLabel: String?

    init(_ window: UsageWindow) {
        switch window.kind {
        case .fiveHour:
            self.kind = .fiveHour
            self.otherLabel = nil
        case .weekly:
            self.kind = .weekly
            self.otherLabel = nil
        case .other(let label):
            self.kind = .other
            self.otherLabel = label
        }
        self.utilization = window.utilization
        self.resetsAt = window.resetsAt
        self.resetLabel = window.resetLabel
    }

    var usageWindow: UsageWindow? {
        guard utilization.isFinite else { return nil }
        let restoredKind: WindowKind
        switch kind {
        case .fiveHour:
            restoredKind = .fiveHour
        case .weekly:
            restoredKind = .weekly
        case .other:
            guard let otherLabel, !otherLabel.isEmpty else { return nil }
            restoredKind = .other(otherLabel)
        }
        return UsageWindow(
            kind: restoredKind,
            utilization: utilization,
            resetsAt: resetsAt,
            resetLabel: resetLabel
        )
    }
}
