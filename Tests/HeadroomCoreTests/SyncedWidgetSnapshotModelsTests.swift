import Foundation
import Testing
@testable import HeadroomCore

struct SyncedWidgetSnapshotModelsTests {
    private let generatedAt = Date(timeIntervalSince1970: 2_000)
    private let publishedAt = Date(timeIntervalSince1970: 2_100)
    private let reset = Date(timeIntervalSince1970: 3_000)

    @Test func liveSnapshotRoundTrips() throws {
        let envelope = makeSyncedEnvelope(snapshot: liveSnapshot)

        let decoded = SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))

        #expect(decoded == .snapshot(envelope))
    }

    @Test func currentSnapshotSchemaRejectsFreshnessBlindClientsButAcceptsLegacyPayloads() throws {
        #expect(WidgetSnapshotEnvelope.schemaVersion == 3)
        #expect(SyncedWidgetSnapshotEnvelope.schemaVersion == 1)

        let legacySnapshot = WidgetSnapshotEnvelope(
            schemaVersion: 1,
            generatedAt: generatedAt,
            status: .enabled,
            providers: liveSnapshot.providers
        )
        let envelope = makeSyncedEnvelope(snapshot: legacySnapshot)

        let decoded = SyncedWidgetSnapshotCodec.decode(
            try SyncedWidgetSnapshotCodec.encode(envelope)
        )

        #expect(decoded == .snapshot(envelope))
    }

    @Test func futureSnapshotSchemaIsIncompatible() throws {
        let futureSnapshot = WidgetSnapshotEnvelope(
            schemaVersion: WidgetSnapshotEnvelope.schemaVersion + 1,
            generatedAt: generatedAt,
            status: .enabled,
            providers: []
        )
        let envelope = makeSyncedEnvelope(snapshot: futureSnapshot)

        #expect(
            SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))
                == .incompatibleSchema
        )
    }

    @Test func windowEncodingKeepsLegacyIDAndMissingFreshnessDefaultsToLive() throws {
        let window = liveSnapshot.providers[0].windows[0]
        let encoded = try JSONEncoder().encode(window)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(object["id"] as? String == window.id)
        object.removeValue(forKey: "freshness")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WidgetWindowSummary.self, from: legacyData)

        #expect(decoded.id == window.id)
        #expect(decoded.freshness == .live)
    }

    @Test func billingPeriodUsesAdditiveV2Discriminator() throws {
        #expect(WidgetSnapshotEnvelope.schemaVersion == 3)
        let window = WidgetWindowSummary(
            kind: .other("Monthly"),
            label: "Monthly",
            percentRemaining: 64,
            resetsAt: reset,
            resetLabel: nil,
            severity: .healthy,
            freshness: .stale(observedAt: generatedAt),
            billingPeriodDuration: 30 * 24 * 60 * 60
        )

        let encoded = try JSONEncoder().encode(window)
        let decoded = try JSONDecoder().decode(WidgetWindowSummary.self, from: encoded)
        #expect(decoded.isBillingPeriod)
        #expect(decoded.isSubscriptionWindow)
        #expect(decoded.freshness == .stale(observedAt: generatedAt))

        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "billingPeriodDuration")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(WidgetWindowSummary.self, from: legacyData)
        #expect(legacy.kind == .other("Monthly"))
        #expect(!legacy.isBillingPeriod)
        #expect(!legacy.isSubscriptionWindow)
        #expect(legacy.freshness == .stale(observedAt: generatedAt))
    }

    @Test func unsupportedInnerSchemaWinsOverMalformedPayload() {
        let payload = """
        {
          "schemaVersion": 1,
          "publishedAt": 2100,
          "sourceID": "test-mac",
          "sourcePlatform": "macOS",
          "snapshot": {
            "schemaVersion": 999,
            "generatedAt": "malformed-on-purpose",
            "status": {"not": "valid"},
            "providers": "not-an-array"
          }
        }
        """

        #expect(SyncedWidgetSnapshotCodec.decode(Data(payload.utf8)) == .incompatibleSchema)
    }

    @Test func liveSnapshotWithAPISpendRoundTrips() throws {
        let envelope = makeSyncedEnvelope(snapshot: liveSnapshotWithAPISpend)

        let decoded = SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))

        #expect(decoded == .snapshot(envelope))
        #expect(decoded.envelope?.snapshot.apiSpendProviders.first?.displayName == "OpenAI API")
        #expect(decoded.envelope?.snapshot.apiSpendProviders.first?.amount == 19.25)
    }

    @Test func widgetProviderSelectionSurvivesSyncAndLegacyPayloadFallsBack() throws {
        let selected = WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: liveSnapshot.providers,
            widgetProviderSelection: ["claude"]
        )
        let decoded = SyncedWidgetSnapshotCodec.decode(
            try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: selected))
        )

        #expect(decoded.envelope?.snapshot.widgetProviderSelection == ["claude"])
        #expect(decoded.envelope?.snapshot.widgetProviders.map(\.id) == ["claude"])

        let encoded = try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: selected))
        var legacyObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var legacySnapshot = try #require(legacyObject["snapshot"] as? [String: Any])
        legacySnapshot.removeValue(forKey: "widgetProviderSelection")
        legacySnapshot["schemaVersion"] = 2
        legacyObject["snapshot"] = legacySnapshot
        let legacy = SyncedWidgetSnapshotCodec.decode(
            try JSONSerialization.data(withJSONObject: legacyObject)
        )

        #expect(legacy.envelope?.snapshot.widgetProviderSelection == nil)
        #expect(legacy.envelope?.snapshot.widgetProviders.map(\.id) == ["claude"])
    }

    @Test func disabledSnapshotRoundTripsWithoutProviders() throws {
        let envelope = makeSyncedEnvelope(snapshot: .disabled(generatedAt: generatedAt))

        let decoded = SyncedWidgetSnapshotCodec.decode(try SyncedWidgetSnapshotCodec.encode(envelope))

        #expect(decoded.envelope?.snapshot.status == .disabled)
        #expect(decoded.envelope?.snapshot.providers.isEmpty == true)
    }

    @Test func unknownProviderAndWindowRoundTrip() throws {
        let snapshot = WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "future-provider",
                    displayName: "Future",
                    planLabel: nil,
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .other("daily"),
                            label: "Daily",
                            percentRemaining: 42,
                            resetsAt: reset,
                            resetLabel: nil,
                            severity: .healthy
                        ),
                    ],
                    renewalDate: nil
                ),
            ]
        )

        let decoded = SyncedWidgetSnapshotCodec.decode(
            try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: snapshot))
        )

        #expect(decoded.envelope?.snapshot.providers[0].id == "future-provider")
        #expect(decoded.envelope?.snapshot.providers[0].windows[0].kind == .other("daily"))
    }

    @Test func subscriptionWindowsFilterDecodedLegacyAllowanceWindows() {
        let provider = WidgetProviderSummary(
            id: "codex",
            displayName: "Codex",
            planLabel: nil,
            freshness: .live,
            windows: [
                WidgetWindowSummary(
                    kind: .weekly,
                    label: "Weekly",
                    percentRemaining: 75,
                    resetsAt: reset,
                    resetLabel: nil,
                    severity: .healthy
                ),
                WidgetWindowSummary(
                    kind: .other("GPT-5.3"),
                    label: "GPT-5.3",
                    percentRemaining: 10,
                    resetsAt: reset,
                    resetLabel: nil,
                    severity: .critical
                ),
            ],
            renewalDate: nil
        )

        #expect(provider.subscriptionWindows.map(\.kind) == [.weekly])
        #expect(provider.weeklyWindow?.percentRemaining == 75)
    }

    @Test func invalidDataReturnsCorrupt() {
        #expect(SyncedWidgetSnapshotCodec.decode(Data("not-json".utf8)) == .corrupt)
    }

    @Test func legacyWidgetSnapshotWithoutAPISpendDecodesWithEmptySpendList() throws {
        let legacyPayload = """
        {
          "schemaVersion": 1,
          "publishedAt": 2100,
          "sourceID": "test-mac",
          "sourcePlatform": "macOS",
          "snapshot": {
            "schemaVersion": 1,
            "generatedAt": 2000,
            "status": "enabled",
            "providers": []
          }
        }
        """

        let decoded = SyncedWidgetSnapshotCodec.decode(Data(legacyPayload.utf8))

        #expect(decoded.envelope?.snapshot.apiSpendProviders == [])
    }

    @Test func unsupportedSchemaReturnsIncompatible() throws {
        let envelope = makeSyncedEnvelope(schemaVersion: 999, snapshot: liveSnapshot)

        let decoded = SyncedWidgetSnapshotCodec.decode(try JSONEncoder().encode(envelope))

        #expect(decoded == .incompatibleSchema)
    }

    @Test func encodedPayloadContainsNoKnownSecretStrings() throws {
        let data = try SyncedWidgetSnapshotCodec.encode(makeSyncedEnvelope(snapshot: liveSnapshot))
        let payload = String(decoding: data, as: UTF8.self)

        #expect(!payload.contains("access_token"))
        #expect(!payload.contains("refresh_token"))
        #expect(!payload.contains("/Users/"))
        #expect(!payload.contains("Claude Code-credentials"))
        #expect(!payload.contains("Authorization"))
        #expect(!payload.contains("x-api-key"))
        #expect(!payload.contains("api.openai.com"))
        #expect(!payload.contains("api.anthropic.com"))
    }

    @Test func newestValidKeepsLocalWhenRemoteIsOlderOrInvalid() {
        let local = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), snapshot: liveSnapshot)
        let older = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 5), snapshot: .disabled(generatedAt: generatedAt))

        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .snapshot(older)) == .snapshot(local))
        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .corrupt) == .snapshot(local))
    }

    @Test func newestValidUsesRemoteWhenNewer() {
        let local = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 10), snapshot: liveSnapshot)
        let newer = makeSyncedEnvelope(publishedAt: Date(timeIntervalSince1970: 11), snapshot: .disabled(generatedAt: generatedAt))

        #expect(SyncedWidgetSnapshotResolution.newestValid(local: local, remote: .snapshot(newer)) == .snapshot(newer))
    }

    private var liveSnapshot: WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: [
                WidgetProviderSummary(
                    id: "claude",
                    displayName: "Claude",
                    planLabel: "max",
                    freshness: .live,
                    windows: [
                        WidgetWindowSummary(
                            kind: .weekly,
                            label: "Weekly",
                            percentRemaining: 80,
                            resetsAt: reset,
                            resetLabel: "Resets tomorrow",
                            severity: .healthy
                        ),
                    ],
                    renewalDate: nil
                ),
            ]
        )
    }

    private var liveSnapshotWithAPISpend: WidgetSnapshotEnvelope {
        WidgetSnapshotEnvelope(
            generatedAt: generatedAt,
            status: .enabled,
            providers: [],
            apiSpendProviders: [
                WidgetAPISpendSummary(
                    id: "codex",
                    displayName: "OpenAI API",
                    amount: 19.25,
                    currency: "usd",
                    periodLabel: "Current month",
                    capturedAt: generatedAt,
                    freshness: .live
                ),
            ]
        )
    }

    private func makeSyncedEnvelope(
        schemaVersion: Int = SyncedWidgetSnapshotEnvelope.schemaVersion,
        publishedAt: Date? = nil,
        snapshot: WidgetSnapshotEnvelope
    ) -> SyncedWidgetSnapshotEnvelope {
        SyncedWidgetSnapshotEnvelope(
            schemaVersion: schemaVersion,
            publishedAt: publishedAt ?? self.publishedAt,
            sourceID: "test-mac",
            sourcePlatform: .macOS,
            snapshot: snapshot
        )
    }
}
