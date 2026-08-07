import Foundation
import WidgetKit

struct HeadroomIOSTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(date: .now, state: .demo(DemoScreenshotData.envelope))
    }

    func getSnapshot(in context: Context, completion: @escaping (HeadroomIOSWidgetEntry) -> Void) {
        if context.isPreview {
            completion(HeadroomIOSWidgetEntry(date: .now, state: .demo(DemoScreenshotData.envelope)))
        } else {
            completion(entry(date: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeadroomIOSWidgetEntry>) -> Void) {
        let now = Date.now
        let state = resolvedState()
        let envelope: WidgetSnapshotEnvelope?
        switch state {
        case .demo(let content), .content(let content): envelope = content
        default: envelope = nil
        }
        let entries = WidgetTimelineSchedule.entryDates(for: envelope, now: now).map { date in
            HeadroomIOSWidgetEntry(date: date, state: state)
        }
        completion(Timeline(entries: entries, policy: .after(WidgetTimelineSchedule.refreshDate(after: now))))
    }

    private func entry(date: Date) -> HeadroomIOSWidgetEntry {
        HeadroomIOSWidgetEntry(date: date, state: resolvedState())
    }

    private func resolvedState() -> IOSWidgetSnapshotState {
        if CompanionDemoModeStore.appGroup().isEnabled {
            return .demo(DemoScreenshotData.envelope)
        }
        let cache = WidgetSnapshotCache.appGroup()
        let sync = iCloudSnapshotSync(store: UbiquitousKeyValueSyncStore())
        let syncRead = sync.read()
        let cacheRead = cache.read()
        // Adopt the remote snapshot only when it's newer than (or absent from) the cache, so
        // an older iCloud payload never overwrites fresher cached content. Resolution below is
        // newest-wins regardless, but this keeps the on-disk cache honest for the next read.
        if case .snapshot(let envelope) = syncRead,
           adoptable(remote: envelope.snapshot, into: cacheRead) {
            try? cache.write(envelope.snapshot)
        }
        return .from(cacheRead: cacheRead, syncRead: syncRead)
    }

    private func adoptable(remote: WidgetSnapshotEnvelope, into cacheRead: WidgetSnapshotCacheRead) -> Bool {
        guard let cached = cacheRead.envelope else { return true }
        return remote.generatedAt > cached.generatedAt
    }
}
