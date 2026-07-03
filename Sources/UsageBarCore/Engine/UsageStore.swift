import Foundation
import Observation

/// Compact, self-contained menu bar summary (R5): the tightest live window plus its
/// provider identity, so the bar means something without opening the popover.
public struct MenuBarSummary: Sendable, Equatable {
    public let text: String            // e.g. "12%"
    public let providerID: ProviderID? // which provider the number is about
    public let detail: String?         // e.g. "Claude 5h"
    public let isNeutral: Bool         // true when no live data yet

    public static let neutral = MenuBarSummary(text: "—", providerID: nil, detail: nil, isNeutral: true)
}

/// The observable view model the UI and menu bar label bind to (U6). `@MainActor`
/// and `@Observable`: snapshots are published on the main actor; providers are
/// fetched concurrently off-main (KTD10). Per-provider isolation — one provider's
/// failure updates only its own snapshot (KTD7).
@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshots: [ProviderID: UsageSnapshot]
    public private(set) var showMenuBarPercentage: Bool
    public let providerOrder: [ProviderID]
    public let displayNames: [ProviderID: String]

    private let providers: [any UsageProvider]
    private let preferences: Preferences
    private var engine: PollingEngine?
    private var isRefreshing = false

    public init(providers: [any UsageProvider], preferences: Preferences = Preferences()) {
        self.providers = providers
        self.preferences = preferences
        self.providerOrder = providers.map(\.id)
        self.displayNames = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0.displayName) })
        self.snapshots = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, .pending(for: $0.id)) })
        self.showMenuBarPercentage = preferences.showMenuBarPercentage
    }

    /// Begin polling: an immediate refresh, then the interval loop. Idempotent — a
    /// second call (e.g. the popover re-appearing) does not restart the loop or
    /// reset the cadence.
    public func start() async {
        guard engine == nil else { return }
        await refreshAll()
        let engine = PollingEngine(
            intervalMinutes: { [preferences] in preferences.pollIntervalMinutes },
            tick: { [weak self] in await self?.refreshAll() }
        )
        engine.start()
        self.engine = engine
    }

    /// Immediate off-cadence refresh — called on popover open (KTD9).
    public func refreshNow() {
        Task { await refreshAll() }
    }

    /// Restart the loop so a changed poll interval takes effect now (R14).
    public func reschedulePolling() { engine?.reschedule() }

    public func setShowMenuBarPercentage(_ enabled: Bool) {
        preferences.showMenuBarPercentage = enabled
        showMenuBarPercentage = enabled
    }

    /// Fetch every provider concurrently and merge results with continuity. Guarded
    /// so overlapping triggers (a timer tick during a popover-open `refreshNow()`)
    /// coalesce into one in-flight cycle instead of racing duplicate fetches.
    public func refreshAll() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let results = await withTaskGroup(of: (ProviderID, UsageSnapshot).self) { group in
            for provider in providers {
                group.addTask { (provider.id, await provider.fetchSnapshot()) }
            }
            var acc: [(ProviderID, UsageSnapshot)] = []
            for await pair in group { acc.append(pair) }
            return acc
        }
        for (id, fresh) in results { merge(id: id, fresh: fresh) }
    }

    /// Continuity (KTD7): a failure with no fresh windows keeps the prior windows
    /// shown dimmed rather than blanking the card; it never touches another provider.
    private func merge(id: ProviderID, fresh: UsageSnapshot) {
        let next: UsageSnapshot
        if case .stale(let reason) = fresh.freshness,
           fresh.windows.isEmpty,
           let prior = snapshots[id], !prior.windows.isEmpty {
            next = prior.markedStale(reason)
        } else {
            next = fresh
        }
        // Skip the assignment when nothing changed so an unchanging state (e.g. a
        // provider that stays logged-out) doesn't invalidate observers every cycle.
        if snapshots[id] != next { snapshots[id] = next }
    }

    public func snapshot(for id: ProviderID) -> UsageSnapshot {
        snapshots[id] ?? .pending(for: id)
    }

    /// The menu bar summary: the lowest `percentRemaining` among all live windows,
    /// tagged with its provider+window identity. Neutral until any live data exists.
    public var menuBarSummary: MenuBarSummary {
        var best: (id: ProviderID, window: UsageWindow)?
        for id in providerOrder {
            guard let snap = snapshots[id], snap.freshness == .live else { continue }
            for window in snap.windows {
                if best == nil || window.percentRemaining < best!.window.percentRemaining {
                    best = (id, window)
                }
            }
        }
        guard let best else { return .neutral }
        let pct = Int(best.window.percentRemaining.rounded())
        let name = displayNames[best.id] ?? best.id.raw
        return MenuBarSummary(
            text: "\(pct)%",
            providerID: best.id,
            detail: "\(name) \(best.window.kind.shortLabel)",
            isNeutral: false
        )
    }
}
