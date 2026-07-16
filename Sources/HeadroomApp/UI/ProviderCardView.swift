import SwiftUI
import AppKit
import HeadroomCore

/// One account's row data inside a provider card.
struct ProviderAccountEntry: Identifiable {
    let account: ProviderAccount
    let snapshot: UsageSnapshot
    var id: AccountID { account.id }
}

/// One provider's card (U7). Renders the explicit states off `snapshot.freshness`:
/// `.pending` first-run skeleton, `.live`, transient stale (last data kept, marked with
/// a "Stale" pill), permanent needs-reauth (actionable command), and — for Claude's
/// trust-required first run and Codex credential recovery — guided Connect/Waiting
/// cards that hand control to each provider's official CLI.
///
/// Multi-account (Jul 2026): the card takes one `ProviderAccountEntry` per configured
/// account. A single account renders exactly the pre-multi-account layout (no labels,
/// no dividers — nothing changed for the common case). Two or more accounts stack
/// labeled sections inside the one provider card, divided by inset hairlines; at three
/// or more the meters step down to the compact recipe so five accounts stay glanceable.
/// The guided full-size Connect/Waiting cards stay reserved for the single-account
/// first run — extra accounts get a compact inline sign-in row instead, since the
/// user explicitly created them from Settings and just needs the Terminal handoff.
///
/// Type + spacing were tuned in the mockup: 16pt bold card titles, 14pt vertical rhythm
/// between rows, 20pt card padding. Plan pills return in multi-account mode as the
/// natural differentiator ("Max" vs "Pro"); they stay hidden with one account
/// (density audit).
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let entries: [ProviderAccountEntry]
    let percentageMode: UsagePercentageMode
    let now: Date
    let onRetrySetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var showsConnectedChip = false

    private var isMultiAccount: Bool { entries.count > 1 }
    /// Compact meters once the stack is deep enough that full-size rows would push
    /// the popover past a comfortable glance height.
    private var isCompact: Bool { entries.count >= 3 }
    private var primaryEntry: ProviderAccountEntry? { entries.first }
    private var snapshot: UsageSnapshot { primaryEntry?.snapshot ?? .pending(for: providerID) }
    private var primaryAccount: ProviderAccount {
        primaryEntry?.account ?? .builtIn(for: providerID)
    }

    var body: some View {
        Group {
            if isMultiAccount {
                multiAccountBody
            } else {
                singleAccountBody
            }
        }
        // 13pt pad / 9pt rhythm — one step above the large widget's 10/9 to account
        // for the popover's larger type (walked down from 20/14 → 16/11 → here).
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedTile(cornerRadius: 10)
        // A refresh replacing the pending skeleton (or a stale card recovering) cross-fades
        // and springs its height change rather than hard-cutting — the arrival of a poll
        // cycle, felt not flashed. Snaps instead under Reduce Motion.
        .animation(reduceMotion ? nil : HeadroomMotion.valueSpring, value: snapshot.freshness)
        .onAppear { evaluateConnectedPayoff() }
        .onChange(of: snapshot.freshness) { evaluateConnectedPayoff() }
    }

    // MARK: - Single account (unchanged pre-multi-account layout)

    @ViewBuilder private var singleAccountBody: some View {
        if isClaudeTrustSetup {
            if ClaudeSetupSession.openedSetupAt(for: primaryAccount.id) != nil {
                ClaudeWaitingCard(
                    onCheckNow: onRetrySetup,
                    onReopen: { ClaudeSetupSession.openSetup(for: primaryAccount, onRetry: onRetrySetup) }
                )
            } else {
                ClaudeConnectCard(
                    onOpenSetup: { ClaudeSetupSession.openSetup(for: primaryAccount, onRetry: onRetrySetup) }
                )
            }
        } else if let action = snapshot.codexConnectionAction {
            VStack(alignment: .leading, spacing: 13) {
                if CodexSetupSession.openedSetupAt(for: primaryAccount.id) != nil {
                    CodexWaitingCard(
                        onCheckNow: onRetrySetup,
                        onReopen: { CodexSetupSession.openSetup(for: primaryAccount, onRetry: onRetrySetup) }
                    )
                } else {
                    CodexConnectCard(
                        action: action,
                        onOpenSetup: { CodexSetupSession.openSetup(for: primaryAccount, onRetry: onRetrySetup) }
                    )
                }
                if action == .reconnect, !snapshot.windows.isEmpty {
                    bars(for: snapshot, dimmed: true)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 9) {
                header
                content
            }
        }
    }

    // MARK: - Multi-account

    private var multiAccountBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: isCompact ? 9 : 11) {
                ForEach(entries) { entry in
                    if entry.id != entries.first?.id {
                        Rectangle()
                            .fill(ClaudeSetupStyle.hairline(dark: scheme == .dark))
                            .frame(height: 1)
                    }
                    AccountSectionView(
                        providerID: providerID,
                        entry: entry,
                        percentageMode: percentageMode,
                        now: now,
                        compact: isCompact,
                        onRetrySetup: onRetrySetup
                    )
                }
            }
        }
    }

    /// The guided-setup payoff: when either provider goes live after its Terminal handoff,
    /// stop only that provider's retries and show the "Connected" chip briefly.
    private func evaluateConnectedPayoff() {
        guard case .live = snapshot.freshness else { return }
        let accountID = primaryAccount.id
        let setupOpenedAt: Date
        switch providerID {
        case .claude:
            guard let openedAt = ClaudeSetupSession.openedSetupAt(for: accountID) else { return }
            setupOpenedAt = openedAt
            ClaudeSetupSession.cancelRetries(for: accountID)
        case .codex:
            guard let openedAt = CodexSetupSession.openedSetupAt(for: accountID) else { return }
            setupOpenedAt = openedAt
            CodexSetupSession.cancelRetries(for: accountID)
        default:
            return
        }
        guard !showsConnectedChip else { return }
        withAnimation(reduceMotion ? nil : HeadroomMotion.valueSpring) { showsConnectedChip = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(reduceMotion ? nil : HeadroomMotion.settle) { showsConnectedChip = false }
            switch providerID {
            case .claude where ClaudeSetupSession.openedSetupAt(for: accountID) == setupOpenedAt:
                ClaudeSetupSession.setOpenedSetupAt(nil, for: accountID)
            case .codex where CodexSetupSession.openedSetupAt(for: accountID) == setupOpenedAt:
                CodexSetupSession.setOpenedSetupAt(nil, for: accountID)
            default: break
            }
        }
    }

    /// Claude's folder-trust first run — the one failure that gets the guided flow.
    private var isClaudeTrustSetup: Bool {
        guard providerID == .claude, case .stale(let reason) = snapshot.freshness else { return false }
        return reason.isPermanent && reason.message == ClaudeUsageWorkspace.trustRequiredMessage
    }

    /// The per-card "Updated N min ago" was removed here — both providers poll on one
    /// cycle, so it reads once in the popover header (PopoverView) instead of twice.
    /// Header mirrors the large widget's recipe (icon ≈ 1.33× the title size, title in
    /// the shared brand text-accent) so popover and widgets read as one family.
    private var header: some View {
        HStack(spacing: 6) {
            ProviderLogoView(providerID: providerID, size: 21)
            Text(displayName)
                .font(.system(size: 16, weight: .semibold))
                .kerning(-0.2)
                .foregroundStyle(ProviderStyle.textAccent(for: providerID, scheme: scheme))
            if isMultiAccount {
                // Quiet count so a five-account stack announces its size up front.
                Text("\(entries.count) accounts")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 6)
            if showsConnectedChip {
                connectedChip
                    .transition(.opacity)
            }
        }
    }

    private var connectedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Connected")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(ClaudeSetupStyle.connectedInk(dark: scheme == .dark))
        .padding(.horizontal, 8).padding(.vertical, 2.5)
        .background(ClaudeSetupStyle.connectedBackground(dark: scheme == .dark), in: Capsule())
    }

    @ViewBuilder private var content: some View {
        Group {
            switch snapshot.freshness {
            case .pending:
                pendingSkeleton
            case .live:
                bars(for: snapshot, dimmed: false)
            case .stale(let reason):
                staleContent(reason)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func staleContent(_ reason: FailureReason) -> some View {
        if reason.isPermanent {
            actionable(reason)
            if !snapshot.windows.isEmpty { bars(for: snapshot, dimmed: true) }
        } else {
            bars(for: snapshot, dimmed: true)
            stalePill(reason)
        }
    }

    @ViewBuilder private func bars(for snapshot: UsageSnapshot, dimmed: Bool) -> some View {
        if snapshot.windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 9) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(window: window, percentageMode: percentageMode, now: now, dimmed: dimmed)
                }
            }
        }
    }

    /// Varied widths (audit UI-13): real content isn't two identical bars, so the
    /// skeleton previews the true shape rather than reading as "broken". The wait names
    /// the ~20–30s first Claude poll so the delay feels intentional, not hung.
    private var pendingSkeleton: some View {
        VStack(alignment: .leading, spacing: 9) {
            skeletonMeter(labelWidth: 72, valueWidth: 42)
            skeletonMeter(labelWidth: 86, valueWidth: 36)
            Text("Fetching usage…")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func skeletonMeter(labelWidth: CGFloat, valueWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(ProviderStyle.barTrack(scheme: scheme)).frame(width: labelWidth, height: 13)
                Spacer(minLength: 6)
                RoundedRectangle(cornerRadius: 4).fill(ProviderStyle.barTrack(scheme: scheme)).frame(width: valueWidth, height: 13)
            }
            Capsule().fill(ProviderStyle.barTrack(scheme: scheme)).frame(height: 8)
        }
    }

    /// Permanent failure the user can fix (UI-05) that is not one of the guided setup
    /// states: message + compact copyable command.
    @ViewBuilder private func actionable(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
            if let command = recoveryCommand {
                CommandRecoveryRow(command: command)
            }
        }
    }

    /// Small "Stale" flag + the transient reason, so a network blip is explicit rather
    /// than communicated only by a faint bar (which also reads as "disabled").
    private func stalePill(_ reason: FailureReason) -> some View {
        HStack(spacing: 6) {
            Text("Stale")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.20), in: Capsule())
            Text(reason.message)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The CLI command that recovers each provider (nil for unknown providers).
    private var recoveryCommand: String? {
        switch providerID {
        case .claude: return "claude"
        case .codex: return CodexCLI.loginCommand
        default: return nil
        }
    }
}

// MARK: - Account section (multi-account rows)

/// One account's section inside a multi-account provider card: a quiet identity row
/// (label + plan) above the account's meters, with per-account failure affordances.
/// Kept intentionally smaller than the card header — accounts are siblings *within*
/// a provider, one hierarchy step below the brand row.
private struct AccountSectionView: View {
    let providerID: ProviderID
    let entry: ProviderAccountEntry
    let percentageMode: UsagePercentageMode
    let now: Date
    let compact: Bool
    let onRetrySetup: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var snapshot: UsageSnapshot { entry.snapshot }
    private var account: ProviderAccount { entry.account }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 7) {
            identityRow
            stateContent
        }
        .animation(reduceMotion ? nil : HeadroomMotion.valueSpring, value: snapshot.freshness)
        .onChange(of: snapshot.freshness) { settleSetupIfLive() }
        .onAppear { settleSetupIfLive() }
    }

    /// Label + plan pill. The label is the account's identity — 11.5pt semibold in
    /// secondary ink so it frames the meters without competing with the numerals.
    private var identityRow: some View {
        HStack(spacing: 6) {
            Text(account.label)
                .font(.system(size: 11.5, weight: .semibold))
                .kerning(0.1)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if let plan = snapshot.planLabel, !plan.isEmpty {
                Text(plan.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(ClaudeSetupStyle.stepBackground(dark: scheme == .dark), in: Capsule())
            }
            Spacer(minLength: 6)
            if case .stale(let reason) = snapshot.freshness, !reason.isPermanent {
                staleTag
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityIdentity)
    }

    private var accessibilityIdentity: String {
        var parts = ["\(account.label) account"]
        if let plan = snapshot.planLabel, !plan.isEmpty { parts.append("\(plan) plan") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var stateContent: some View {
        Group {
            switch snapshot.freshness {
            case .pending:
                accountSkeleton
            case .live:
                bars(dimmed: false)
            case .stale(let reason):
                if reason.isPermanent {
                    signInContent(reason)
                } else {
                    bars(dimmed: true)
                }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private func bars(dimmed: Bool) -> some View {
        if snapshot.windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: compact ? 7 : 9) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(
                        window: window,
                        percentageMode: percentageMode,
                        now: now,
                        dimmed: dimmed,
                        compact: compact
                    )
                }
            }
        }
    }

    /// Permanent failure on one account: a single compact row — the reason, then the
    /// Terminal handoff — so one dead login never dominates its healthy siblings.
    /// While the handoff Terminal is open it becomes a quiet waiting row with a
    /// real-progress spinner (bound to the retry cycle, not decorative).
    @ViewBuilder private func signInContent(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if isWaitingForSetup {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Waiting for sign-in…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Button("Check now") { onRetrySetup() }
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 3))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(ClaudeSetupStyle.accentText(dark: scheme == .dark))
                }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ProviderStyle.severityColor(for: .low, scheme: scheme))
                    Text(reason.message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button {
                        openSetup()
                    } label: {
                        Label("Sign in", systemImage: "terminal")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(SetupChipButtonStyle())
                    .accessibilityLabel("Sign in to \(account.label)")
                }
            }
            if !snapshot.windows.isEmpty {
                bars(dimmed: true)
            }
        }
    }

    private var staleTag: some View {
        Text("Stale")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.secondary.opacity(0.18), in: Capsule())
    }

    private var isWaitingForSetup: Bool {
        switch providerID {
        case .claude: ClaudeSetupSession.openedSetupAt(for: account.id) != nil
        case .codex: CodexSetupSession.openedSetupAt(for: account.id) != nil
        default: false
        }
    }

    private func openSetup() {
        switch providerID {
        case .claude: ClaudeSetupSession.openSetup(for: account, onRetry: onRetrySetup)
        case .codex: CodexSetupSession.openSetup(for: account, onRetry: onRetrySetup)
        default: break
        }
    }

    /// An account going live ends its handoff session and pending retries so the
    /// waiting row doesn't keep spinning (and retrying) after success.
    private func settleSetupIfLive() {
        guard case .live = snapshot.freshness else { return }
        switch providerID {
        case .claude:
            if ClaudeSetupSession.openedSetupAt(for: account.id) != nil {
                ClaudeSetupSession.cancelRetries(for: account.id)
                ClaudeSetupSession.setOpenedSetupAt(nil, for: account.id)
            }
        case .codex:
            if CodexSetupSession.openedSetupAt(for: account.id) != nil {
                CodexSetupSession.cancelRetries(for: account.id)
                CodexSetupSession.setOpenedSetupAt(nil, for: account.id)
            }
        default: break
        }
    }

    private var accountSkeleton: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                RoundedRectangle(cornerRadius: 4).fill(ProviderStyle.barTrack(scheme: scheme)).frame(width: 72, height: compact ? 11 : 13)
                Spacer(minLength: 6)
                RoundedRectangle(cornerRadius: 4).fill(ProviderStyle.barTrack(scheme: scheme)).frame(width: 38, height: compact ? 11 : 13)
            }
            Capsule().fill(ProviderStyle.barTrack(scheme: scheme)).frame(height: compact ? 6 : 8)
        }
    }
}

// MARK: - Shared command recovery row

/// Compact copyable command row shared by the single-account actionable state.
private struct CommandRecoveryRow: View {
    let command: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            Text("$ \(command)")
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button(action: copy) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(HoverButtonStyle(horizontalPadding: 4, verticalPadding: 4))
            .foregroundStyle(.secondary)
            .help("Copy command")
            .accessibilityLabel("Copy command")
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(ClaudeSetupStyle.codeBackground(dark: scheme == .dark), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
