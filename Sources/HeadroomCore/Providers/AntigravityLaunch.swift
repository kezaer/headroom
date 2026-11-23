import Darwin
import Foundation

public enum AntigravitySignInHome: Sendable, Equatable {
    case system
    case t3Managed(instanceID: String, probeHome: URL)

    public var memoryKey: String {
        switch self {
        case .system: "system"
        case .t3Managed(let id, _): "t3:\(id)"
        }
    }

    public var environmentOverrides: [String: String] {
        guard case .t3Managed(_, let home) = self else { return [:] }
        return ["HOME": home.path]
    }

    var signedOutFailure: AntigravityCaptureFailure {
        self == .system ? .signedOut : .signedOutInT3
    }
}

public struct AntigravityLaunchPlan: Sendable, Equatable {
    public let executable: String
    public let signInHome: AntigravitySignInHome
}

struct ProbeHomeLinker: Sendable {
    func ensureSignInLink(probeHome: URL, target: URL) -> Bool {
        let root = probeHome.deletingLastPathComponent()
        let gemini = probeHome.appendingPathComponent(".gemini", isDirectory: true)
        // Inspect each Headroom-owned component without following symlinks.
        guard ensureDirectory(root.deletingLastPathComponent()),
              ensureDirectory(root), ensureDirectory(probeHome), ensureDirectory(gemini)
        else { return false }
        let destination = gemini.appendingPathComponent("antigravity-cli")
        let existing = fileType(at: destination)
        func alreadyLinked() -> Bool {
            (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == target.path
        }
        if existing == S_IFLNK, alreadyLinked() { return true }
        guard existing == nil || existing == S_IFLNK else { return false }
        let temporary = gemini.appendingPathComponent(".antigravity-\(UUID().uuidString)")
        guard symlink(target.path, temporary.path) == 0 else { return false }
        defer { _ = unlink(temporary.path) }
        // Exclusive rename protects an absent destination. Existing non-symlinks fail closed.
        if existing == nil {
            return renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 || alreadyLinked()
        }
        guard fileType(at: destination) == S_IFLNK else { return false }
        return rename(temporary.path, destination.path) == 0
    }

    private func ensureDirectory(_ url: URL) -> Bool {
        if fileType(at: url) == S_IFDIR { return true }
        _ = mkdir(url.path, 0o700)
        return fileType(at: url) == S_IFDIR
    }

    private func fileType(at url: URL) -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }
}

public struct AntigravityLaunchResolver: Sendable {
    public static var defaultProbeHomesRoot: URL {
        AntigravityCLI.defaultWorkingDirectory.deletingLastPathComponent()
            .appendingPathComponent("AntigravityHomes", isDirectory: true)
    }

    private let t3: T3Installation
    private let probeHomesRoot: URL
    private let resolveSystemExecutable: @Sendable () -> String?

    public init(
        t3: T3Installation, probeHomesRoot: URL = AntigravityLaunchResolver.defaultProbeHomesRoot,
        resolveSystemExecutable: @escaping @Sendable () -> String? = { AntigravityCLI.resolveExecutable() }
    ) {
        self.t3 = t3
        self.probeHomesRoot = probeHomesRoot
        self.resolveSystemExecutable = resolveSystemExecutable
    }

    public func resolve(preference: AntigravitySourcePreference = .autoPreferT3) -> AntigravityLaunchPlan? {
        if preference == .autoPreferT3, let install = t3.antigravity() {
            let probeHome = probeHomesRoot.appendingPathComponent(
                T3Installation.instanceHash(install.instanceID), isDirectory: true
            )
            if ProbeHomeLinker().ensureSignInLink(probeHome: probeHome, target: install.dataDirectory) {
                return .init(
                    executable: install.executable.path,
                    signInHome: .t3Managed(instanceID: install.instanceID, probeHome: probeHome)
                )
            }
        }
        return resolveSystemExecutable().map { .init(executable: $0, signInHome: .system) }
    }
}
