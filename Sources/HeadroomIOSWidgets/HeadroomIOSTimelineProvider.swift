import Foundation
import WidgetKit

struct HeadroomIOSTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(date: .now, state: .waitingForMac)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadroomIOSWidgetEntry) -> Void) {
        completion(entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomIOSWidgetEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: [entry(date: now)], policy: .after(now.addingTimeInterval(5 * 60))))
    }

    private func entry(date: Date) -> HeadroomIOSWidgetEntry {
        let cache = WidgetSnapshotCache.appGroup()
        let sync = iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore())
        let syncRead = sync.read()
        if case .snapshot(let envelope) = syncRead {
            try? cache.write(envelope.snapshot)
        }
        return HeadroomIOSWidgetEntry(
            date: date,
            state: .from(cacheRead: cache.read(), syncRead: syncRead)
        )
    }
}
