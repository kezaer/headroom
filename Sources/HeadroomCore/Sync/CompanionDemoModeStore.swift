import Foundation

public enum CompanionDemoModeWriteResult: Equatable, Sendable {
    case changed
    case unchanged
    case unavailable
}

/// A deliberately tiny App Group preference shared by the iOS companion and widget.
/// Demo content itself remains an in-memory fixture and never enters the real snapshot
/// cache or iCloud publication path.
public struct CompanionDemoModeStore: @unchecked Sendable { // UserDefaults is thread-safe
    public static let defaultsKey = "companionDemoModeEnabled"
    public static let variantKey = "companionDemoVariant"

    private let defaults: UserDefaults?

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    public static func appGroup() -> CompanionDemoModeStore {
        CompanionDemoModeStore(defaults: UserDefaults(suiteName: WidgetSnapshotCache.appGroupSuiteName))
    }

    public var isEnabled: Bool {
        defaults?.bool(forKey: Self.defaultsKey) ?? false
    }

    /// The selected demo fixture variant. Defaults to 'full' when unset; unrecognized values are resolved to the full fixture by DemoScreenshotData.envelope(for:).
    public var variant: String {
        defaults?.string(forKey: Self.variantKey) ?? "full"
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> CompanionDemoModeWriteResult {
        guard let defaults else { return .unavailable }
        guard isEnabled != enabled else { return .unchanged }

        if enabled {
            defaults.set(true, forKey: Self.defaultsKey)
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        // WidgetKit may launch the extension immediately after the host requests a
        // timeline reload, so flush this one cross-process flag before that handoff.
        defaults.synchronize()
        return .changed
    }

    @discardableResult
    public func setVariant(_ variant: String) -> CompanionDemoModeWriteResult {
        guard let defaults else { return .unavailable }
        let currentVariant = self.variant
        guard currentVariant != variant else { return .unchanged }

        defaults.set(variant, forKey: Self.variantKey)
        defaults.synchronize()
        return .changed
    }
}
