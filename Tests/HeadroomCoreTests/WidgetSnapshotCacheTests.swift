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

    private func freshFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-widget-cache-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }

    private func siblingFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-widget-cache-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Widget Container", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
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

    @Test func fileEnvelopeRoundTripsWithoutDefaults() throws {
        let cache = WidgetSnapshotCache(defaults: nil, fileURL: freshFileURL())
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        try cache.write(envelope)

        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func writeMirrorsEnvelopeToFallbackFiles() throws {
        let primary = freshFileURL()
        let fallback = siblingFileURL()
        let cache = WidgetSnapshotCache(defaults: nil, fileURL: primary, fallbackFileURLs: [fallback])
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        try cache.write(envelope)

        #expect(FileManager.default.fileExists(atPath: primary.path))
        #expect(FileManager.default.fileExists(atPath: fallback.path))
        try FileManager.default.removeItem(at: primary)
        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func fallbackFileRoundTripsWithoutPrimaryFile() throws {
        let fallback = siblingFileURL()
        let cache = WidgetSnapshotCache(defaults: nil, fileURL: nil, fallbackFileURLs: [fallback])
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        try cache.write(envelope)

        #expect(FileManager.default.fileExists(atPath: fallback.path))
        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func fileWriteFailureThrowsAndDoesNotReloadWidgets() throws {
        let regularFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("headroom-widget-cache-tests-\(UUID().uuidString)")
        try Data("not-a-directory".utf8).write(to: regularFile)
        let unwritableURL = regularFile.appendingPathComponent("widget-snapshot.json")
        let cache = WidgetSnapshotCache(defaults: nil, fileURL: unwritableURL)
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        #expect(throws: WidgetSnapshotCacheError.writeFailed) {
            try cache.write(envelope)
        }

        let spy = ReloadSpy()
        WidgetSnapshotExporter(cache: cache, reloadTimelines: spy.reload).export(envelope)
        #expect(spy.count == 0)
    }

    @Test func corruptPrimaryFileFallsBackToSecondaryFile() throws {
        let primary = freshFileURL()
        let fallback = siblingFileURL()
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))
        try FileManager.default.createDirectory(at: primary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallback.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: primary)
        try JSONEncoder().encode(envelope).write(to: fallback)

        let cache = WidgetSnapshotCache(defaults: nil, fileURL: primary, fallbackFileURLs: [fallback])

        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func fileCacheFallsBackToDefaultsWhenFileIsMissing() throws {
        let defaults = freshDefaults()
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))
        try WidgetSnapshotCache(defaults: defaults).write(envelope)

        let cache = WidgetSnapshotCache(defaults: defaults, fileURL: freshFileURL())

        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func fileCachePrefersFileOverDefaults() throws {
        let defaults = freshDefaults()
        let fileURL = freshFileURL()
        let defaultsEnvelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))
        let fileEnvelope = WidgetSnapshotEnvelope(
            generatedAt: Date(timeIntervalSince1970: 2_000),
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "codex",
                    displayName: "Codex",
                    planLabel: nil,
                    freshness: .live,
                    windows: [],
                    renewalDate: nil
                ),
            ]
        )
        defaults.set(try JSONEncoder().encode(defaultsEnvelope), forKey: "widgetSnapshotEnvelope")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(fileEnvelope).write(to: fileURL)

        let cache = WidgetSnapshotCache(defaults: defaults, fileURL: fileURL)

        #expect(cache.read() == .snapshot(fileEnvelope))
    }

    @Test func corruptFileFallsBackToDefaults() throws {
        let defaults = freshDefaults()
        let fileURL = freshFileURL()
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))
        try WidgetSnapshotCache(defaults: defaults).write(envelope)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        let cache = WidgetSnapshotCache(defaults: defaults, fileURL: fileURL)

        #expect(cache.read() == .snapshot(envelope))
    }

    @Test func corruptFileWithEmptyDefaultsReportsCorrupt() throws {
        let fileURL = freshFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        let cache = WidgetSnapshotCache(defaults: freshDefaults(), fileURL: fileURL)

        #expect(cache.read() == .corrupt)
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

    @Test func exporterReloadsUnchangedSnapshot() {
        let cache = WidgetSnapshotCache(defaults: freshDefaults())
        let spy = ReloadSpy()
        let exporter = WidgetSnapshotExporter(cache: cache, reloadTimelines: spy.reload)
        let envelope = WidgetSnapshotEnvelope.disabled(generatedAt: Date(timeIntervalSince1970: 1_000))

        exporter.export(envelope)
        exporter.export(envelope)

        #expect(spy.count == 2)
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
