import Foundation
import Testing
@testable import HeadroomCore

struct IOSWidgetTimelineMappingTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func liveCacheMapsToContent() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot)) == .content(snapshot))
    }

    @Test func demoWinsBeforeCacheAndSyncWithoutMutatingEitherSource() {
        let demo = DemoScreenshotData.envelope
        let cache = WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(7_200), status: .enabled, providers: [])
        let remote = WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(14_400), status: .enabled, providers: [])

        let resolution = IOSWidgetSnapshotState.resolve(
            demoEnvelope: demo,
            cacheRead: .snapshot(cache),
            syncRead: .snapshot(synced(remote))
        )

        #expect(resolution.state == .demo(demo))
        #expect(resolution.origin == .demo)
        #expect(cache.generatedAt != demo.generatedAt)
        #expect(remote.generatedAt != demo.generatedAt)
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
        #expect(IOSWidgetSnapshotState.from(cacheRead: .incompatibleSchema) == .incompatibleSchema)
        #expect(IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: .incompatibleSchema) == .incompatibleSchema)
    }

    @Test func incompatibleLocalSchemaDoesNotFallBackToSyncedContent() {
        let remote = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        #expect(
            IOSWidgetSnapshotState.from(
                cacheRead: .incompatibleSchema,
                syncRead: .snapshot(synced(remote))
            ) == .incompatibleSchema
        )
    }

    @Test func equalGeneratedAtKeepsLocalCache() {
        let cache = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let remote = WidgetSnapshotEnvelope.disabled(generatedAt: now)

        let resolution = IOSWidgetSnapshotState.resolve(
            cacheRead: .snapshot(cache),
            syncRead: .snapshot(synced(remote))
        )

        #expect(resolution.state == .content(cache))
        #expect(resolution.origin == .cache)
    }

    @Test func newerRemoteSnapshotWinsOverStaleCache() {
        let stale = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let fresh = WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(3_600), status: .enabled, providers: [])

        let resolution = IOSWidgetSnapshotState.resolve(
            cacheRead: .snapshot(stale),
            syncRead: .snapshot(synced(fresh))
        )
        #expect(resolution.state == .content(fresh))
        #expect(resolution.origin == .sync)
    }

    @Test func newerCacheWinsOverStaleRemote() {
        let fresh = WidgetSnapshotEnvelope(generatedAt: now.addingTimeInterval(3_600), status: .enabled, providers: [])
        let stale = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        let resolution = IOSWidgetSnapshotState.resolve(
            cacheRead: .snapshot(fresh),
            syncRead: .snapshot(synced(stale))
        )
        #expect(resolution.state == .content(fresh))
        #expect(resolution.origin == .cache)
    }

    @Test func liveCacheSurvivesMissingOrCorruptSync() {
        let snapshot = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot), syncRead: .missing) == .content(snapshot))
        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(snapshot), syncRead: .corrupt) == .content(snapshot))
    }

    @Test func newerRemoteDisabledSnapshotPausesOverStaleContent() {
        let stale = WidgetSnapshotEnvelope(generatedAt: now, status: .enabled, providers: [])
        let disabled = WidgetSnapshotEnvelope.disabled(generatedAt: now.addingTimeInterval(3_600))

        #expect(IOSWidgetSnapshotState.from(cacheRead: .snapshot(stale), syncRead: .snapshot(synced(disabled))) == .disabled)
    }

    @Test func syncedPeriodWindowPreservesSemanticAndFreshness() throws {
        let observedAt = now.addingTimeInterval(-60)
        let source = WidgetSnapshotProjector.project(
            snapshots: [.grok: .live(.grok, windows: [
                UsageWindow(
                    kind: .billingPeriod(label: "Monthly", duration: 30 * 24 * 60 * 60),
                    utilization: 40,
                    resetsAt: now.addingTimeInterval(20 * 24 * 60 * 60),
                    freshness: .stale(observedAt: observedAt)
                ),
            ])],
            providerOrder: [.grok],
            displayNames: [.grok: "Grok"],
            renewalDate: { _ in nil },
            widgetsEnabled: true,
            generatedAt: now
        )
        let decoded = SyncedWidgetSnapshotCodec.decode(
            try SyncedWidgetSnapshotCodec.encode(synced(source))
        )
        let syncRead: iCloudSnapshotSyncRead
        switch decoded {
        case .snapshot(let envelope): syncRead = .snapshot(envelope)
        case .missing: syncRead = .missing
        case .corrupt: syncRead = .corrupt
        case .incompatibleSchema: syncRead = .incompatibleSchema
        }
        let state = IOSWidgetSnapshotState.from(cacheRead: .empty, syncRead: syncRead)
        guard case .content(let envelope) = state else {
            Issue.record("expected synced widget content")
            return
        }

        let window = try #require(envelope.providers.first?.primarySubscriptionWindow)
        #expect(window.label == "Monthly")
        #expect(window.displayPercentRemaining == 60)
        #expect(window.isBillingPeriod)
        #expect(window.freshness == .stale(observedAt: observedAt))
    }

    private func synced(_ snapshot: WidgetSnapshotEnvelope) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            publishedAt: now,
            sourceID: "mac",
            sourcePlatform: .macOS,
            snapshot: snapshot
        )
    }
}
