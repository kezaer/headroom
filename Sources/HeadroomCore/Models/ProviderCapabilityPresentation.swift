public extension ProviderCapabilityState {
    var recoveryPresentation: ProviderRecoveryPresentation? {
        switch self {
        case .unknown, .discovering, .available:
            nil
        case .inconclusive:
            .init(
                status: "Claude Code location couldn't be confirmed — usage will retry",
                primaryLabel: "Check Again",
                primaryAction: .checkNow,
                secondaryLabel: "Open Guided Setup",
                secondaryAction: .openClaudeSetup
            )
        case .confirmedAbsent:
            .init(
                status: "Install Claude Code to show usage",
                primaryLabel: "Install Claude Code",
                primaryAction: .installClaudeCLI,
                secondaryLabel: "Copy Manual Command",
                secondaryAction: .copyManualCommand
            )
        }
    }
}
