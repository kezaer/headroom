import CryptoKit
import Foundation

/// Read-only discovery. The Antigravity token is checked using metadata alone.
public struct T3Installation: Sendable {
    public enum Architecture: String, Sendable {
        case arm64, x64

        public static var current: Self {
            #if arch(arm64)
            .arm64
            #else
            .x64
            #endif
        }
    }

    let userHome: URL
    let accountsBase: URL
    let architecture: Architecture

    public init(
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        architecture: Architecture = .current, accountsBase: URL = AccountStorage.baseDirectoryURL
    ) {
        self.userHome = userHome
        self.architecture = architecture
        self.accountsBase = accountsBase
    }

    private var root: URL { userHome.appendingPathComponent(".t3", isDirectory: true) }
    private var settingsFile: URL { root.appendingPathComponent("userdata/settings.json") }

    public func scanCodexHomes() -> T3CodexScan {
        do {
            guard let instances = T3SettingsParser.parse(try Data(contentsOf: settingsFile)) else {
                return .unreadable
            }
            let homes: [T3CodexHome] = instances.compactMap { instance in
                guard instance.enabled, instance.driver == "codex",
                      let rawPath = instance.shadowHomePath, rawPath.hasPrefix("/"),
                      case .success(let path) = BorrowedHomePaths.canonicalize(
                          URL(fileURLWithPath: rawPath), userHome: userHome, accountsBase: accountsBase
                      )
                else { return nil }
                return T3CodexHome(
                    instanceID: instance.id, displayName: instance.displayName, path: path,
                    binaryPath: instance.binaryPath
                )
            }
            return .found(homes.sorted(by: BorrowedHomeRoster.t3Order))
        } catch CocoaError.fileReadNoSuchFile {
            return .notInstalled
        } catch {
            return .unreadable
        }
    }

    /// T3 Claude uses the default Claude CLI login, shared with Terminal.
    public func claudeInstanceName() -> String? {
        guard let settings = try? Data(contentsOf: settingsFile) else { return nil }
        return Self.claudeInstanceName(in: settings, userHome: userHome.path)
    }

    static func claudeInstanceName(in settings: Data, userHome: String) -> String? {
        let defaultHomes = ["", "~/.claude", userHome + "/.claude"]
        let instance = T3SettingsParser.parse(settings)?.first {
            $0.enabled && $0.driver == "claudeAgent" && defaultHomes.contains($0.homePath ?? "")
        }
        return instance.map { $0.displayName ?? "Claude (T3)" }
    }

    public func antigravity() -> T3AntigravityInstall? {
        let tools = root.appendingPathComponent("tools/antigravity-acp/darwin-\(architecture.rawValue)")
        guard let settings = try? Data(contentsOf: settingsFile),
              let instances = T3SettingsParser.parse(settings),
              let active = try? Data(contentsOf: tools.appendingPathComponent("active.json")),
              let release = try? JSONDecoder().decode(ActiveRelease.self, from: active),
              !release.releaseId.isEmpty, release.releaseId.utf8.allSatisfy(Self.isReleaseIDByte)
        else { return nil }
        let executable = tools.appendingPathComponent("versions/\(release.releaseId)/antigravity")
        let files = FileManager.default
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: executable.path, isDirectory: &isDirectory),
              !isDirectory.boolValue, files.isExecutableFile(atPath: executable.path)
        else { return nil }

        let eligible = instances.filter { $0.enabled && $0.driver == "antigravity" }
            .sorted { ($0.id != "antigravity" ? 1 : 0, $0.id) < ($1.id != "antigravity" ? 1 : 0, $1.id) }
        for instance in eligible {
            let directory = root.appendingPathComponent(
                "userdata/providers/antigravity/\(Self.instanceHash(instance.id))/antigravity-acp",
                isDirectory: true
            )
            let token = directory.appendingPathComponent("antigravity-oauth-token")
            guard files.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  files.fileExists(atPath: token.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            return T3AntigravityInstall(instanceID: instance.id, executable: executable, dataDirectory: directory)
        }
        return nil
    }

    static func instanceHash(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func isReleaseIDByte(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
            || byte == 45 || byte == 95
    }

    private struct ActiveRelease: Decodable { let releaseId: String }
}

public struct T3AntigravityInstall: Sendable, Equatable {
    public let instanceID: String
    public let executable: URL
    public let dataDirectory: URL
}

enum T3SettingsParser {
    struct Instance: Sendable, Equatable {
        let id: String
        let driver: String
        let displayName: String?
        let enabled: Bool
        let shadowHomePath: String?
        let binaryPath: String?
        let homePath: String?
    }

    private struct Settings: Decodable { let providerInstances: [String: WireInstance] }
    private struct WireInstance: Decodable {
        let driver: String?
        let displayName: String?
        let enabled: Bool?
        let config: Config?
    }
    private struct Config: Decodable {
        let shadowHomePath: String?
        let binaryPath: String?
        let homePath: String?
    }

    static func parse(_ data: Data) -> [Instance]? {
        guard let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return nil }
        return settings.providerInstances.keys.sorted().compactMap { id in
            guard let entry = settings.providerInstances[id], let driver = entry.driver else { return nil }
            return Instance(
                id: id, driver: driver, displayName: entry.displayName, enabled: entry.enabled ?? true,
                shadowHomePath: entry.config?.shadowHomePath, binaryPath: entry.config?.binaryPath,
                homePath: entry.config?.homePath
            )
        }
    }
}
