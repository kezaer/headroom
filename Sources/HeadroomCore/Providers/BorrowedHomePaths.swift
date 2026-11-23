import Darwin
import Foundation

public enum BorrowedHomePaths {
    /// Resolve filesystem metadata only. An empty folder can be signed into later by its owner.
    public static func canonicalize(
        _ url: URL, userHome: URL, accountsBase: URL
    ) -> Result<CanonicalHomePath, BorrowedHomeRejection> {
        guard let canonical = existingDirectory(url) else { return .failure(.notADirectory) }
        let path = canonical.rawPath
        let cli = referencePath(userHome.appendingPathComponent(".codex"))
        guard path != cli else { return .failure(.isCLIDefault) }
        let owned = referencePath(accountsBase)
        guard path != owned, !path.hasPrefix(owned + "/") else { return .failure(.insideHeadroomStorage) }
        return .success(canonical)
    }

    /// Match realpath even when the comparison directory has not been created yet.
    static func referencePath(_ directory: URL) -> String {
        var url = directory.standardizedFileURL
        var tail: [String] = []
        while url.path != "/" {
            if let resolved = existingDirectory(url) {
                return ([resolved.rawPath] + tail.reversed()).joined(separator: "/")
            }
            tail.append(url.lastPathComponent)
            url.deleteLastPathComponent()
        }
        return "/" + tail.reversed().joined(separator: "/")
    }

    static func existingDirectory(_ url: URL) -> CanonicalHomePath? {
        guard url.isFileURL, let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        let path = String(cString: resolved)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return nil }
        return CanonicalHomePath(trustedCanonical: path)
    }
}

public struct BorrowedHomeEnvironment: Sendable {
    public let scanT3: @Sendable () -> T3CodexScan
    public let canonicalize: @Sendable (URL) -> Result<CanonicalHomePath, BorrowedHomeRejection>

    public static func live(t3: T3Installation) -> Self {
        Self(scanT3: t3.scanCodexHomes, canonicalize: {
            BorrowedHomePaths.canonicalize($0, userHome: t3.userHome, accountsBase: t3.accountsBase)
        })
    }

    public static let inert = Self(scanT3: { .unreadable }, canonicalize: { _ in .failure(.unsupportedProvider) })
}
