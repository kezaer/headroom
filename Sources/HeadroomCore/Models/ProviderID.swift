/// Stable identifier for a usage provider. A struct rather than a closed enum so a
/// third provider can be added (R13) without changing this type.
public struct ProviderID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    public static let claude = ProviderID("claude")
    public static let codex = ProviderID("codex")

    public var description: String { raw }
}
