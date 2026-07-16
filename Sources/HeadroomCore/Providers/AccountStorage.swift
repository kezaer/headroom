import Foundation

/// Headroom-owned config homes for additional (non-built-in) accounts. Each extra
/// account gets an isolated directory the official CLI signs into once:
/// - Claude: `CLAUDE_CONFIG_DIR` pointed at `…/claude/<id>/config`, plus a stable
///   `workspace` folder the probe cd's into (trust is recorded per config dir, so each
///   account approves the folder once — same flow as the built-in account).
/// - Codex: `CODEX_HOME` pointed at `…/codex/<id>`; `codex login` writes `auth.json`
///   there and Headroom only ever reads it (KTD3 unchanged).
///
/// The built-in `.primary` account never routes through here — it uses the CLI's own
/// default config so existing installs keep working untouched.
public enum AccountStorage {
    public static var baseDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Headroom", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    public static func accountDirectoryURL(for account: ProviderAccount) -> URL {
        baseDirectoryURL
            .appendingPathComponent(safePathComponent(account.providerID.raw), isDirectory: true)
            .appendingPathComponent(safePathComponent(account.id.raw), isDirectory: true)
    }

    /// Encode arbitrary persisted identifiers into one literal filesystem component.
    /// Production IDs are UUIDs and pass through unchanged; encoding keeps malformed
    /// metadata such as `..` or `a/b` contained beneath the Accounts directory.
    static func safePathComponent(_ raw: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".utf8)
        guard !raw.isEmpty else { return "%00" }
        return raw.utf8.map { byte in
            allowed.contains(byte) ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }.joined()
    }

    /// `CLAUDE_CONFIG_DIR` for an extra Claude account.
    public static func claudeConfigDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account).appendingPathComponent("config", isDirectory: true)
    }

    /// Working directory the probe runs `claude` in for an extra Claude account.
    public static func claudeWorkspaceDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account).appendingPathComponent("workspace", isDirectory: true)
    }

    /// `CODEX_HOME` for an extra Codex account; `auth.json` lives directly inside.
    public static func codexHomeDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account)
    }

    public static func codexAuthFileURL(for account: ProviderAccount) -> URL {
        codexHomeDirectoryURL(for: account).appendingPathComponent("auth.json")
    }

    /// Create the account's directories so the CLI handoff and probe never race a
    /// missing folder. Safe to call repeatedly.
    @discardableResult
    public static func ensureDirectories(for account: ProviderAccount) throws -> URL {
        let directory = accountDirectoryURL(for: account)
        var targets = [directory]
        if account.providerID == .claude {
            targets.append(claudeConfigDirectoryURL(for: account))
            targets.append(claudeWorkspaceDirectoryURL(for: account))
        }
        for url in targets {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Delete an extra account's config home (its CLI session/token included) after the
    /// account is removed from the registry. Built-in accounts are never touched — their
    /// config belongs to the user's own CLI. The recursive delete runs off-main: a used
    /// config home holds thousands of small CLI files and must not beachball the
    /// Settings window (code-review finding).
    public static func removeDirectories(for account: ProviderAccount) {
        guard !account.isBuiltIn else { return }
        let url = accountDirectoryURL(for: account)
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Injection seam for the account config-home file operations, so `UsageStore` unit
/// tests never touch the real Application Support tree (AGENTS.md: the suite is all
/// mocked — no CLI/network/Keychain/filesystem).
public protocol AccountStorageManaging: Sendable {
    func ensureDirectories(for account: ProviderAccount)
    func removeDirectories(for account: ProviderAccount)
}

public struct DefaultAccountStorage: AccountStorageManaging {
    public init() {}
    public func ensureDirectories(for account: ProviderAccount) {
        _ = try? AccountStorage.ensureDirectories(for: account)
    }
    public func removeDirectories(for account: ProviderAccount) {
        AccountStorage.removeDirectories(for: account)
    }
}
