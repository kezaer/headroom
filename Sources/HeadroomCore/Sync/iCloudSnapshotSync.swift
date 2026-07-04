import Foundation

public enum iCloudSnapshotSyncRead: Equatable, Sendable {
    case unavailable
    case missing
    case corrupt
    case incompatibleSchema
    case snapshot(SyncedWidgetSnapshotEnvelope)

    public var envelope: SyncedWidgetSnapshotEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

public enum iCloudSnapshotSyncError: Error, Equatable, Sendable {
    case unavailable
    case writeFailed
}

public protocol iCloudKeyValueSyncing: Sendable {
    func data(forKey key: String) -> Data?
    @discardableResult func set(_ data: Data, forKey key: String) -> Bool
    @discardableResult func synchronize() -> Bool
}

public struct iCloudSnapshotSync: Sendable {
    public static let snapshotKey = "headroom.syncedWidgetSnapshot"

    private let store: (any iCloudKeyValueSyncing)?
    private let key: String
    private let localEnvelope: @Sendable () -> SyncedWidgetSnapshotEnvelope?

    public init(
        store: (any iCloudKeyValueSyncing)?,
        key: String = Self.snapshotKey,
        localEnvelope: @escaping @Sendable () -> SyncedWidgetSnapshotEnvelope? = { nil }
    ) {
        self.store = store
        self.key = key
        self.localEnvelope = localEnvelope
    }

    public func read() -> iCloudSnapshotSyncRead {
        guard let store else { return .unavailable }
        _ = store.synchronize()
        let remote = SyncedWidgetSnapshotCodec.decode(store.data(forKey: key))
        return read(from: SyncedWidgetSnapshotResolution.newestValid(local: localEnvelope(), remote: remote))
    }

    public func publish(_ envelope: SyncedWidgetSnapshotEnvelope) throws {
        guard let store else { throw iCloudSnapshotSyncError.unavailable }
        let data = try SyncedWidgetSnapshotCodec.encode(envelope)
        guard store.set(data, forKey: key), store.synchronize() else {
            throw iCloudSnapshotSyncError.writeFailed
        }
    }

    private func read(from result: SyncedWidgetSnapshotDecodeResult) -> iCloudSnapshotSyncRead {
        switch result {
        case .missing:
            .missing
        case .incompatibleSchema:
            .incompatibleSchema
        case .corrupt:
            .corrupt
        case .snapshot(let envelope):
            .snapshot(envelope)
        }
    }
}

public struct iCloudSnapshotPublisher: WidgetSnapshotExporting {
    private let sync: iCloudSnapshotSync
    private let now: @Sendable () -> Date
    private let sourceID: @Sendable () -> String

    public init(
        sync: iCloudSnapshotSync,
        now: @escaping @Sendable () -> Date = Date.init,
        sourceID: @escaping @Sendable () -> String = { "Mac" }
    ) {
        self.sync = sync
        self.now = now
        self.sourceID = sourceID
    }

    public func export(_ envelope: WidgetSnapshotEnvelope) {
        let synced = SyncedWidgetSnapshotEnvelope(
            publishedAt: now(),
            sourceID: sourceID(),
            sourcePlatform: .macOS,
            snapshot: envelope
        )
        try? sync.publish(synced)
    }
}

#if canImport(Foundation)
public struct UbiquitousKeyValueSyncStore: iCloudKeyValueSyncing, @unchecked Sendable {
    private let store: NSUbiquitousKeyValueStore

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ data: Data, forKey key: String) -> Bool {
        store.set(data, forKey: key)
        return true
    }

    public func synchronize() -> Bool {
        store.synchronize()
    }
}
#endif
