#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import AppKit
import PacemarkCore
import SwiftUI
#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif

/// Session-local state for the official Codex CLI handoff. It is intentionally separate
/// from Claude setup so either provider can wait or recover without canceling the other.
@MainActor
enum CodexSetupSession {
    private static var retryTasks: [AccountID: [Task<Void, Never>]] = [:]
    private static var openingTasks: [AccountID: Task<Void, Never>] = [:]

    static func openedSetupAt(for accountID: AccountID) -> Date? {
        SetupSessionActivity.shared.openedAt(for: AccountKey(providerID: .codex, accountID: accountID))
    }

    static func setOpenedSetupAt(_ date: Date?, for accountID: AccountID) {
        SetupSessionActivity.shared.set(date, for: AccountKey(providerID: .codex, accountID: accountID))
    }

    /// Built-in-account accessor kept for the single-account flow (popover header,
    /// render harness).
    static var openedSetupAt: Date? {
        get { openedSetupAt(for: .primary) }
        set { setOpenedSetupAt(newValue, for: .primary) }
    }

    /// `CODEX_HOME` for an extra account; nil for the built-in (default `~/.codex`).
    static func codexHome(for setup: SetupCapableAccount) -> String? {
        setup.ownedHome.map { AccountStorage.codexHomeDirectoryURL(for: $0.account).path }
    }

    static func loginCommand(for account: SetupCapableAccount = .builtIn(for: .codex)) -> String {
        CodexCLI.accountLoginCommand(codexHome: codexHome(for: account))
    }

    /// R2M9: reports whether the write landed, so the copy button only confirms a copy that
    /// actually happened. The Terminal-handoff fallbacks below still ignore the result —
    /// there is nothing better to offer them if the pasteboard refuses.
    @discardableResult
    static func copyCommand(for account: SetupCapableAccount) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(loginCommand(for: account), forType: .string)
    }

    @discardableResult
    static func copyCommand() -> Bool { copyCommand(for: .builtIn(for: .codex)) }

    static func openSetup(for setup: SetupCapableAccount, onRetry: @escaping () -> Void) {
        let account = setup.account
        guard openingTasks[account.id] == nil else { return }
        openingTasks[account.id] = Task { @MainActor in
            defer { openingTasks[account.id] = nil }
            if let owned = setup.ownedHome {
                guard (try? AccountStorage.ensureDirectories(for: owned)) != nil else { return }
            }
            let codexHome = codexHome(for: setup)
            // Per-account filename — see ClaudeSetupSession.openSetup (script-overwrite race).
            let scriptName = account.isBuiltIn
                ? "Open Codex Login.command"
                : "Add Codex Account \(account.id.raw.prefix(8)).command"
            let preparation = await Task.detached(priority: .userInitiated) { () -> (scriptURL: URL, hasExecutable: Bool)? in
                let supportDirectory = ClaudeUsageWorkspace.defaultDirectoryURL.deletingLastPathComponent()
                let scriptURL = supportDirectory.appendingPathComponent(scriptName)
                let executablePath = CodexCLI.resolveExecutable()
                do {
                    try FileManager.default.createDirectory(
                        at: supportDirectory,
                        withIntermediateDirectories: true
                    )
                    try CodexCLI.loginScript(executablePath: executablePath, codexHome: codexHome)
                        .write(to: scriptURL, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes(
                        [.posixPermissions: 0o755],
                        ofItemAtPath: scriptURL.path
                    )
                    return (scriptURL: scriptURL, hasExecutable: executablePath != nil)
                } catch {
                    return nil
                }
            }.value

            guard let preparation else {
                copyCommand(for: setup)
                return
            }
            guard NSWorkspace.shared.open(preparation.scriptURL) else {
                copyCommand(for: setup)
                return
            }
            guard preparation.hasExecutable else {
                setOpenedSetupAt(nil, for: account.id)
                cancelRetries(for: account.id)
                copyCommand(for: setup)
                return
            }
            setOpenedSetupAt(Date(), for: account.id)
            scheduleRetries(for: account.id, onRetry)
        }
    }

    static func cancelRetries(for accountID: AccountID) {
        retryTasks[accountID]?.forEach { $0.cancel() }
        retryTasks[accountID] = nil
    }

    static func cancelRetries() { cancelRetries(for: .primary) }

    private static func scheduleRetries(for accountID: AccountID, _ onRetry: @escaping () -> Void) {
        cancelRetries(for: accountID)
        retryTasks[accountID] = [8.0, 20.0, 45.0, 90.0].map { delay in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                onRetry()
            }
        }
    }
}

struct CodexConnectCard: View {
    let action: CodexConnectionAction
    var presentation: ProviderRecoveryPresentation? = nil
    let onOpenSetup: () -> Void
    var onSecondaryAction: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reconnecting = action == .reconnect
        VStack(alignment: .leading, spacing: .zero) {
            HStack(spacing: PDS.Space.xs) {
                ProviderLogoView(providerID: .codex, size: 20)
                // R2C6: one verb. "Connect Codex" / "Reconnect Codex" named the same act
                // the Claude card next to it called signing in.
                Text(ProviderSignInCopy.cardTitle(for: .codex, again: reconnecting))
                    .font(PDS.Typography.rowTitle)
                    .kerning(SetupCardMetrics.titleKerning)
                    .foregroundStyle(ProviderStyle.textAccent(for: .codex, scheme: scheme))
            }
            Text(reconnecting
                 ? "Your Codex session needs a quick sign-in before usage can refresh."
                 : "See your remaining Codex usage right here.")
                .font(PDS.Typography.body)
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.leadGap)
            // R2B2: the tertiary note tier, matching the Claude card's reassurance line.
            Text("Sign-in stays in the official Codex CLI and browser. Pacemark never sees your password.")
                .font(PDS.Typography.secondary)
                .foregroundStyle(.tertiary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.siblingGap)
            Button(action: onOpenSetup) {
                Label(
                    presentation?.primaryLabel
                        ?? (reconnecting ? ProviderSignInCopy.buttonAgain : ProviderSignInCopy.button),
                    systemImage: "terminal"
                )
            }
            .buttonStyle(CodexPrimaryButtonStyle())
            .padding(.top, SetupCardMetrics.siblingGap)
            if let secondaryLabel = presentation?.secondaryLabel,
               let onSecondaryAction {
                // B3A/P4C/B3: "Use Device Code" was a bare indigo label hanging under the
                // full-width primary. The primary keeps its width; the secondary becomes a
                // thin chip in the leading action row beneath it.
                // B3X: this card's prose starts at its own leading edge, not the 34pt axis.
                CardActionRow(labelInset: 0) {
                    Button(secondaryLabel, action: onSecondaryAction)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                        .accessibilityLabel(secondaryLabel)
                }
            }
            steps
                .padding(.top, SetupCardMetrics.sectionGap)
            CodexManualCommandDisclosure()
                .padding(.top, SetupCardMetrics.siblingGap)
        }
    }

    private var steps: some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: PDS.Space.s) {
            HStack(spacing: PDS.Space.xs) {
                Text("A minute or less")
                    .font(PDS.Typography.secondary.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(ClaudeSetupStyle.hairline(dark: dark))
                    .frame(height: 1)
            }
            step(1, "Terminal opens the official Codex login", dark: dark)
            step(2, "Finish signing in with ChatGPT in your browser", dark: dark)
            step(3, "Come back — Pacemark reconnects automatically", dark: dark)
        }
    }

    private func step(_ number: Int, _ text: String, dark: Bool) -> some View {
        HStack(alignment: .top, spacing: PDS.Space.s) {
            Text("\(number)")
                .font(PDS.Typography.secondary.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: Circle())
                .overlay(Circle().strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
            // R2B2: the steps answer the lead, so they read at the lead's size.
            Text(text)
                .font(PDS.Typography.body)
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum CodexAccessRecoveryKind {
    case permission
    case storage
}

/// Recovery that cannot be repaired by silently reopening login. Permission denial
/// goes to macOS access guidance; storage mismatch deliberately names the file-store
/// repair before the user invokes the official CLI again.
struct CodexAccessRecoveryCard: View {
    let kind: CodexAccessRecoveryKind
    let onPrimaryAction: () -> Void
    let onCheckNow: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: PDS.Space.s) {
            HStack(spacing: PDS.Space.xs) {
                ProviderLogoView(providerID: .codex, size: 20)
                Text(kind == .permission ? "Allow Codex Access" : "Resolve Codex Storage")
                    .font(PDS.Typography.rowTitle)
                    .foregroundStyle(ProviderStyle.textAccent(for: .codex, scheme: scheme))
            }
            Text(kind == .permission
                 ? "Pacemark found the Codex sign-in file but macOS did not allow it to be read. Signing in again cannot repair this permission."
                 : "Codex did not leave a readable file for this account. Reopen its official login with Pacemark’s account-specific file-storage setting.")
                .font(PDS.Typography.body)
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            // P4C/B3: the full-width primary keeps its own line, as in `CodexConnectCard`;
            // "Check Now" drops to the card's leading action row.
            VStack(alignment: .leading, spacing: .zero) {
                Button(kind == .permission ? "Open Privacy & Security" : "Resolve Storage", action: onPrimaryAction)
                    .buttonStyle(CodexPrimaryButtonStyle())
                    .accessibilityLabel(kind == .permission
                                        ? "Open Privacy and Security for Codex file access"
                                        : "Resolve Codex storage for this account")
                // B3X: aligned with the card's prose, which starts at its own edge.
                CardActionRow(labelInset: 0) {
                    Button("Check Now", action: onCheckNow)
                        .buttonStyle(SetupChipButtonStyle(size: .small))
                }
            }
        }
    }
}

struct CodexWaitingCard: View {
    var mode: SetupHandoffMode = .standard
    var phase: SetupWaitingPhase? = nil
    let onReopen: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func loadingMotion(reduceMotion: Bool) -> SetupMotion {
        SetupMotion.resolve(phase: phase ?? .waitingForUser(.signIn), surface: .card, reduceMotion: reduceMotion)
    }

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: .zero) {
            HStack(spacing: PDS.Space.xs) {
                ProviderLogoView(providerID: .codex, size: 20)
                let loading = loadingMotion(reduceMotion: reduceMotion)
                // R7: the same title-slot vessel as Claude; setup phases own its motion.
                HalftoneVesselView(state: .init(id: "codex-setup", level: loading.level),
                                  motion: loading.motion, width: 10, height: 16, columns: 4, rows: 8)
                Text(phase?.copy.title ?? (mode == .deviceCode ? "Finish device-code sign-in…" : "Finish signing in…"))
                    .font(PDS.Typography.rowTitle)
                    .kerning(SetupCardMetrics.titleKerning)
                    .foregroundStyle(ProviderStyle.textAccent(for: .codex, scheme: scheme))
            }
            Text(mode == .deviceCode
                 ? "Follow the device-code instructions in Terminal. Pacemark will reconnect when Codex confirms it."
                 : "Complete the ChatGPT sign-in in your browser. Pacemark will reconnect when Codex confirms it.")
                .font(PDS.Typography.body)
                .foregroundStyle(.secondary)
                // PB11: 2pt on every line of popover prose that is allowed to wrap.
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SetupCardMetrics.leadGap)
            Label(mode == .deviceCode
                  ? "Official Codex CLI · device code · file-backed sign-in"
                  : "Official Codex CLI · file-backed sign-in", systemImage: "lock.shield")
                .font(PDS.Typography.secondary.weight(.medium))
                .padding(.vertical, PDS.Space.xs)
                .padding(.horizontal, PDS.Space.s)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
                .padding(.top, SetupCardMetrics.siblingGap)
            // B3A/P4C/B3: same as the Claude waiting card — a thin chip, leading-aligned at
            // the card's foot, with no icon inside it.
            // R13/KTD12 (2026-09-19 sign-in plan): Check Now left every waiting surface. The
            // row is shared with Claude, and nothing the user could force is outstanding
            // while the official CLI still owns the Terminal window.
            // B3X: same as the Claude waiting card — the guided card's own leading edge.
            CardActionRow(labelInset: 0) {
                Button("Reopen Terminal", action: onReopen)
                    .buttonStyle(SetupChipButtonStyle(size: .small))
            }
            CodexManualCommandDisclosure()
                .padding(.top, SetupCardMetrics.siblingGap)
        }
    }
}

struct CodexManualCommandDisclosure: View {
    @State private var open = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        // R2M7/S2A: see `ClaudeManualCommandDisclosure` — the revealed well is a crossfade
        // and keeps its timing under Reduce Motion; the chevron's rotation is movement and
        // snaps. `reduceMotion ? nil : token` silenced both, so the disclosure blinked.
        let movement = PacemarkMotion.resolved(PacemarkMotion.settle, .movement, reduceMotion: reduceMotion)
        VStack(alignment: .leading, spacing: PDS.Space.s) {
            Button {
                open.toggle()
            } label: {
                HStack(spacing: PDS.Space.xs) {
                    Image(systemName: "chevron.right")
                        .font(PDS.Typography.caps)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .animation(movement, value: open)
                    Text("Rather run it yourself?")
                        .font(PDS.Typography.secondary)
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 5, verticalPadding: 3))
            .accessibilityLabel(open ? "Hide manual Codex login command" : "Show manual Codex login command")
            if open {
                HStack(alignment: .top, spacing: PDS.Space.s) {
                    Text(CodexCLI.accountLoginCommand(codexHome: nil))
                        .font(PDS.Typography.numberSmall)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    CopyFeedbackButton(
                        copy: { CodexSetupSession.copyCommand() },
                        label: "Copy Codex login command"
                    )
                }
                .padding(.horizontal, PDS.Space.s).padding(.vertical, PDS.Space.s)
                .background(ClaudeSetupStyle.codeBackground(dark: dark), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(PacemarkMotion.fade(PacemarkMotion.settle, reduceMotion: reduceMotion))
            }
        }
        // RM1: `.movement`, so under Reduce Motion the disclosure's height snaps and only the
        // well's fade (on its transition) keeps its timing.
        .animation(movement, value: open)
    }
}

/// PB13: Codex's half of the setup palette, mirroring `ClaudeSetupStyle`. The CTA gradient
/// used to be four raw RGB literals inside the button's own body, which made it the one
/// brand colour in the app with no name and no shared home. It stays a *local* enum rather
/// than a Core token on purpose: the two provider setup flows are deliberately decoupled, so
/// a Codex tweak must never reach into Claude's ramp.
enum CodexSetupStyle {
    /// R2C18: the four literals are stops on Codex's constant-hue ramp (H 271.5°) in
    /// `PacemarkBrandRamp`; the dark top dropped L 0.611 → 0.565 because white on it measured
    /// 3.97:1, below AA. This enum stays the call surface, so a Codex tweak still cannot
    /// reach into Claude's ramp.
    static func buttonTop(dark: Bool) -> Color {
        ProviderStyle.codexCTATop(dark: dark)
    }

    static func buttonBottom(dark: Bool) -> Color {
        ProviderStyle.codexCTABottom(dark: dark)
    }
}

struct CodexPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, dark: scheme == .dark)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let dark: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            let top = CodexSetupStyle.buttonTop(dark: dark)
            let bottom = CodexSetupStyle.buttonBottom(dark: dark)
            // S3A: hover in fast, out slow; press lands inside 100ms and returns on settle.
            let hoverAnimation = hovering ? PacemarkMotion.hoverIn : PacemarkMotion.hoverOut
            let pressAnimation = configuration.isPressed ? PacemarkMotion.pressDown : PacemarkMotion.settle
            configuration.label
                .font(PDS.Typography.rowTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PDS.Space.s)
                .background(shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1).blendMode(.plusLighter).opacity(0.6))
                .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                .brightness(configuration.isPressed ? -0.03 : (hovering ? 0.04 : 0))
                // S2A: brightness is a colour change and keeps its timing under Reduce Motion;
                // the press scale below is movement, so it carries its own modifier.
                .animation(PacemarkMotion.resolved(hoverAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: hovering)
                .animation(PacemarkMotion.resolved(pressAnimation, .crossfade, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                // PB12: one press scale across all four button styles.
                .scaleEffect(configuration.isPressed ? PacemarkMotion.pressScale : 1)
                .animation(PacemarkMotion.resolved(pressAnimation, .movement, reduceMotion: reduceMotion),
                           value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
