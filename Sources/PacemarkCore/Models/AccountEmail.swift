import Foundation

public enum AccountEmail {
    /// Whitespace-trimmed and lowercased, or nil when nothing displayable is left.
    public static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed.lowercased()
    }
}
