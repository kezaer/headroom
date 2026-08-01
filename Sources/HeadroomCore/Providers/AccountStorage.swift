import Foundation
import Darwin

/// Headroom-owned config homes for additional (non-built-in) accounts. Each extra
/// account gets an isolated directory the official CLI signs into once:
/// - Claude: `CLAUDE_CONFIG_DIR` pointed at `…/claude/<id>/config`, plus a stable
///   `workspace` folder the probe cd's into (trust is recorded per config dir, so each
///   account approves the folder once — same flow as the built-in account).
/// - Codex: `CODEX_HOME` pointed at `…/codex/<id>`; `codex login` writes `auth.json`
///   there and Headroom only ever reads it (KTD3 unchanged).
/// - Grok: `GROK_HOME` pointed at `…/grok/<id>`; `grok login` writes `auth.json`
///   there and the official CLI does not fall back to the built-in account.
///
/// The built-in `.primary` account never routes through here — it uses the CLI's own
/// default config so existing installs keep working untouched.
public enum AccountStorage {
    static let preparedMarkerGracePeriod: TimeInterval = 5 * 60

    public static var baseDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Headroom", isDirectory: true)
            .appendingPathComponent("Accounts", isDirectory: true)
    }

    public static func accountDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    static func accountDirectoryURL(for account: ProviderAccount, baseDirectoryURL: URL) -> URL {
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

    /// `CLAUDE_CONFIG_DIR` for an extra Claude account, addressed by id alone. The path
    /// depends only on provider + account id, so the email reader can resolve it without
    /// threading a whole `ProviderAccount` down into the provider.
    static func claudeConfigDirectoryURL(forClaudeAccountID accountID: AccountID) -> URL {
        claudeConfigDirectoryURL(
            for: ProviderAccount(id: accountID, providerID: .claude, label: "")
        )
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

    /// `GROK_HOME` for an extra Grok account; `auth.json` lives directly inside.
    public static func grokHomeDirectoryURL(for account: ProviderAccount) -> URL {
        accountDirectoryURL(for: account)
    }

    public static func grokAuthFileURL(for account: ProviderAccount) -> URL {
        grokHomeDirectoryURL(for: account).appendingPathComponent("auth.json")
    }

    public static func setupCompletionMarker(for account: ProviderAccount) -> SetupCompletionMarker {
        let directory = accountDirectoryURL(for: account)
        return SetupCompletionMarker(
            pendingPath: directory.appendingPathComponent(".headroom-setup-pending").path,
            completedPath: directory.appendingPathComponent(".headroom-setup-complete").path
        )
    }

    /// Stage the durable handoff sentinel before Terminal opens. The wrapper replaces
    /// `opening` with its redaction-safe mode and PID, writes a completion marker on
    /// every normal/signal exit, then removes the pending marker. This survives view
    /// and app closure without persisting account identity or provider output.
    public static func prepareSetupCompletionMarker(_ marker: SetupCompletionMarker) throws {
        let manager = FileManager.default
        let pendingURL = URL(fileURLWithPath: marker.pendingPath)
        try manager.createDirectory(
            at: pendingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? manager.removeItem(atPath: marker.completedPath)
        let opening = "opening:\(Date().timeIntervalSince1970)\n"
        try Data(opening.utf8).write(to: pendingURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.pendingPath)
    }

    public static func clearPreparedSetupCompletionMarker(_ marker: SetupCompletionMarker) {
        try? FileManager.default.removeItem(atPath: marker.pendingPath)
    }

    /// Read only the wrapper's allowlisted `complete:<status>` marker. Missing,
    /// malformed, or out-of-range data stays unknown and never reaches diagnostics.
    public static func setupHandoffCompletion(
        marker: SetupCompletionMarker
    ) -> SetupHandoffCompletion {
        guard let data = FileManager.default.contents(atPath: marker.completedPath),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return .unknown }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0] == "complete",
              let status = UInt8(parts[1])
        else { return .unknown }
        return status == 0 ? .succeeded : .failed
    }

    /// A short-lived `opening` marker covers the gap between AppKit accepting the file
    /// and zsh replacing it with its PID. If the app or Terminal crashes in that gap,
    /// the marker expires rather than blocking account removal forever. Unknown marker
    /// formats still fail closed; a PID clears only when the process is provably gone.
    public static func setupHandoffIsActive(for account: ProviderAccount) -> Bool {
        setupHandoffIsActive(marker: setupCompletionMarker(for: account))
    }

    public static func setupHandoffIsActive(
        marker: SetupCompletionMarker,
        now: Date = .now
    ) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: marker.pendingPath) else { return false }
        guard let data = manager.contents(atPath: marker.pendingPath),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return true }
        if value == "opening" || value.hasPrefix("opening:") {
            let parts = value.split(separator: ":", maxSplits: 1)
            let encodedDate = parts.count == 2
                ? Double(parts[1]).map { Date(timeIntervalSince1970: $0) }
                : nil
            let attributes = try? manager.attributesOfItem(atPath: marker.pendingPath)
            let writtenAt = encodedDate ?? attributes?[.modificationDate] as? Date
            guard let writtenAt,
                  now.timeIntervalSince(writtenAt) > preparedMarkerGracePeriod
            else { return true }
            try? manager.removeItem(atPath: marker.pendingPath)
            return false
        }
        let modeAndPID = value.split(separator: ":", maxSplits: 1)
        let pidText = modeAndPID.count == 2
            && (modeAndPID[0] == "standard" || modeAndPID[0] == "deviceCode")
            ? modeAndPID[1]
            : Substring(value)
        guard let pid = Int32(pidText), pid > 1 else { return true }
        if kill(pid, 0) == 0 || errno == EPERM { return true }
        guard errno == ESRCH else { return true }
        try? manager.removeItem(atPath: marker.pendingPath)
        return false
    }

    /// Restore the explicit login mode after an app relaunch while Terminal remains
    /// open. Legacy PID-only markers are standard; opening/unknown markers have no
    /// recoverable mode yet.
    public static func setupHandoffMode(marker: SetupCompletionMarker) -> SetupHandoffMode? {
        guard let data = FileManager.default.contents(atPath: marker.pendingPath),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        if value.hasPrefix("deviceCode:") { return .deviceCode }
        if value.hasPrefix("standard:") || Int32(value) != nil { return .standard }
        return nil
    }

    /// Create the account's directories so the CLI handoff and probe never race a
    /// missing folder. Safe to call repeatedly.
    @discardableResult
    public static func ensureDirectories(for account: ProviderAccount) throws -> URL {
        try ensureDirectories(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    @discardableResult
    static func ensureDirectories(for account: ProviderAccount, baseDirectoryURL: URL) throws -> URL {
        let directory = accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL)
        var targets = [directory]
        if account.providerID == .claude {
            targets.append(directory.appendingPathComponent("config", isDirectory: true))
            targets.append(directory.appendingPathComponent("workspace", isDirectory: true))
        }
        for url in targets {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }
        return directory
    }

    /// Delete an extra account's config home (its CLI session/token included) after the
    /// account is removed from the registry. Built-in accounts are never touched — their
    /// config belongs to the user's own CLI. The recursive delete runs off-main: a used
    /// config home holds thousands of small CLI files and must not beachball the
    /// Settings window (code-review finding).
    public static func removeDirectories(for account: ProviderAccount) throws {
        try removeDirectories(for: account, baseDirectoryURL: baseDirectoryURL)
    }

    static func removeDirectories(for account: ProviderAccount, baseDirectoryURL: URL) throws {
        guard !account.isBuiltIn else { return }
        let url = accountDirectoryURL(for: account, baseDirectoryURL: baseDirectoryURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let marker = SetupCompletionMarker(
            pendingPath: url.appendingPathComponent(".headroom-setup-pending").path,
            completedPath: url.appendingPathComponent(".headroom-setup-complete").path
        )
        guard !setupHandoffIsActive(marker: marker) else {
            throw AccountStorageOperationError.setupActive
        }
        try FileManager.default.removeItem(at: url)
    }

    public static func credentialFilePermissionsAreSafe(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else { return false }
        return permissions.intValue & 0o077 == 0
    }
}

public enum AccountStorageFailure: Error, Sendable, Equatable {
    case createFailed
    case setupActive
    case removeFailed
}

private enum AccountStorageOperationError: Error {
    case setupActive
}

/// Injection seam for the account config-home file operations, so `UsageStore` unit
/// tests never touch the real Application Support tree (AGENTS.md: the suite is all
/// mocked — no CLI/network/Keychain/filesystem).
public protocol AccountStorageManaging: Sendable {
    func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure>
    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool
    func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure>
}

public extension AccountStorageManaging {
    func setupHandoffIsActive(for account: ProviderAccount) async -> Bool { false }
}

public struct DefaultAccountStorage: AccountStorageManaging {
    public init() {}
    public func ensureDirectories(for account: ProviderAccount) -> Result<Void, AccountStorageFailure> {
        do {
            _ = try AccountStorage.ensureDirectories(for: account)
            return .success(())
        } catch {
            return .failure(.createFailed)
        }
    }
    public func setupHandoffIsActive(for account: ProviderAccount) async -> Bool {
        await Task.detached(priority: .utility) {
            AccountStorage.setupHandoffIsActive(for: account)
        }.value
    }
    public func removeDirectories(for account: ProviderAccount) async -> Result<Void, AccountStorageFailure> {
        await Task.detached(priority: .utility) {
            do {
                try AccountStorage.removeDirectories(for: account)
                return .success(())
            } catch AccountStorageOperationError.setupActive {
                return .failure(.setupActive)
            } catch {
                return .failure(.removeFailed)
            }
        }.value
    }
}
