import Foundation

public enum CLIExecutableLocationSource: String, Sendable, Equatable {
    case memoryHint
    case persistedHint
    case loginShell
    case fallback
}

public enum CLIExecutableDiscoveryIssue: String, Sendable, Equatable {
    case shellTimeout
    case shellSpawnFailure
    case invalidShellOutput
    case inaccessibleCandidate
    case invalidatedHint
    case launchRace
}

public enum CLIExecutableLocation: Sendable, Equatable {
    case available(path: String, source: CLIExecutableLocationSource)
    case confirmedAbsent
    case inconclusive(CLIExecutableDiscoveryIssue)

    public var path: String? {
        guard case .available(let path, _) = self else { return nil }
        return path
    }
}

public enum CLIExecutableShellResult: Sendable, Equatable {
    case completed(candidates: [String])
    case timedOut
    case spawnFailed
    case invalidOutput
}

public enum CLIExecutableCandidateStatus: Sendable, Equatable {
    case executable
    case missing
    case inaccessible
}

public enum CLIExecutableInvalidationReason: Sendable, Equatable {
    case nonExecutable
    case launchNotFound
}

public enum CLIExecutableDiagnosticCategory: String, Sendable, Equatable, CaseIterable {
    case memoryHintValidated
    case persistedHintValidated
    case hintInvalidated
    case launchRace
    case loginShellResolved
    case fallbackResolved
    case supportedLocationMiss
    case shellTimeout
    case shellSpawnFailure
    case invalidShellOutput
    case inaccessibleCandidate
}

public struct CLIExecutableDiagnosticEvent: Sendable, Equatable {
    public let category: CLIExecutableDiagnosticCategory
    public let observedAt: Date

    public init(category: CLIExecutableDiagnosticCategory, observedAt: Date) {
        self.category = category
        self.observedAt = observedAt
    }
}

public protocol CLIExecutableHintStoring: Sendable {
    func hint(for executableName: String) -> String?
    func setHint(_ path: String?, for executableName: String)
}

public final class UserDefaultsCLIExecutableHintStore: CLIExecutableHintStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "cliExecutableHint.v1") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func hint(for executableName: String) -> String? {
        defaults.string(forKey: key(for: executableName))
    }

    public func setHint(_ path: String?, for executableName: String) {
        let key = key(for: executableName)
        if let path {
            defaults.set(path, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for executableName: String) -> String {
        "\(keyPrefix).\(executableName)"
    }
}

public protocol CLIExecutableLocating: Sendable {
    func locate(forceRefresh: Bool) async -> CLIExecutableLocation
    func invalidate(path: String, reason: CLIExecutableInvalidationReason) async
    func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent]
}

public extension CLIExecutableLocating {
    func locate() async -> CLIExecutableLocation { await locate(forceRefresh: false) }
    func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent] { [] }
}

/// Provider-scoped executable discovery. Paths are hints, not identity: every cached
/// value is revalidated, launch failures invalidate it, and later cycles can discover
/// a replacement without relaunching Headroom.
public actor CLIExecutableLocator: CLIExecutableLocating {
    public typealias ShellSearch = @Sendable () async -> CLIExecutableShellResult
    public typealias Validate = @Sendable (String) -> CLIExecutableCandidateStatus
    public typealias Now = @Sendable () -> Date

    private struct InFlight: Sendable {
        let id: UUID
        let generation: UInt64
        let task: Task<CLIExecutableLocation, Never>
    }

    private let executableName: String
    private let fallbackPaths: [String]
    private let hintStore: any CLIExecutableHintStoring
    private let shellSearch: ShellSearch
    private let validate: Validate
    private let now: Now
    private var cachedPath: String?
    private var inFlight: InFlight?
    private var generation: UInt64 = 0
    private var pendingInvalidation: CLIExecutableDiscoveryIssue?
    private var diagnosticEvents: [CLIExecutableDiagnosticEvent] = []

    public init(
        executableName: String,
        fallbackPaths: [String],
        hintStore: any CLIExecutableHintStoring = UserDefaultsCLIExecutableHintStore(),
        shellSearch: ShellSearch? = nil,
        validate: Validate? = nil,
        now: @escaping Now = Date.init
    ) {
        self.executableName = executableName
        self.fallbackPaths = fallbackPaths
        self.hintStore = hintStore
        self.shellSearch = shellSearch ?? { await CLIExecutableResolver.searchExecutable(named: executableName) }
        self.validate = validate ?? { path in
            if FileManager.default.isExecutableFile(atPath: path) { return .executable }
            return FileManager.default.fileExists(atPath: path) ? .inaccessible : .missing
        }
        self.now = now
    }

    public func locate(forceRefresh: Bool = false) async -> CLIExecutableLocation {
        if !forceRefresh {
            if let cachedPath, validate(cachedPath) == .executable {
                record(.memoryHintValidated)
                return .available(path: cachedPath, source: .memoryHint)
            }
            if cachedPath != nil { invalidateHintLocally(issue: .invalidatedHint) }

            if let persistedPath = hintStore.hint(for: executableName) {
                if validate(persistedPath) == .executable {
                    cachedPath = persistedPath
                    record(.persistedHintValidated)
                    return .available(path: persistedPath, source: .persistedHint)
                }
                invalidateHintLocally(issue: .invalidatedHint)
            }
        }

        if let inFlight { return await finish(inFlight) }

        let id = UUID()
        let discoveryGeneration = generation
        let shellSearch = self.shellSearch
        let fallbackPaths = self.fallbackPaths
        let validate = self.validate
        let invalidation = pendingInvalidation
        let task = Task.detached(priority: .utility) {
            let shell = await shellSearch()
            return Self.discover(
                shell: shell,
                fallbackPaths: fallbackPaths,
                validate: validate,
                priorInvalidation: invalidation
            )
        }
        let flight = InFlight(id: id, generation: discoveryGeneration, task: task)
        inFlight = flight
        return await finish(flight)
    }

    public func invalidate(path: String, reason: CLIExecutableInvalidationReason) async {
        let persistedPath = hintStore.hint(for: executableName)
        guard cachedPath == path || persistedPath == path else { return }
        generation &+= 1
        cachedPath = nil
        hintStore.setHint(nil, for: executableName)
        pendingInvalidation = reason == .launchNotFound ? .launchRace : .invalidatedHint
        record(reason == .launchNotFound ? .launchRace : .hintInvalidated)
        inFlight = nil
    }

    public func recentDiagnosticEvents() async -> [CLIExecutableDiagnosticEvent] {
        diagnosticEvents
    }

    private func finish(_ flight: InFlight) async -> CLIExecutableLocation {
        let result = await flight.task.value
        guard generation == flight.generation else {
            return await locate(forceRefresh: true)
        }
        let ownsCompletion = inFlight?.id == flight.id
        if ownsCompletion { inFlight = nil }
        if ownsCompletion, case .available(let path, _) = result {
            cachedPath = path
            hintStore.setHint(path, for: executableName)
            pendingInvalidation = nil
        }
        if ownsCompletion { record(result.diagnosticCategory) }
        return result
    }

    private func invalidateHintLocally(issue: CLIExecutableDiscoveryIssue) {
        cachedPath = nil
        hintStore.setHint(nil, for: executableName)
        pendingInvalidation = issue
        record(.hintInvalidated)
    }

    private func record(_ category: CLIExecutableDiagnosticCategory) {
        let event = CLIExecutableDiagnosticEvent(category: category, observedAt: now())
        if diagnosticEvents.last?.category == category {
            diagnosticEvents[diagnosticEvents.count - 1] = event
            return
        }
        diagnosticEvents.append(event)
        if diagnosticEvents.count > 8 { diagnosticEvents.removeFirst(diagnosticEvents.count - 8) }
    }

    private static func discover(
        shell: CLIExecutableShellResult,
        fallbackPaths: [String],
        validate: Validate,
        priorInvalidation: CLIExecutableDiscoveryIssue?
    ) -> CLIExecutableLocation {
        var shellHadCandidate = false
        switch shell {
        case .completed(let candidates):
            shellHadCandidate = !candidates.isEmpty
            if let path = candidates.last(where: { validate($0) == .executable }) {
                return .available(path: path, source: .loginShell)
            }
        case .timedOut, .spawnFailed, .invalidOutput:
            break
        }

        if let path = fallbackPaths.first(where: { validate($0) == .executable }) {
            return .available(path: path, source: .fallback)
        }

        if shellHadCandidate { return .inconclusive(.inaccessibleCandidate) }
        switch shell {
        case .timedOut: return .inconclusive(.shellTimeout)
        case .spawnFailed: return .inconclusive(.shellSpawnFailure)
        case .invalidOutput: return .inconclusive(.invalidShellOutput)
        case .completed:
            return priorInvalidation.map(CLIExecutableLocation.inconclusive) ?? .confirmedAbsent
        }
    }
}

private extension CLIExecutableLocation {
    var diagnosticCategory: CLIExecutableDiagnosticCategory {
        switch self {
        case .available(_, let source):
            switch source {
            case .memoryHint: .memoryHintValidated
            case .persistedHint: .persistedHintValidated
            case .loginShell: .loginShellResolved
            case .fallback: .fallbackResolved
            }
        case .confirmedAbsent:
            .supportedLocationMiss
        case .inconclusive(let issue):
            switch issue {
            case .shellTimeout: .shellTimeout
            case .shellSpawnFailure: .shellSpawnFailure
            case .invalidShellOutput: .invalidShellOutput
            case .inaccessibleCandidate: .inaccessibleCandidate
            case .invalidatedHint: .hintInvalidated
            case .launchRace: .launchRace
            }
        }
    }
}

public extension CLIExecutableLocator {
    static func claude(
        hintStore: any CLIExecutableHintStoring = UserDefaultsCLIExecutableHintStore()
    ) -> CLIExecutableLocator {
        CLIExecutableLocator(
            executableName: "claude",
            fallbackPaths: [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                "\(NSHomeDirectory())/.local/bin/claude",
            ],
            hintStore: hintStore
        )
    }
}
