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
}

public extension CLIExecutableLocating {
    func locate() async -> CLIExecutableLocation { await locate(forceRefresh: false) }
}

/// Provider-scoped executable discovery. Paths are hints, not identity: every cached
/// value is revalidated, launch failures invalidate it, and later cycles can discover
/// a replacement without relaunching Headroom.
public actor CLIExecutableLocator: CLIExecutableLocating {
    public typealias ShellSearch = @Sendable () async -> CLIExecutableShellResult
    public typealias Validate = @Sendable (String) -> CLIExecutableCandidateStatus

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
    private var cachedPath: String?
    private var inFlight: InFlight?
    private var generation: UInt64 = 0
    private var pendingInvalidation: CLIExecutableDiscoveryIssue?

    public init(
        executableName: String,
        fallbackPaths: [String],
        hintStore: any CLIExecutableHintStoring = UserDefaultsCLIExecutableHintStore(),
        shellSearch: ShellSearch? = nil,
        validate: Validate? = nil
    ) {
        self.executableName = executableName
        self.fallbackPaths = fallbackPaths
        self.hintStore = hintStore
        self.shellSearch = shellSearch ?? { await CLIExecutableResolver.searchExecutable(named: executableName) }
        self.validate = validate ?? { path in
            if FileManager.default.isExecutableFile(atPath: path) { return .executable }
            return FileManager.default.fileExists(atPath: path) ? .inaccessible : .missing
        }
    }

    public func locate(forceRefresh: Bool = false) async -> CLIExecutableLocation {
        if !forceRefresh {
            if let cachedPath, validate(cachedPath) == .executable {
                return .available(path: cachedPath, source: .memoryHint)
            }
            if cachedPath != nil { invalidateHintLocally(issue: .invalidatedHint) }

            if let persistedPath = hintStore.hint(for: executableName) {
                if validate(persistedPath) == .executable {
                    cachedPath = persistedPath
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
        inFlight = nil
    }

    private func finish(_ flight: InFlight) async -> CLIExecutableLocation {
        let result = await flight.task.value
        guard generation == flight.generation else {
            return await locate(forceRefresh: true)
        }
        if inFlight?.id == flight.id { inFlight = nil }
        if case .available(let path, _) = result {
            cachedPath = path
            hintStore.setHint(path, for: executableName)
            pendingInvalidation = nil
        }
        return result
    }

    private func invalidateHintLocally(issue: CLIExecutableDiscoveryIssue) {
        cachedPath = nil
        hintStore.setHint(nil, for: executableName)
        pendingInvalidation = issue
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
