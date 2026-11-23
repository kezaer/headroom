import Foundation

public struct T3CodexHome: Sendable, Hashable, Codable {
    public let instanceID: String
    public let displayName: String?
    public let path: CanonicalHomePath
    public let binaryPath: String?
}

public enum T3CodexScan: Sendable, Equatable {
    case notInstalled
    case found([T3CodexHome])
    case unreadable
}

/// Discovery and user choices have separate writers so a rescan cannot erase a label or hide decision.
public struct T3DiscoveryCache: @unchecked Sendable {
    static let storageKey = "t3CodexDiscovery.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func load() -> [T3CodexHome] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([T3CodexHome].self, from: data)) ?? []
    }

    @discardableResult
    public func record(_ scan: T3CodexScan) -> Bool {
        let homes: [T3CodexHome]
        switch scan {
        case .unreadable: return false
        case .notInstalled: homes = []
        case .found(let found): homes = found
        }
        let unique = Set(homes)
        guard unique != Set(load()),
              let data = try? JSONEncoder().encode(unique.sorted(by: BorrowedHomeRoster.t3Order))
        else { return false }
        defaults.set(data, forKey: Self.storageKey)
        return true
    }
}

public struct BorrowedHomeDecisions: Sendable, Equatable, Codable {
    public struct ManualHome: Sendable, Equatable, Codable {
        public let path: CanonicalHomePath
        public let addedAt: Date
    }

    public var manualHomes: [ManualHome] = []
    public var labels: [AccountID: String] = [:]
    public var menuBarBadges: [AccountID: String] = [:]
    public var hidden: Set<AccountID> = []
    public var tracksCLIDefaultAlongsideT3 = false

    static let storageKey = "borrowedCodexHomes.v1"
}

public enum BorrowedHomeRoster {
    public struct Resolved: Sendable, Equatable {
        public let visible: [ProviderAccount]
        public let hidden: [ProviderAccount]
        public let suppressesCLIDefault: Bool
    }

    static func t3Order(_ lhs: T3CodexHome, _ rhs: T3CodexHome) -> Bool {
        (lhs.displayName ?? lhs.instanceID, lhs.instanceID, lhs.path.rawPath, lhs.binaryPath ?? "")
            < (rhs.displayName ?? rhs.instanceID, rhs.instanceID, rhs.path.rawPath, rhs.binaryPath ?? "")
    }

    public static func resolve(discovered: [T3CodexHome], decisions: BorrowedHomeDecisions) -> Resolved {
        let t3 = discovered.sorted(by: t3Order).map {
            BorrowedHome(
                path: $0.path, source: .t3Instance(instanceID: $0.instanceID, displayName: $0.displayName),
                preferredExecutable: $0.binaryPath
            )
        }
        let manual = decisions.manualHomes
            .sorted { ($0.addedAt, $0.path.rawPath) < ($1.addedAt, $1.path.rawPath) }
            .map { BorrowedHome(path: $0.path, source: .manual) }
        var seen: Set<AccountID> = []
        var visible: [ProviderAccount] = []
        var hidden: [ProviderAccount] = []
        for home in t3 + manual {
            let id = AccountID.borrowedHome(home.path)
            guard seen.insert(id).inserted else { continue }
            let sourceLabel: String?
            if case .t3Instance(_, let name) = home.source { sourceLabel = name } else { sourceLabel = nil }
            let row = ProviderAccount(
                borrowing: home, providerID: .codex,
                label: decisions.labels[id] ?? AccountRegistry.normalizedLabel(sourceLabel)
                    ?? home.path.url.lastPathComponent
            )
            if decisions.hidden.contains(id) {
                if home.source.isT3 { hidden.append(row) }
            } else {
                visible.append(row)
            }
        }
        return Resolved(
            visible: visible, hidden: hidden,
            suppressesCLIDefault: !decisions.tracksCLIDefaultAlongsideT3
                && visible.contains { $0.borrowedHome?.source.isT3 == true }
        )
    }
}

public enum BorrowedHomeRejection: Error, Sendable, Equatable {
    case notADirectory
    case isCLIDefault
    case insideHeadroomStorage
    case alreadyTracked(AccountKey)
    case atCapacity
    case unsupportedProvider

    public var message: String {
        switch self {
        case .notADirectory: "Choose an existing Codex folder."
        case .isCLIDefault: "Use the CLI login row to track ~/.codex."
        case .insideHeadroomStorage: "Choose a folder outside Headroom’s account storage."
        case .alreadyTracked: "This folder is already listed in Codex accounts."
        case .atCapacity: "Remove an account before adding another folder."
        case .unsupportedProvider: "External folders are unavailable."
        }
    }
}
