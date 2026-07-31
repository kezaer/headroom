import Foundation

/// Converts the app's richer provider snapshots into the small, safe contract consumed
/// by WidgetKit. Keeping this in core makes widget rendering deterministic and testable.
public enum WidgetSnapshotProjector {
    public static func project(
        snapshots: [ProviderID: UsageSnapshot],
        providerOrder: [ProviderID],
        displayNames: [ProviderID: String],
        renewalDate: (ProviderID) -> Date?,
        widgetsEnabled: Bool,
        showsCodexSparkCounters: Bool = false,
        apiSpendSnapshots: [ProviderID: APISpendSnapshot] = [:],
        apiSpendProviderOrder: [ProviderID] = [],
        generatedAt: Date = .now
    ) -> WidgetSnapshotEnvelope {
        guard widgetsEnabled else { return .disabled(generatedAt: generatedAt) }
        let providers = providerOrder.map { id in
            providerSummary(
                id: id,
                snapshot: snapshots[id] ?? .pending(for: id),
                displayName: displayNames[id] ?? id.raw,
                renewalDate: renewalDate(id),
                showsCodexSparkCounters: showsCodexSparkCounters
            )
        }
        let apiSpendProviders = apiSpendProviderOrder.compactMap { id in
            apiSpendSnapshots[id].map(apiSpendSummary)
        }
        return WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: providers,
            apiSpendProviders: apiSpendProviders
        )
    }

    private static func providerSummary(
        id: ProviderID,
        snapshot: UsageSnapshot,
        displayName: String,
        renewalDate: Date?,
        showsCodexSparkCounters: Bool
    ) -> WidgetProviderSummary {
        WidgetProviderSummary(
            id: id.raw,
            displayName: displayName,
            planLabel: snapshot.planLabel,
            freshness: freshness(snapshot.freshness),
            windows: snapshot.windows.compactMap { windowSummary($0, providerID: id, showsCodexSparkCounters: showsCodexSparkCounters) },
            renewalDate: renewalDate
        )
    }

    private static func freshness(_ freshness: Freshness) -> WidgetProviderFreshness {
        switch freshness {
        case .pending:
            .pending
        case .live:
            .live
        case .stale(let reason):
            .stale(message: reason.message, needsAttention: reason.isPermanent)
        }
    }

    private static func apiSpendSummary(_ snapshot: APISpendSnapshot) -> WidgetAPISpendSummary {
        WidgetAPISpendSummary(
            id: snapshot.providerID.raw,
            displayName: snapshot.displayName,
            amount: snapshot.amount,
            currency: snapshot.currency,
            periodLabel: snapshot.periodLabel,
            capturedAt: snapshot.capturedAt,
            freshness: freshness(snapshot.freshness)
        )
    }

    private static func windowSummary(
        _ window: UsageWindow,
        providerID: ProviderID,
        showsCodexSparkCounters: Bool
    ) -> WidgetWindowSummary? {
        guard let kind = widgetKind(window.kind, providerID: providerID, showsCodexSparkCounters: showsCodexSparkCounters) else { return nil }
        return WidgetWindowSummary(
            kind: kind,
            label: window.kind.shortLabel,
            percentRemaining: window.percentRemaining,
            resetsAt: window.resetsAt,
            resetLabel: window.resetLabel,
            severity: widgetSeverity(window.severity),
            freshness: widgetFreshness(window.freshness)
        )
    }

    private static func widgetFreshness(_ freshness: UsageWindowFreshness) -> WidgetWindowFreshness {
        switch freshness {
        case .live:
            .live
        case .stale(let observedAt):
            .stale(observedAt: observedAt)
        case .unavailable(let since):
            .unavailable(since: since)
        }
    }

    private static func widgetKind(
        _ kind: WindowKind,
        providerID: ProviderID,
        showsCodexSparkCounters: Bool
    ) -> WidgetWindowKind? {
        switch kind {
        case .fiveHour:
            return .fiveHour
        case .weekly:
            return .weekly
        case .billingPeriod(let label, _):
            return .other(label)
        case .other(let label):
            if providerID == .codex {
                return (showsCodexSparkCounters && kind.isCodexSparkCounter) ? .other(label) : nil
            }
            // Claude reports model-specific weekly sub-limits (e.g. "Weekly (Fable)") as
            // extra `.other` windows. Retain them so a more restrictive sub-limit can
            // appear as compact context in the large-widget header.
            if providerID == .claude {
                return label.localizedCaseInsensitiveContains("weekly") ? .other(label) : nil
            }
            return .other(label)
        }
    }

    private static func widgetSeverity(_ severity: UsageSeverity) -> WidgetUsageSeverity {
        switch severity {
        case .healthy: .healthy
        case .low: .low
        case .critical: .critical
        }
    }
}
