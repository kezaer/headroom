import Foundation

public enum IOSWidgetSnapshotState: Equatable, Sendable {
    case setupNeeded
    case waitingForMac
    case disabled
    case corrupt
    case incompatibleSchema
    case content(WidgetSnapshotEnvelope)

    public static func from(
        cacheRead: WidgetSnapshotCacheRead,
        syncRead: iCloudSnapshotSyncRead? = nil
    ) -> IOSWidgetSnapshotState {
        if let cached = state(from: cacheRead) {
            return cached
        }
        if let syncRead {
            return state(from: syncRead)
        }
        return .waitingForMac
    }

    private static func state(from read: WidgetSnapshotCacheRead) -> IOSWidgetSnapshotState? {
        switch read {
        case .unavailable:
            .setupNeeded
        case .empty:
            nil
        case .corrupt:
            .corrupt
        case .snapshot(let envelope):
            envelope.status == .disabled ? .disabled : .content(envelope)
        }
    }

    private static func state(from read: iCloudSnapshotSyncRead) -> IOSWidgetSnapshotState {
        switch read {
        case .unavailable:
            .setupNeeded
        case .missing:
            .waitingForMac
        case .corrupt:
            .corrupt
        case .incompatibleSchema:
            .incompatibleSchema
        case .snapshot(let envelope):
            envelope.snapshot.status == .disabled ? .disabled : .content(envelope.snapshot)
        }
    }
}
