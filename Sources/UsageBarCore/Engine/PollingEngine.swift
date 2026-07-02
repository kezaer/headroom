import Foundation

/// Interval loop that drives periodic refreshes (U6). Kept separate from the store
/// so the cadence mechanics are isolated. `reschedule()` restarts the loop so a
/// changed poll interval takes effect immediately (R14).
@MainActor
public final class PollingEngine {
    private var task: Task<Void, Never>?
    private let intervalMinutes: @MainActor () -> Int
    private let tick: @MainActor () async -> Void

    public init(
        intervalMinutes: @escaping @MainActor () -> Int,
        tick: @escaping @MainActor () async -> Void
    ) {
        self.intervalMinutes = intervalMinutes
        self.tick = tick
    }

    /// Start (or restart) the loop. Reads the interval each cycle, so a preference
    /// change is picked up on the next tick without an explicit reschedule.
    public func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let minutes = max(1, self.intervalMinutes())
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
                if Task.isCancelled { break }
                await self.tick()
            }
        }
    }

    public func reschedule() { start() }
    public func stop() { task?.cancel(); task = nil }

    deinit { task?.cancel() }
}
