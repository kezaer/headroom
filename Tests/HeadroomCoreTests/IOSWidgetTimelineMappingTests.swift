import Foundation
import Testing
@testable import HeadroomCore

struct IOSWidgetTimelineMappingTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func liveCacheMapsToContent() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot)) == .content(snapshot))
    }

    @Test func disabledCacheMapsToDisabled() {
        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(.disabled(generatedAt: now))) == .disabled)
    }

    @Test func emptyCacheFallsBackToRemoteSnapshot() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let synced = SyncedWidgetSnapshotEnvelope(
            publishedAt: now,
            sourceID: "mac",
            sourcePlatform: .macOS,
            snapshot: snapshot
        )

        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .snapshot(synced)) == .content(snapshot))
    }

    @Test func noLocalOrRemoteSnapshotWaitsForMac() {
        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .missing) == .waitingForMac)
    }

    @Test func corruptAndIncompatibleStatesAreTyped() {
        #expect(IOSWidgetSnapshotState.from(cacheRead: .corrupt) == .corrupt)
        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .incompatibleSchema) == .incompatibleSchema)
    }
}
