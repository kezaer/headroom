/// A provider/setup condition that changes which recovery action Headroom may offer.
/// These values deliberately carry no provider output, paths, account identity, or
/// caught errors. Presentation copy is derived separately so behavior never depends
/// on matching a user-facing string.
public enum ProviderSetupOutcome: Sendable, Equatable, Hashable {
    case claudeCLIMissing
    case claudeLoginRequired
    case claudeTrustRequired
    case claudeUnknownUI
    case claudeTransientCapture
    case codexCLIMissing
    case codexAuthAbsent
    case codexPermissionDenied
    case codexUnsafePermissions
    case codexMalformedAuth
    case codexCredentialIO
    case codexRejectedAuth
    case codexStorageMismatch
    case codexCallbackIncomplete

    public var message: String {
        switch self {
        case .claudeCLIMissing: "Install Claude Code to show usage"
        case .claudeLoginRequired: "Sign in with the official Claude CLI"
        case .claudeTrustRequired: "Approve Headroom's Claude workspace in the official CLI"
        case .claudeUnknownUI: "Claude opened an unrecognized setup screen"
        case .claudeTransientCapture: "Couldn't read Claude usage — will retry"
        case .codexCLIMissing: "Install Codex CLI to connect"
        case .codexAuthAbsent: "Connect with the official Codex CLI"
        case .codexPermissionDenied: "Allow Headroom to read the Codex sign-in file"
        case .codexUnsafePermissions: "Codex sign-in data is not stored privately — reconnect"
        case .codexMalformedAuth: "Codex sign-in data is unreadable — reconnect"
        case .codexCredentialIO: "Couldn't read Codex sign-in data"
        case .codexRejectedAuth: "Codex sign-in expired — reconnect"
        case .codexStorageMismatch: "Codex stored this login somewhere Headroom cannot read"
        case .codexCallbackIncomplete: "Codex sign-in did not finish"
        }
    }

    public var isPermanent: Bool {
        switch self {
        case .claudeUnknownUI, .claudeTransientCapture, .codexCredentialIO:
            false
        default:
            true
        }
    }

    /// True only when the account has never completed its first official CLI login.
    /// Timer backoff keys off this typed state rather than enumerating providers.
    public var isNeverSignedIn: Bool {
        switch self {
        case .claudeLoginRequired, .codexAuthAbsent:
            true
        default:
            false
        }
    }

    public var recoveryPresentation: ProviderRecoveryPresentation {
        switch self {
        case .claudeCLIMissing:
            .init(status: message, primaryLabel: "Install Claude Code", primaryAction: .installClaudeCLI,
                  secondaryLabel: "Copy Manual Command", secondaryAction: .copyManualCommand)
        case .claudeLoginRequired:
            .init(status: message, primaryLabel: "Open Claude Setup", primaryAction: .openClaudeSetup,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeTrustRequired:
            .init(status: message, primaryLabel: "Open Claude Workspace", primaryAction: .openClaudeSetup,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .claudeUnknownUI, .claudeTransientCapture:
            .init(status: message, primaryLabel: "Check Again", primaryAction: .checkNow,
                  secondaryLabel: "Open Guided Setup", secondaryAction: .openClaudeSetup)
        case .codexCLIMissing:
            .init(status: message, primaryLabel: "Install Codex CLI", primaryAction: .installCodexCLI)
        case .codexAuthAbsent:
            .init(status: message, primaryLabel: "Connect Codex", primaryAction: .connectCodex,
                  secondaryLabel: "Use Device Code", secondaryAction: .connectCodexDeviceCode,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .codexPermissionDenied:
            .init(status: message, primaryLabel: "Privacy & Security Help", primaryAction: .showPrivacyGuidance,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .codexUnsafePermissions, .codexMalformedAuth, .codexRejectedAuth:
            .init(status: message, primaryLabel: "Reconnect Codex", primaryAction: .reconnectCodex,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow,
                  automaticPolicy: .boundedChecksAfterHandoff)
        case .codexCredentialIO:
            .init(status: message, primaryLabel: "Check Again", primaryAction: .checkNow)
        case .codexStorageMismatch:
            .init(status: message, primaryLabel: "Resolve Storage", primaryAction: .resolveCodexStorage,
                  secondaryLabel: "Check Now", secondaryAction: .checkNow)
        case .codexCallbackIncomplete:
            .init(status: message, primaryLabel: "Reopen Codex Login", primaryAction: .reconnectCodex,
                  secondaryLabel: "Use Device Code", secondaryAction: .connectCodexDeviceCode)
        }
    }
}

public enum SetupRecoveryAction: Sendable, Equatable, Hashable {
    case installClaudeCLI
    case copyManualCommand
    case openClaudeSetup
    case installCodexCLI
    case connectCodex
    case connectCodexDeviceCode
    case reconnectCodex
    case showPrivacyGuidance
    case resolveCodexStorage
    case checkNow
}

public enum SetupAutomaticPolicy: Sendable, Equatable, Hashable {
    case none
    case boundedChecksAfterHandoff
}

public struct ProviderRecoveryPresentation: Sendable, Equatable {
    public let status: String
    public let primaryLabel: String
    public let primaryAction: SetupRecoveryAction
    public let secondaryLabel: String?
    public let secondaryAction: SetupRecoveryAction?
    public let automaticPolicy: SetupAutomaticPolicy

    public init(
        status: String,
        primaryLabel: String,
        primaryAction: SetupRecoveryAction,
        secondaryLabel: String? = nil,
        secondaryAction: SetupRecoveryAction? = nil,
        automaticPolicy: SetupAutomaticPolicy = .none
    ) {
        self.status = status
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
        self.automaticPolicy = automaticPolicy
    }
}

/// Redaction-safe filesystem handshake around an external Terminal setup process.
/// The wrapper writes only its redaction-safe handoff mode/PID and exit status; it
/// never writes provider output, credentials, callback data, paths, or account identity.
public struct SetupCompletionMarker: Sendable, Equatable {
    public let pendingPath: String
    public let completedPath: String

    public init(pendingPath: String, completedPath: String) {
        self.pendingPath = pendingPath
        self.completedPath = completedPath
    }
}
