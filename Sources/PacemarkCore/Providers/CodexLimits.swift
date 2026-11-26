import Foundation

struct CodexLimitWindow: Sendable, Equatable {
    let usedPercent: Double
    let windowSeconds: Double?
    let resetsAt: Date?

    init(usedPercent: Double, windowSeconds: Double?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowSeconds = windowSeconds
        self.resetsAt = resetsAt
    }

    init?(_ wire: CodexWindowDTO?, now: Date) {
        guard let wire, let percent = wire.utilizationValue else { return nil }
        self.init(
            usedPercent: percent, windowSeconds: wire.windowSecondsValue,
            resetsAt: DateParsing.iso8601(wire.resetAtValue)
                ?? wire.resetEpochValue.map(Date.init(timeIntervalSince1970:))
                ?? wire.resetSecondsValue.map(now.addingTimeInterval)
        )
    }
}

struct CodexLimitBucket: Sendable, Equatable {
    let label: String?
    let primary: CodexLimitWindow?
    let secondary: CodexLimitWindow?
}

enum CodexWindowMapping {
    static func windows(_ buckets: [CodexLimitBucket]) -> [UsageWindow] {
        buckets.flatMap { bucket in
            [(bucket.primary, WindowKind.fiveHour), (bucket.secondary, .weekly)].compactMap { entry in
                let (window, positionalDefault) = entry
                guard let window, let reset = window.resetsAt,
                      reset.timeIntervalSince1970.isFinite, window.usedPercent.isFinite else { return nil }
                let duration = window.windowSeconds.flatMap { $0.isFinite && $0 < Double(Int.max) ? $0 : nil }
                let kind = CodexWindowClassifier.kind(limitWindowSeconds: duration, positionalDefault: positionalDefault)
                return UsageWindow(
                    kind: bucket.label.map { .other("\($0) \(kind.shortLabel)") } ?? kind,
                    utilization: window.usedPercent, resetsAt: reset
                )
            }
        }
    }
}
