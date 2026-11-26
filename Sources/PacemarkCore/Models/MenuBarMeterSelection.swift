import Foundation

public enum MenuBarMeterWindow: Codable, Hashable, Sendable {
    case auto
    case limit(String)

    private enum Keys: String, CodingKey { case auto, popover, leastLeft, limit }
    private enum Payload: String, CodingKey { case value = "_0" }

    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Keys.self)
        if keys.contains(.auto) || keys.contains(.popover) || keys.contains(.leastLeft) {
            self = .auto
        } else if keys.contains(.limit) {
            self = .limit(try keys.nestedContainer(keyedBy: Payload.self, forKey: .limit).decode(String.self, forKey: .value))
        } else {
            self = .auto
        }
    }

    init(legacyChoice: MenuBarWindowChoice) {
        switch legacyChoice {
        case .closest: self = .auto
        case .window(let id): self = .limit(id)
        }
    }
}

public struct MenuBarMeterSelection: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case chosen, tightest
    }

    public struct Item: Codable, Equatable, Sendable {
        public let account: AccountKey
        public var window: MenuBarMeterWindow

        /// Only user-entered text appears below the gauge.
        public var label: String?

        private enum CodingKeys: String, CodingKey { case account, window, label }

        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            self.init(account: try fields.decode(AccountKey.self, forKey: .account),
                      window: try fields.decode(MenuBarMeterWindow.self, forKey: .window),
                      label: try fields.decodeIfPresent(String.self, forKey: .label))
        }

        public static func trimmedLabel(_ value: String) -> String {
            String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public init(account: AccountKey, window: MenuBarMeterWindow = .auto, label: String? = "") {
            self.account = account
            self.label = label.map(Self.trimmedLabel)
            self.window = window
        }
    }

    /// Missing in selections saved before label fields became explicit-only.
    var explicitLabels: Bool?
    public var seenAccounts: Set<AccountKey>?
    public var mode: Mode
    public var items: [Item]
    public var hidden: [Item]

    public init(mode: Mode = .chosen, items: [Item] = [], hidden: [Item] = []) {
        explicitLabels = true
        self.mode = mode
        self.items = items
        self.hidden = hidden
    }

    /// Remember both shown and hidden accounts. Temporarily absent accounts keep their
    /// settings, and new ones join at the end even if their provider is currently off.
    public mutating func appendNewAccounts(_ accounts: [AccountKey]) {
        var known = seenAccounts ?? []
        known.formUnion(items.map(\.account) + hidden.map(\.account))
        items.append(contentsOf: accounts.filter { known.insert($0).inserted }.map { Item(account: $0) })
        seenAccounts = known
    }
}
