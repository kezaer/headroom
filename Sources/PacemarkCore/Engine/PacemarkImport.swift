import Foundation

public enum PacemarkImport {
    public static let marker = "pacemark.import.v1"
    public static let keepBoth = "pacemark.import.keepBoth"

    public static func shouldImport(key: String) -> Bool {
        let localPrefixes = ["companionSync.", "SU", "NS", "Apple", "com.apple.", "WebKit",
                             "AK", "pacemark.import.", "co.zantos.headroom.bench."]
        let localKeys = ["launchAtLogin", "sessionReliability.v1", "claudeSignOutRecord.v1"]
        return !localKeys.contains(key) && !localPrefixes.contains(where: key.hasPrefix)
    }

    /// Both dictionaries contain only persistent, application-scoped preferences.
    /// Registered defaults and command-line overrides must never suppress an import.
    @discardableResult
    public static func apply(from source: () -> [String: Any], to defaults: UserDefaults,
                             domain: String) -> Bool {
        var destination = defaults.persistentDomain(forName: domain) ?? [:]
        guard destination[marker] == nil else { return false }
        let original = source().filter { shouldImport(key: $0.key) && destination[$0.key] == nil }
        destination.merge(original) { existing, _ in existing }
        destination[marker] = true
        defaults.setPersistentDomain(destination, forName: domain)
        return !original.isEmpty
    }

    public static func warnAboutRunningApp(running: Bool, defaults: UserDefaults) -> Bool {
        running && !defaults.bool(forKey: keepBoth)
    }
}
