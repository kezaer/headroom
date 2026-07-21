import SwiftUI
import AppKit
import HeadroomCore

/// First-run Claude connection flow (onboarding redesign, Jul 2026): the trust-required
/// failure renders as a calm, guided "Connect Claude" card — value proposition, one
/// primary action, three numbered steps — instead of an amber error. After the user
/// opens setup it becomes a "Waiting for approval…" card, so the existing silent
/// auto-retries (12/35/75s) have visible feedback. Values were tuned in the HTML
/// mockup (.context/headroom-claude-onboarding.html) and are transferred 1:1.
@MainActor
enum ClaudeSetupSession {
    /// Waiting state lives in the observable `SetupSessionActivity` so rows repaint
    /// the instant a Terminal handoff opens; cleared on app relaunch, so the payoff
    /// chip never becomes permanent UI.
    private static var retryTasks: [AccountID: [Task<Void, Never>]] = [:]

    static func openedSetupAt(for accountID: AccountID) -> Date? {
        SetupSessionActivity.shared.openedAt(for: AccountKey(providerID: .claude, accountID: accountID))
    }

    static func setOpenedSetupAt(_ date: Date?, for accountID: AccountID) {
        SetupSessionActivity.shared.set(date, for: AccountKey(providerID: .claude, accountID: accountID))
    }

    /// Built-in-account accessor kept for the single-account flow (popover header,
    /// render harness).
    static var openedSetupAt: Date? {
        get { openedSetupAt(for: .primary) }
        set { setOpenedSetupAt(newValue, for: .primary) }
    }

    /// The Claude workspace the probe drives for an account. Built-in keeps the
    /// original shared folder; extras get their own home under `AccountStorage`.
    static func workspaceURL(for account: ProviderAccount) -> URL {
        account.isBuiltIn
            ? ClaudeUsageWorkspace.defaultDirectoryURL
            : AccountStorage.claudeWorkspaceDirectoryURL(for: account)
    }

    static func command(for account: ProviderAccount = .builtIn(for: .claude)) -> String {
        let configuration = ProviderAccountConfiguration.make(for: account)
        return ClaudeSetupCommand.manualCommand(for: ClaudeSetupDescriptor(
            accountKey: account.key,
            executablePath: nil,
            loginPath: "",
            workspaceDirectory: configuration.claudeWorkspaceDirectory?.path ?? workspaceURL(for: account).path,
            configDirectory: configuration.claudeConfigDirectory?.path
        ))
    }

    static var command: String { command() }

    /// Tilde-abbreviated command for display; `command` (absolute) is what's copied.
    static func displayCommand(for account: ProviderAccount = .builtIn(for: .claude)) -> String {
        command(for: account).replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static var displayCommand: String { displayCommand() }

    static func copyCommand(for account: ProviderAccount = .builtIn(for: .claude)) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command(for: account), forType: .string)
    }

    static func copyCommand() { copyCommand(for: .builtIn(for: .claude)) }

    /// Writes and opens the guided `.command` script (same mechanism as before the
    /// redesign), marks the session as waiting, and schedules the auto-retries.
    /// Extra accounts additionally export their `CLAUDE_CONFIG_DIR` and walk the user
    /// through signing in with the account being added.
    static func openSetup(for account: ProviderAccount = .builtIn(for: .claude), onRetry: @escaping () -> Void) {
        setOpenedSetupAt(Date(), for: account.id)
        do {
            let workspace: URL
            if account.isBuiltIn {
                workspace = try ClaudeUsageWorkspace.ensureDefaultDirectory()
            } else {
                try AccountStorage.ensureDirectories(for: account)
                workspace = AccountStorage.claudeWorkspaceDirectoryURL(for: account)
            }
            // Script filename is per-account: a shared name let a second account's
            // Sign In overwrite the script a still-open Terminal was about to run,
            // landing the login in the wrong config home (code-review finding).
            let scriptURL = ClaudeUsageWorkspace.defaultDirectoryURL.deletingLastPathComponent()
                .appendingPathComponent(account.isBuiltIn
                    ? "Open Claude Setup.command"
                    : "Add Claude Account \(account.id.raw.prefix(8)).command")
            let configExport = account.isBuiltIn
                ? ""
                : "export CLAUDE_CONFIG_DIR=\(shellQuoted(AccountStorage.claudeConfigDirectoryURL(for: account).path))\n"
            let intro = account.isBuiltIn
                ? """
                echo "Headroom needs Claude Code to trust this empty folder before it can read /usage."
                echo
                echo "When Claude asks, choose: Yes, I trust this folder"
                echo "After approving, return to Headroom. It will retry automatically."
                """
                : """
                echo "Adding another Claude account to Headroom."
                echo
                echo "1. Log in when Claude asks — use the account you want to add."
                echo "   (This login is kept separate from your main Claude Code account.)"
                echo "2. If Claude asks about this folder, choose: Yes, I trust this folder"
                echo "3. Return to Headroom. It will pick the account up automatically."
                """
            let script = """
            #!/bin/zsh
            clear
            export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
            \(configExport)cd \(shellQuoted(workspace.path)) || exit 1
            \(intro)
            echo
            if ! command -v claude >/dev/null 2>&1; then
              echo "Claude Code CLI was not found. Install Claude Code, then reopen Headroom."
              echo
              echo "Press any key to close this window."
              read -k 1
              exit 127
            fi
            exec claude
            """
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            guard NSWorkspace.shared.open(scriptURL) else {
                setOpenedSetupAt(nil, for: account.id)
                cancelRetries(for: account.id)
                copyCommand(for: account)
                return
            }
            scheduleRetries(for: account.id, onRetry)
        } catch {
            // Failed to stage the handoff: clear the waiting flag (no Terminal ever
            // opened, so a spinner would wait forever — code-review finding) and fall
            // back to the copyable command.
            setOpenedSetupAt(nil, for: account.id)
            cancelRetries(for: account.id)
            copyCommand(for: account)
        }
    }

    /// Stop pending auto-retries. Called once the connection goes live — otherwise the
    /// 35s/75s retries keep spawning full 20–30s Claude CLI cycles after success, and
    /// the popover footer reads "Refreshing…" for minutes.
    static func cancelRetries(for accountID: AccountID) {
        retryTasks[accountID]?.forEach { $0.cancel() }
        retryTasks[accountID] = nil
    }

    static func cancelRetries() { cancelRetries(for: .primary) }

    private static func scheduleRetries(for accountID: AccountID, _ onRetry: @escaping () -> Void) {
        cancelRetries(for: accountID)
        retryTasks[accountID] = [12.0, 35.0, 75.0].map { delay in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                onRetry()
            }
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

/// Setup-flow palette, transferred from the mockup's OKLCH light palette (WCAG-checked:
/// button label ≥4.6:1, accent text 6.3:1, chip ink 5.1:1) and its dark equivalents.
enum ClaudeSetupStyle {
    /// Dark values darkened (audit): the original dark gradient left the white 13pt
    /// label at 3.1–3.8:1; this ramp averages ≈4.5:1 across the button face.
    static func buttonTop(dark: Bool) -> Color {
        dark ? Color(red: 0.75, green: 0.40, blue: 0.22) : Color(red: 0.733, green: 0.345, blue: 0.133)
    }
    static func buttonBottom(dark: Bool) -> Color {
        dark ? Color(red: 0.69, green: 0.34, blue: 0.17) : Color(red: 0.663, green: 0.302, blue: 0.110)
    }
    /// Clay accent used as *text* — darker than the brand fill so it passes AA.
    static func accentText(dark: Bool) -> Color {
        dark ? Color(red: 0.910, green: 0.561, blue: 0.369) : Color(red: 0.604, green: 0.282, blue: 0.106)
    }
    static func stepBackground(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }
    static func stepBorder(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
    static func wellBackground(dark: Bool) -> Color {
        dark ? Color.black.opacity(0.32) : Color.black.opacity(0.05)
    }
    static func codeBackground(dark: Bool) -> Color {
        wellBackground(dark: dark)
    }
    static func hairline(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
    /// "Connected" chip ink — offset from the bar-fill green so it passes AA as text on
    /// the chip tint in both schemes (light darker, dark brighter + thinner tint).
    static func connectedInk(dark: Bool) -> Color {
        dark ? Color(red: 0.25, green: 0.86, blue: 0.42) : Color(red: 0.082, green: 0.447, blue: 0.208)
    }
    static func connectedBackground(dark: Bool) -> Color {
        let green = HeadroomSeverityColorValues.healthy(dark: dark)
        return Color(red: green.red, green: green.green, blue: green.blue).opacity(0.12)
    }
}

/// State 1 — "Connect Claude": value first, one primary action, guided steps, and the
/// raw command demoted behind a disclosure.
struct ClaudeConnectCard: View {
    var outcome: ProviderSetupOutcome = .claudeTrustRequired
    let onOpenSetup: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .claude, size: 20)
                Text(outcome == .claudeLoginRequired ? "Sign in to Claude" : "Connect Claude")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
            }
            Text(outcome == .claudeLoginRequired
                 ? "Sign in through the official Claude CLI to show this account's usage."
                 : "See your remaining Claude usage right here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            reassurance
                .padding(.top, 11)
            Button(action: onOpenSetup) {
                Label(outcome.recoveryPresentation.primaryLabel, systemImage: "terminal")
            }
            .buttonStyle(ClaudePrimaryButtonStyle())
            .padding(.top, 12)
            steps(dark: dark)
                .padding(.top, 14)
            ClaudeManualCommandDisclosure()
                .padding(.top, 13)
        }
    }

    /// "official /usage · no login · never spends usage" — the trust line that makes a
    /// first-run user comfortable pressing the button.
    private var reassurance: some View {
        Text("Reads Claude's official \(Text("/usage").font(.system(size: 10.5, design: .monospaced))) panel through its CLI. Headroom never receives your password or tokens, and the check never spends usage.")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func steps(dark: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("Takes about 20 seconds")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
                Rectangle()
                    .fill(ClaudeSetupStyle.hairline(dark: dark))
                    .frame(height: 1)
            }
            step(1, Text("Terminal opens and starts Claude for you"), dark: dark)
            step(2, outcome == .claudeLoginRequired
                 ? Text("Finish signing in, then approve the workspace if asked")
                 : Text("Choose \(Text("“Yes, I trust this folder”").fontWeight(.semibold).foregroundColor(.primary)) when asked"), dark: dark)
            step(3, Text("Come back — your usage appears here automatically"), dark: dark)
        }
    }

    private func step(_ number: Int, _ text: Text, dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: Circle())
                .overlay(Circle().strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
            text
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// State 2 — "Waiting for approval…": visible feedback for the auto-retry window. The
/// literal trust-prompt option is a quiet bordered token (not bold prose) so it never
/// competes with the bold title above it.
struct ClaudeWaitingCard: View {
    var outcome: ProviderSetupOutcome = .claudeTrustRequired
    let onCheckNow: () -> Void
    let onReopen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .claude, size: 20)
                ProgressView()
                    .controlSize(.small)
                Text(outcome == .claudeLoginRequired ? "Waiting for sign-in…" : "Waiting for approval…")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
            }
            Text(outcome == .claudeLoginRequired
                 ? "Finish signing in in the Terminal that just opened. Headroom checks this account automatically."
                 : "In the Terminal that just opened, choose the option below — Headroom connects the moment you approve.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if outcome == .claudeTrustRequired {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text("“Yes, I trust this folder”")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.vertical, 6)
                .padding(.leading, 9).padding(.trailing, 11)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
                .padding(.top, 11)
            }
            HStack(spacing: 14) {
                Button(action: onCheckNow) {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SetupChipButtonStyle())
                Button("Reopen Terminal", action: onReopen)
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 4))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ClaudeSetupStyle.accentText(dark: dark))
            }
            .padding(.top, 14)
            ClaudeManualCommandDisclosure()
                .padding(.top, 13)
        }
    }
}

/// "Rather run it yourself?" — the manual command, demoted behind a disclosure so the
/// shell never dominates the first-run card. Shown tilde-abbreviated, wraps fully.
struct ClaudeManualCommandDisclosure: View {
    @State private var open = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? nil : HeadroomMotion.settle) { open.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text("Rather run it yourself?")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 5, verticalPadding: 3))
            if open {
                HStack(alignment: .top, spacing: 8) {
                    Text(ClaudeSetupSession.displayCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Button(action: ClaudeSetupSession.copyCommand) {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
                    .foregroundStyle(.secondary)
                    .help("Copy command")
                    .accessibilityLabel("Copy command")
                }
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(ClaudeSetupStyle.codeBackground(dark: dark), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(.opacity)
            }
        }
    }
}

/// Full-width clay gradient primary — the card's one unmistakable action. Hover
/// brightens, press settles 0.98; both input-driven (no idle motion).
struct ClaudePrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, dark: scheme == .dark)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let dark: Bool
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    shape.fill(LinearGradient(
                        colors: [ClaudeSetupStyle.buttonTop(dark: dark), ClaudeSetupStyle.buttonBottom(dark: dark)],
                        startPoint: .top, endPoint: .bottom))
                )
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1).blendMode(.plusLighter).opacity(0.6))
                .shadow(color: .black.opacity(0.20), radius: 1, y: 1)
                .brightness(configuration.isPressed ? -0.03 : (hovering ? 0.04 : 0))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(HeadroomMotion.press, value: hovering)
                .animation(HeadroomMotion.press, value: configuration.isPressed)
        }
    }
}

/// Quiet bordered chip for the waiting card's secondary action ("Check now").
struct SetupChipButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, dark: scheme == .dark)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        let dark: Bool
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(dark ? Color(white: 0.85) : Color(red: 0.24, green: 0.24, blue: 0.26))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(shape.fill(dark ? Color.white.opacity(hovering ? 0.14 : 0.10) : Color.white.opacity(hovering ? 0.9 : 0.72)))
                .overlay(shape.strokeBorder(dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0 : 0.10), radius: 1, y: 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(HeadroomMotion.press, value: hovering)
                .animation(HeadroomMotion.press, value: configuration.isPressed)
        }
    }
}
