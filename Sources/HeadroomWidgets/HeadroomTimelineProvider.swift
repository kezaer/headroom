import Foundation
import HeadroomCore
import WidgetKit

struct HeadroomTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(date: .now, state: .pending)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadroomWidgetEntry) -> Void) {
        completion(entry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomWidgetEntry>) -> Void) {
        let now = Date.now
        completion(Timeline(entries: [entry(date: now)], policy: .after(now.addingTimeInterval(5 * 60))))
    }

    private func entry(date: Date) -> HeadroomWidgetEntry {
        HeadroomWidgetEntry(date: date, state: .from(WidgetSnapshotCache.appGroup().read()))
    }
}
