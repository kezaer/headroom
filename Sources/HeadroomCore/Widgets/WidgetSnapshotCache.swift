import Foundation

public enum WidgetSnapshotCacheRead: Equatable, Sendable {
    case unavailable
    case empty
    case corrupt
    case snapshot(WidgetSnapshotEnvelope)

    public var envelope: WidgetSnapshotEnvelope? {
        if case .snapshot(let envelope) = self { envelope } else { nil }
    }
}

/// App Group-backed widget cache. Production uses a JSON file at the app-group
/// container root because WidgetKit and the host app are separate sandboxed processes.
/// A widget-container fallback keeps local development usable when the app was manually
/// signed and the App Group entitlement is present but not provisioning-backed yet.
/// UserDefaults remains an injectable compatibility seam for tests and non-sandboxed
/// migration paths, but WidgetKit should not depend on cross-process suite defaults.
public struct WidgetSnapshotCache: @unchecked Sendable { // UserDefaults is thread-safe
    public static var appGroupSuiteName: String {
        Bundle.main.object(forInfoDictionaryKey: "HeadroomAppGroupIdentifier") as? String
            ?? "group.com.kylezantos.headroom"
    }

    private static let key = "widgetSnapshotEnvelope"
    private static let fileName = "widget-snapshot.json"
    private static let widgetBundleIdentifier = "com.kylezantos.headroom.widgets"
    private let defaults: UserDefaults?
    private let fileURL: URL?
    private let fallbackFileURLs: [URL]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults?, fileURL: URL? = nil, fallbackFileURLs: [URL] = []) {
        self.defaults = defaults
        self.fileURL = fileURL
        self.fallbackFileURLs = fallbackFileURLs
    }

    public static func appGroup() -> WidgetSnapshotCache {
        let fileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupSuiteName)?
            .appendingPathComponent(Self.fileName)
        let widgetContainerURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(Self.widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(Self.fileName)
        let sandboxApplicationSupportURL = Bundle.main.bundleIdentifier == Self.widgetBundleIdentifier
            ? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent(Self.fileName)
            : nil
        return WidgetSnapshotCache(
            defaults: nil,
            fileURL: fileURL,
            fallbackFileURLs: unique([widgetContainerURL, sandboxApplicationSupportURL])
        )
    }

    public func read() -> WidgetSnapshotCacheRead {
        var sawFileReadFailure = false
        for fileURL in fileURLs {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            do {
                let data = try Data(contentsOf: fileURL)
                return .snapshot(try decoder.decode(WidgetSnapshotEnvelope.self, from: data))
            } catch {
                sawFileReadFailure = true
                continue
            }
        }

        let fallback: WidgetSnapshotCacheRead
        if sawFileReadFailure {
            fallback = .corrupt
        } else if fileURLs.isEmpty {
            fallback = .unavailable
        } else {
            fallback = .empty
        }
        return readDefaults(fallbackWhenMissing: fallback)
    }

    private func readDefaults(fallbackWhenMissing fallback: WidgetSnapshotCacheRead) -> WidgetSnapshotCacheRead {
        guard let defaults else { return fallback }
        guard let data = defaults.data(forKey: Self.key) else {
            return fallback == .unavailable ? .empty : fallback
        }
        do {
            return .snapshot(try decoder.decode(WidgetSnapshotEnvelope.self, from: data))
        } catch {
            return .corrupt
        }
    }

    public func write(_ envelope: WidgetSnapshotEnvelope) throws {
        let data = try encoder.encode(envelope)
        var didWrite = false
        var lastFileWriteFailed = false

        for fileURL in fileURLs {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: [.atomic])
                didWrite = true
            } catch {
                lastFileWriteFailed = true
            }
        }

        if let defaults {
            defaults.set(data, forKey: Self.key)
            defaults.synchronize()
            didWrite = true
        }

        if didWrite { return }
        if lastFileWriteFailed { throw WidgetSnapshotCacheError.writeFailed }
        throw WidgetSnapshotCacheError.unavailable
    }

    private var fileURLs: [URL] {
        Self.unique([fileURL] + fallbackFileURLs.map(Optional.some))
    }

    private static func unique(_ urls: [URL?]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls.compactMap(\.self) {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

public enum WidgetSnapshotCacheError: Error, Equatable {
    case unavailable
    case writeFailed
}
