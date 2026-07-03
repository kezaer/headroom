import Foundation
import HeadroomCore
import WidgetKit

struct HeadroomWidgetEntry: TimelineEntry {
    let date: Date
    let state: HeadroomWidgetState
}

enum HeadroomWidgetState: Equatable {
    case setupNeeded
    case disabled
    case pending
    case content(WidgetSnapshotEnvelope)

    static func from(_ read: WidgetSnapshotCacheRead) -> HeadroomWidgetState {
        switch read {
        case .unavailable, .corrupt:
            .setupNeeded
        case .empty:
            .pending
        case .snapshot(let envelope):
            envelope.status == .disabled ? .disabled : .content(envelope)
        }
    }
}
