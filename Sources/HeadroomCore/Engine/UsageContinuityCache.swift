import Foundation

/// Redaction-safe persistence for last-known subscription windows. This cache stores
/// only display-ready values keyed by provider/account — usage numbers plus the plan
/// label and account email the UI already shows; credentials, raw provider responses,
/// CLI output, paths, and failure details never cross this boundary.
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
    /// Persisted alongside the plan label so a relaunch still names the account before
    /// the first poll lands. Optional, so records written by earlier builds still decode.
    let accountEmail: String?
    let capturedAt: Date?

    init(key: AccountKey, snapshot: UsageSnapshot) {
        self.key = key
        self.windows = snapshot.windows.map(StoredWindow.init)
        self.planLabel = snapshot.planLabel
        self.accountEmail = snapshot.accountEmail
        self.capturedAt = snapshot.capturedAt
    }

    var snapshot: UsageSnapshot? {
        let restoredWindows = windows.compactMap(\.usageWindow)
        guard !restoredWindows.isEmpty else { return nil }
        return UsageSnapshot(
            providerID: key.providerID,
            windows: restoredWindows,
            planLabel: planLabel,
            accountEmail: accountEmail,
            capturedAt: capturedAt,
            freshness: .stale(.transient("Last known usage — refreshing"))
        )
    }
}

private struct StoredWindow: Codable {
    private enum Kind: String, Codable {
        case fiveHour
        case weekly
        case billingPeriod
        case other
    }

    private let kind: Kind
    let otherLabel: String?
    let billingPeriodDuration: TimeInterval?
    let utilization: Double
    let resetsAt: Date
    let resetLabel: String?
    let staleObservedAt: Date?
    let unavailableSince: Date?

    init(_ window: UsageWindow) {
        switch window.kind {
        case .fiveHour:
            self.kind = .fiveHour
            self.otherLabel = nil
            self.billingPeriodDuration = nil
        case .weekly:
            self.kind = .weekly
            self.otherLabel = nil
            self.billingPeriodDuration = nil
        case .billingPeriod(let label, let duration):
            self.kind = .billingPeriod
            self.otherLabel = label
            self.billingPeriodDuration = duration
        case .other(let label):
            self.kind = .other
            self.otherLabel = label
            self.billingPeriodDuration = nil
        }
        self.utilization = window.utilization
        self.resetsAt = window.resetsAt
        self.resetLabel = window.resetLabel
        switch window.freshness {
        case .live:
            self.staleObservedAt = nil
            self.unavailableSince = nil
        case .stale(let observedAt):
            self.staleObservedAt = observedAt
            self.unavailableSince = nil
        case .unavailable(let since):
            self.staleObservedAt = nil
            self.unavailableSince = since
        }
    }

    var usageWindow: UsageWindow? {
        guard utilization.isFinite else { return nil }
        let restoredKind: WindowKind
        switch kind {
        case .fiveHour:
            restoredKind = .fiveHour
        case .weekly:
            restoredKind = .weekly
        case .billingPeriod:
            guard let otherLabel, !otherLabel.isEmpty,
                  let billingPeriodDuration,
                  billingPeriodDuration.isFinite,
                  billingPeriodDuration > 0
            else { return nil }
            restoredKind = .billingPeriod(label: otherLabel, duration: billingPeriodDuration)
        case .other:
            guard let otherLabel, !otherLabel.isEmpty else { return nil }
            restoredKind = .other(otherLabel)
        }
        return UsageWindow(
            kind: restoredKind,
            utilization: utilization,
            resetsAt: resetsAt,
            resetLabel: resetLabel,
            freshness: unavailableSince.map(UsageWindowFreshness.unavailable(since:))
                ?? staleObservedAt.map(UsageWindowFreshness.stale(observedAt:))
                ?? .live
        )
    }
}

/// Pure freshness and expiry policy shared by launch restoration and live merges.
/// Keeping the state machine here prevents provider-specific continuity rules from
/// spreading through the observable store.
enum UsageContinuityPolicy {
    static func restoredSnapshot(
        _ cached: UsageSnapshot?,
        for providerID: ProviderID,
        at restorationDate: Date
    ) -> UsageSnapshot {
        guard let cached, cached.providerID == providerID else {
            return .pending(for: providerID)
        }
        let windows = cached.windows.compactMap {
            restoredWindow(
                $0,
                providerID: providerID,
                capturedAt: cached.capturedAt,
                at: restorationDate
            )
        }
        guard !windows.isEmpty else { return .pending(for: providerID) }
        return UsageSnapshot(
            providerID: providerID,
            windows: windows,
            planLabel: cached.planLabel,
            accountEmail: cached.accountEmail,
            capturedAt: cached.capturedAt,
            freshness: .stale(.transient("Last known usage — refreshing"))
        )
    }

    static func mergedSnapshot(
        _ fresh: UsageSnapshot,
        with prior: UsageSnapshot?,
        at mergeDate: Date
    ) -> UsageSnapshot {
        if case .stale(let reason) = fresh.freshness,
           fresh.windows.isEmpty,
           let prior,
           !prior.windows.isEmpty {
            return snapshotByRetainingValidWindows(prior, reason: reason, at: mergeDate)
        }
        guard fresh.providerID == .claude,
              fresh.freshness == .live,
              let prior
        else {
            return fresh
        }
        return preservingClaudeWeeklySubLimits(in: fresh, from: prior)
    }

    private static func snapshotByRetainingValidWindows(
        _ prior: UsageSnapshot,
        reason: FailureReason,
        at mergeDate: Date
    ) -> UsageSnapshot {
        let windows = prior.windows.compactMap { window -> UsageWindow? in
            if isClaudeWeeklySubLimit(window, providerID: prior.providerID) || window.kind.isBillingPeriod {
                return restoredWindow(
                    window,
                    providerID: prior.providerID,
                    capturedAt: prior.capturedAt,
                    at: mergeDate
                )
            }
            guard let observedAt = window.freshness.observedAt ?? prior.capturedAt else {
                return nil
            }
            return window.withFreshness(.stale(observedAt: observedAt))
        }
        return UsageSnapshot(
            providerID: prior.providerID,
            windows: windows,
            planLabel: prior.planLabel,
            accountEmail: prior.accountEmail,
            capturedAt: prior.capturedAt,
            freshness: .stale(reason)
        )
    }

    /// Claude uses `capturedAt` as a reset sentinel when a repaint omits the reset line.
    /// The sentinel gets one window-kind lifetime; a real reset timestamp expires as-is.
    private static func continuityExpiryDate(
        for window: UsageWindow,
        providerID: ProviderID,
        capturedAt: Date
    ) -> Date {
        guard providerID == .claude,
              abs(window.resetsAt.timeIntervalSince(capturedAt)) < 1
        else {
            return window.resetsAt
        }
        return window.resetsAt.addingTimeInterval(fallbackLifetime(for: window.kind))
    }

    private static func restoredWindow(
        _ window: UsageWindow,
        providerID: ProviderID,
        capturedAt: Date?,
        at restorationDate: Date
    ) -> UsageWindow? {
        if case .unavailable(let since) = window.freshness {
            return restorationDate.timeIntervalSince(since) < fallbackLifetime(for: window.kind)
                ? window
                : nil
        }

        guard let observedAt = window.freshness.observedAt ?? capturedAt else {
            return nil
        }
        let expiredAt = continuityExpiryDate(
            for: window,
            providerID: providerID,
            capturedAt: observedAt
        )
        if expiredAt > restorationDate {
            return window.withFreshness(.stale(observedAt: observedAt))
        }
        guard (isClaudeWeeklySubLimit(window, providerID: providerID) || window.kind.isBillingPeriod),
              restorationDate.timeIntervalSince(expiredAt) < fallbackLifetime(for: window.kind)
        else {
            return nil
        }
        return window.withFreshness(.unavailable(since: expiredAt))
    }

    /// Claude's primary limits remain fresh while a separately rate-limited model
    /// breakdown is retained as last-known. Once invalid, the old percentage is hidden
    /// behind an unavailable row for one bounded lifetime before the row disappears.
    private static func preservingClaudeWeeklySubLimits(
        in fresh: UsageSnapshot,
        from prior: UsageSnapshot
    ) -> UsageSnapshot {
        guard fresh.windows.contains(where: { $0.kind == .weekly }),
              let capturedAt = fresh.capturedAt
        else {
            return fresh
        }
        let freshKinds = Set(fresh.windows.map(\.kind))
        let retained = prior.windows.compactMap { window -> UsageWindow? in
            guard isClaudeWeeklySubLimit(window, providerID: fresh.providerID),
                  !freshKinds.contains(window.kind)
            else {
                return nil
            }
            if case .unavailable(let since) = window.freshness {
                return capturedAt.timeIntervalSince(since) < fallbackLifetime(for: window.kind)
                    ? window
                    : nil
            }
            guard let observedAt = window.freshness.observedAt ?? prior.capturedAt else {
                return nil
            }
            let expiredAt = continuityExpiryDate(
                for: window,
                providerID: fresh.providerID,
                capturedAt: observedAt
            )
            if expiredAt > capturedAt {
                return window.withFreshness(.stale(observedAt: observedAt))
            }
            return capturedAt.timeIntervalSince(expiredAt) < fallbackLifetime(for: window.kind)
                ? window.withFreshness(.unavailable(since: expiredAt))
                : nil
        }
        guard !retained.isEmpty else { return fresh }
        return UsageSnapshot(
            providerID: fresh.providerID,
            windows: fresh.windows + retained,
            planLabel: fresh.planLabel,
            accountEmail: fresh.accountEmail,
            capturedAt: fresh.capturedAt,
            freshness: .live
        )
    }

    private static func isClaudeWeeklySubLimit(
        _ window: UsageWindow,
        providerID: ProviderID
    ) -> Bool {
        guard providerID == .claude,
              case .other(let label) = window.kind
        else {
            return false
        }
        return label.localizedCaseInsensitiveContains("weekly")
    }

    private static func fallbackLifetime(for kind: WindowKind) -> TimeInterval {
        switch kind {
        case .fiveHour:
            return 5 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        case .billingPeriod(_, let duration):
            return duration.isFinite && duration > 0
                ? max(24 * 60 * 60, duration)
                : 24 * 60 * 60
        case .other(let label):
            return label.localizedCaseInsensitiveContains("weekly")
                ? 7 * 24 * 60 * 60
                : 24 * 60 * 60
        }
    }
}

private extension WindowKind {
    var isBillingPeriod: Bool {
        if case .billingPeriod = self { return true }
        return false
    }
}
