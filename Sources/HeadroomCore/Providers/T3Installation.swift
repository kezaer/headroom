import Foundation

/// Read-only discovery.
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
