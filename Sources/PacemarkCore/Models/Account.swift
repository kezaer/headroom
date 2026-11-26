import Foundation

/// Stable identifier for one signed-in account under a provider. `.primary` is the
/// built-in account bound to the CLI's own default config (`~/.claude`, `~/.codex`) —
/// it always exists, so existing single-account installs upgrade with zero migration.
public struct AccountID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    public static let primary = AccountID("primary")

    public var description: String { raw }
}

/// One (provider, account) pair — the unit usage is fetched, keyed, and rendered by
/// once multiple subscriptions per provider exist.
public struct AccountKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let providerID: ProviderID
    public let accountID: AccountID

    public init(providerID: ProviderID, accountID: AccountID) {
        self.providerID = providerID
        self.accountID = accountID
    }

    public var description: String { "\(providerID.raw)/\(accountID.raw)" }
}

public enum AccountOrigin: Sendable, Hashable {
    case cliDefault
    case pacemarkOwned
    case borrowed(BorrowedHome)
}

/// The source presented to the user for an account.
public enum AccountSourceKind: String, Codable, Sendable {
    case t3Code, existingCLI, externalCLI, separateLogin
}

/// The filesystem boundary resolves symlinks before creating this value.
public struct CanonicalHomePath: Sendable, Hashable, Codable, CustomStringConvertible {
    public let rawPath: String

    public init?(trustedCanonical rawPath: String) {
        guard rawPath.hasPrefix("/"), !rawPath.utf8.contains(0),
              rawPath.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        self.rawPath = rawPath
    }

    public var url: URL { URL(fileURLWithPath: rawPath, isDirectory: true) }
    public var description: String { rawPath }

    public func abbreviated(userHome: String) -> String {
        if rawPath == userHome { return "~" }
        guard rawPath.hasPrefix(userHome + "/") else { return rawPath }
        return "~" + rawPath.dropFirst(userHome.count)
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        guard let path = Self(trustedCanonical: try value.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid canonical home")
        }
        self = path
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(rawPath)
    }
}

public enum BorrowedHomeSource: Sendable, Hashable, Codable {
    case t3Instance(instanceID: String, displayName: String?)
    case manual

    public var isT3: Bool {
        if case .t3Instance = self { return true }
        return false
    }
}

public struct BorrowedHome: Sendable, Hashable, Codable {
    public let path: CanonicalHomePath
    public let source: BorrowedHomeSource
    public let preferredExecutable: String?

    public init(path: CanonicalHomePath, source: BorrowedHomeSource, preferredExecutable: String? = nil) {
        self.path = path
        self.source = source
        self.preferredExecutable = preferredExecutable
    }
}

extension AccountID {
    public static func borrowedHome(_ path: CanonicalHomePath) -> AccountID {
        let hash = path.rawPath.utf8.reduce(UInt64(0xcbf29ce484222325)) {
            ($0 ^ UInt64($1)) &* 0x100000001b3
        }
        return AccountID("home-" + String(format: "%016llx", hash))
    }
}

public struct ProviderAccount: Identifiable, Sendable, Codable, Equatable, Hashable {
    public static let builtInDefaultLabel = "Main"

    public let id: AccountID
    public let providerID: ProviderID
    public var label: String
    public let origin: AccountOrigin
    public var isBuiltIn: Bool { origin == .cliDefault }
    public var borrowedHome: BorrowedHome? {
        guard case .borrowed(let home) = origin else { return nil }
        return home
    }

    public init(id: AccountID, providerID: ProviderID, label: String, isBuiltIn: Bool = false) {
        self.id = id
        self.providerID = providerID
        self.label = label
        self.origin = isBuiltIn ? .cliDefault : .pacemarkOwned
    }

    public init(borrowing home: BorrowedHome, providerID: ProviderID, label: String) {
        self.id = .borrowedHome(home.path)
        self.providerID = providerID
        self.label = label
        self.origin = .borrowed(home)
    }

    private enum CodingKeys: String, CodingKey { case id, providerID, label, isBuiltIn, borrowedHome }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try values.decode(ProviderID.self, forKey: .providerID)
        let label = try values.decode(String.self, forKey: .label)
        if let home = try values.decodeIfPresent(BorrowedHome.self, forKey: .borrowedHome) {
            self.init(borrowing: home, providerID: provider, label: label)
        } else {
            self.init(
                id: try values.decode(AccountID.self, forKey: .id),
                providerID: provider, label: label,
                isBuiltIn: try values.decode(Bool.self, forKey: .isBuiltIn)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(providerID, forKey: .providerID)
        try values.encode(label, forKey: .label)
        try values.encode(isBuiltIn, forKey: .isBuiltIn)
        try values.encodeIfPresent(borrowedHome, forKey: .borrowedHome)
    }

    public var key: AccountKey { AccountKey(providerID: providerID, accountID: id) }

    /// The built-in default account every provider starts with.
    public static func builtIn(for providerID: ProviderID) -> ProviderAccount {
        ProviderAccount(
            id: .primary,
            providerID: providerID,
            label: builtInDefaultLabel,
            isBuiltIn: true
        )
    }

    public static func extraDefaultLabel(ordinal: Int) -> String {
        "Account \(ordinal)"
    }

    public static func isDefaultLabel(_ label: String) -> Bool {
        if label == builtInDefaultLabel { return true }

        let prefix = "Account "
        guard label.hasPrefix(prefix) else { return false }
        let suffix = label.dropFirst(prefix.count).utf8
        guard let first = suffix.first, (49...57).contains(first) else { return false }
        return suffix.allSatisfy { (48...57).contains($0) }
    }
}
