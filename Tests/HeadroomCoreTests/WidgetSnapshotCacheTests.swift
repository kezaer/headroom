import Testing
import Foundation
@testable import HeadroomCore

struct WidgetSnapshotCacheTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "headroom.widget-cache.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func liveEnvelopeRoundTrips() throws {
        let cache = WidgetSnapshotCache(defaults: freshDefaults())
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "claude",
                    displayName: "Claude",
                    planLabel: nil,
                    freshness: .live,
                    windows: [],
                    renewalDate: nil
                ),
            ]
        )

        try cache.write(envelope)
        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func disabledEnvelopeRoundTrips() throws {
        let cache = WidgetSnapshotCache(defaults: freshDefaults())
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        try cache.write(envelope)
        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func emptyCorruptAndUnavailableAreTypedStates() {
        let defaults = freshDefaults()
        let cache = WidgetSnapshotCache(defaults: defaults)
        #expect(cache.read() == .empty)

        defaults.set(Data("not-json".utf8), forKey: "widgetSnapshotEnvelope")
        #expect(cache.read() == .corrupt)

        #expect(WidgetSnapshotCache(defaults: nil).read() == .unavailable)
    }

    @Test func writeFailsWhenUnavailable() {
        let cache = WidgetSnapshotCache(defaults: nil)
        #expect(throws: WidgetSnapshotCacheError.unavailable) {
            try cache.write(.disabled(generatedAt: Date(timeIntervalSince1970: 1_000)))
        }
    }

    @Test func exporterReloadsAfterSuccessfulWrite() {
        let defaults = freshDefaults()
        let cache = WidgetSnapshotCache(defaults: defaults)
        let spy = ReloadSpy()
        let exporter = WidgetSnapshotExporter(cache: cache, reloadTimelines: spy.reload)

        exporter.export(.disabled(generatedAt: Date(timeIntervalSince1970: 1_000)))

        #expect(spy.count == 1)
        #expect(cache.read().envelope?.status == .disabled)
    }

    @Test func exporterDoesNotReloadWhenWriteFails() {
        let spy = ReloadSpy()
        let exporter = WidgetSnapshotExporter(cache: WidgetSnapshotCache(defaults: nil), reloadTimelines: spy.reload)

        exporter.export(.disabled(generatedAt: Date(timeIntervalSince1970: 1_000)))

        #expect(spy.count == 0)
    }

    @Test func exporterSkipsUnchangedSnapshot() {
        let cache = WidgetSnapshotCache(defaults: freshDefaults())
        let spy = ReloadSpy()
        let exporter = WidgetSnapshotExporter(cache: cache, reloadTimelines: spy.reload)
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        exporter.export(envelope)
        exporter.export(envelope)

        #expect(spy.count == 1)
    }
}

private final class ReloadSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }

    func reload() {
        lock.withLock { _count += 1 }
    }
}
