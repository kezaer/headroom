import Foundation

public struct SyncedWidgetSnapshotEnvelope: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let publishedAt: Date
    public let sourceID: String
    public let sourcePlatform: SyncedWidgetSnapshotSourcePlatform
    public let snapshot: WidgetSnapshotEnvelope

    public init(
        schemaVersion: Int = Self.schemaVersion,
        publishedAt: Date,
        sourceID: String,
        sourcePlatform: SyncedWidgetSnapshotSourcePlatform,
        snapshot: WidgetSnapshotEnvelope
    ) {
        self.schemaVersion = schemaVersion
        self.publishedAt = publishedAt
        self.sourceID = sourceID
        self.sourcePlatform = sourcePlatform
        self.snapshot = snapshot
    }
}

public enum SyncedWidgetSnapshotSourcePlatform: String, Codable, Sendable {
    case macOS
    case iOS
    case unknown
}

public enum SyncedWidgetSnapshotDecodeResult: Equatable, Sendable {
    case missing
    case incompatibleSchema
    case corrupt
    case snapshot(SyncedWidgetSnapshotEnvelope)

    public var envelope: SyncedWidgetSnapshotEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

public enum SyncedWidgetSnapshotCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ envelope: SyncedWidgetSnapshotEnvelope) throws -> Data {
        try encoder.encode(envelope)
    }

    public static func decode(_ data: Data?) -> SyncedWidgetSnapshotDecodeResult {
        guard let data else { return .missing }
        do {
            let header = try decoder.decode(SyncedWidgetSnapshotHeader.self, from: data)
            guard header.schemaVersion == SyncedWidgetSnapshotEnvelope.schemaVersion,
                  WidgetSnapshotEnvelope.supports(schemaVersion: header.snapshot.schemaVersion)
            else { return .incompatibleSchema }
            let envelope = try decoder.decode(SyncedWidgetSnapshotEnvelope.self, from: data)
            return .snapshot(envelope)
        } catch {
            return .corrupt
        }
    }
}

/// The iCloud path checks compatibility before decoding the full tree so an unsupported
/// payload cannot be mislabeled corrupt because a future child shape is unknown. The
/// local macOS `WidgetSnapshotCache` intentionally has no supports gate; it is written
/// and read by the same installed app version.
private struct SyncedWidgetSnapshotHeader: Decodable {
    struct Snapshot: Decodable { let schemaVersion: Int }
    let schemaVersion: Int
    let snapshot: Snapshot
}

public enum SyncedWidgetSnapshotResolution {
    public static func newestValid(
        local: SyncedWidgetSnapshotEnvelope?,
        remote: SyncedWidgetSnapshotDecodeResult
    ) -> SyncedWidgetSnapshotDecodeResult {
        guard case .snapshot(let remoteEnvelope) = remote else {
            return local.map(SyncedWidgetSnapshotDecodeResult.snapshot) ?? remote
        }
        guard let local else { return .snapshot(remoteEnvelope) }
        if remoteEnvelope.publishedAt > local.publishedAt { return .snapshot(remoteEnvelope) }
        if remoteEnvelope.publishedAt < local.publishedAt { return .snapshot(local) }
        return remoteEnvelope.sourceID >= local.sourceID ? .snapshot(remoteEnvelope) : .snapshot(local)
    }
}
