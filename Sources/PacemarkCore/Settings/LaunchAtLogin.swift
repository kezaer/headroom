import ServiceManagement

/// Launch-at-login control (U8, R15). Behind a protocol so Settings can be tested
/// without touching the real login-item registry.
public protocol LaunchAtLoginControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Production wrapper over `SMAppService.mainApp` (macOS 13+ API; replaces the
/// deprecated `SMLoginItemSetEnabled`). Registration requires the app to run from a
/// proper bundle — finalized in the Xcode app target (U1).
public struct LaunchAtLogin: LaunchAtLoginControlling {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled && service.status != .requiresApproval {
                try service.register()
            }
        } else if service.status != .notRegistered {
            try service.unregister()
        }
    }
}
