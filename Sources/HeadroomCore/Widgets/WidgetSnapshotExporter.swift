import Foundation

public protocol WidgetSnapshotExporting: Sendable {
    func export(_ envelope: WidgetSnapshotEnvelope)
}

/// Writes widget data and asks the host app to reload WidgetKit timelines after a
/// successful cache write. The reload closure keeps WidgetKit out of HeadroomCore.
public struct WidgetSnapshotExporter: WidgetSnapshotExporting {
    private let cache: WidgetSnapshotCache
    private let reloadTimelines: @Sendable () -> Void

    public init(cache: WidgetSnapshotCache = .appGroup(), reloadTimelines: @escaping @Sendable () -> Void) {
        self.cache = cache
        self.reloadTimelines = reloadTimelines
    }

    public func export(_ envelope: WidgetSnapshotEnvelope) {
        do {
            try cache.write(envelope)
            reloadTimelines()
        } catch {
            // Widgets surface the app-group setup state when they read; export failure
            // must never interrupt the menu bar refresh path.
        }
    }
}
