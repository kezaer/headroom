import AppKit
import HeadroomCore
import SwiftUI

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
    static func codexHome(for account: ProviderAccount) -> String? {
        account.isBuiltIn ? nil : AccountStorage.codexHomeDirectoryURL(for: account).path
    }

    static func loginCommand(for account: ProviderAccount = .builtIn(for: .codex)) -> String {
        CodexCLI.accountLoginCommand(codexHome: codexHome(for: account))
    }

    static func copyCommand(for account: ProviderAccount = .builtIn(for: .codex)) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(loginCommand(for: account), forType: .string)
    }

    static func copyCommand() { copyCommand(for: .builtIn(for: .codex)) }

    static func openSetup(for account: ProviderAccount = .builtIn(for: .codex), onRetry: @escaping () -> Void) {
        guard openingTasks[account.id] == nil else { return }
        openingTasks[account.id] = Task { @MainActor in
            defer { openingTasks[account.id] = nil }
            if !account.isBuiltIn {
                _ = try? AccountStorage.ensureDirectories(for: account)
            }
            let codexHome = codexHome(for: account)
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
                copyCommand(for: account)
                return
            }
            guard NSWorkspace.shared.open(preparation.scriptURL) else {
                copyCommand(for: account)
                return
            }
            guard preparation.hasExecutable else {
                setOpenedSetupAt(nil, for: account.id)
                cancelRetries(for: account.id)
                copyCommand(for: account)
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
    let onOpenSetup: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reconnecting = action == .reconnect
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .codex, size: 20)
                Text(reconnecting ? "Reconnect Codex" : "Connect Codex")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
                    .foregroundStyle(ProviderStyle.textAccent(for: .codex, scheme: scheme))
            }
            Text(reconnecting
                 ? "Your Codex session needs a quick sign-in before usage can refresh."
                 : "See your remaining Codex usage right here.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text("Sign-in stays in the official Codex CLI and browser. Headroom never sees your password.")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            Button(action: onOpenSetup) {
                Label(reconnecting ? "Open Codex Login" : "Connect with Codex", systemImage: "terminal")
            }
            .buttonStyle(CodexPrimaryButtonStyle())
            .padding(.top, 12)
            steps
                .padding(.top, 14)
            CodexManualCommandDisclosure()
                .padding(.top, 13)
        }
    }

    private var steps: some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("A minute or less")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Rectangle()
                    .fill(ClaudeSetupStyle.hairline(dark: dark))
                    .frame(height: 1)
            }
            step(1, "Terminal opens the official Codex login", dark: dark)
            step(2, "Finish signing in with ChatGPT in your browser", dark: dark)
            step(3, "Come back — Headroom reconnects automatically", dark: dark)
        }
    }

    private func step(_ number: Int, _ text: String, dark: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: Circle())
                .overlay(Circle().strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CodexWaitingCard: View {
    let onCheckNow: () -> Void
    let onReopen: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProviderLogoView(providerID: .codex, size: 20)
                ProgressView().controlSize(.small)
                Text("Finish signing in…")
                    .font(.system(size: 15, weight: .semibold))
                    .kerning(-0.2)
                    .foregroundStyle(ProviderStyle.textAccent(for: .codex, scheme: scheme))
            }
            Text("Complete the ChatGPT sign-in in your browser. Headroom will reconnect when Codex confirms it.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Label("Official Codex CLI · \(CodexCLI.loginCommand)", systemImage: "lock.shield")
                .font(.system(size: 11.5, weight: .medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 9)
                .background(ClaudeSetupStyle.stepBackground(dark: dark), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(ClaudeSetupStyle.stepBorder(dark: dark), lineWidth: 1))
                .padding(.top, 11)
            HStack(spacing: 14) {
                Button(action: onCheckNow) {
                    Label("Check now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SetupChipButtonStyle())
                Button("Reopen Terminal", action: onReopen)
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 4))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ProviderStyle.textAccent(for: .codex, scheme: scheme))
            }
            .padding(.top, 14)
            CodexManualCommandDisclosure()
                .padding(.top, 13)
        }
    }
}

struct CodexManualCommandDisclosure: View {
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
            .accessibilityLabel(open ? "Hide manual Codex login command" : "Show manual Codex login command")
            if open {
                HStack(alignment: .top, spacing: 8) {
                    Text(CodexCLI.loginCommand)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Button(action: CodexSetupSession.copyCommand) {
                        Image(systemName: "doc.on.doc").frame(width: 22, height: 22)
                    }
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 2, verticalPadding: 2))
                    .foregroundStyle(.secondary)
                    .help("Copy Codex login command")
                    .accessibilityLabel("Copy Codex login command")
                }
                .padding(.horizontal, 9).padding(.vertical, 8)
                .background(ClaudeSetupStyle.codeBackground(dark: dark), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .transition(.opacity)
            }
        }
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
        @State private var hovering = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            let top = dark
                ? Color(red: 0.40, green: 0.45, blue: 0.95)
                : Color(red: 0.30, green: 0.35, blue: 0.90)
            let bottom = dark
                ? Color(red: 0.29, green: 0.34, blue: 0.82)
                : Color(red: 0.20, green: 0.24, blue: 0.76)
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(shape.fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)))
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
