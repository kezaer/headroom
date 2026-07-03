import SwiftUI
import AppKit
import HeadroomCore

/// One provider's card (U7). Renders the four explicit states from the design review
/// off `snapshot.freshness`: `.pending` first-run skeleton, `.live`, transient stale
/// (last data kept, marked with a "Stale" pill), and permanent needs-reauth/scope (an
/// actionable message with a one-tap command to copy). Shows the plan-renewal date or a
/// tappable "add date" affordance.
///
/// UI craft (audit): the card is a single lighter translucent layer instead of a second
/// `.regularMaterial` stacked on the popover's glass, so Tahoe's Liquid Glass reads
/// cleanly rather than muddying (UI-07).
struct ProviderCardView: View {
    let providerID: ProviderID
    let displayName: String
    let snapshot: UsageSnapshot
    let renewalDate: Date?
    let now: Date
    let onOpenSettings: () -> Void

    private var accent: Color { ProviderStyle.accent(for: providerID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            renewalRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            ProviderLogoView(providerID: providerID, size: 17)
            Text(displayName).font(.headline)
            if let plan = snapshot.planLabel {
                Text(plan.capitalized)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.18), in: Capsule())
            }
            Spacer(minLength: 6)
            if let updated = Countdown.updatedLabel(capturedAt: snapshot.capturedAt, now: now) {
                Text("Updated \(updated)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch snapshot.freshness {
        case .pending:
            pendingSkeleton
        case .live:
            bars(dimmed: false)
        case .stale(let reason):
            staleContent(reason)
        }
    }

    @ViewBuilder private func staleContent(_ reason: FailureReason) -> some View {
        if reason.isPermanent {
            actionable(reason)
            if !snapshot.windows.isEmpty { bars(dimmed: true) }
        } else {
            bars(dimmed: true)
            stalePill(reason)
        }
    }

    @ViewBuilder private func bars(dimmed: Bool) -> some View {
        if snapshot.windows.isEmpty {
            Text("No usage data").font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    UsageBarView(window: window, now: now, dimmed: dimmed)
                }
            }
        }
    }

    /// Varied widths (audit UI-13): real content isn't two identical bars, so the
    /// skeleton previews the true shape rather than reading as "broken". The wait names
    /// the ~20–30s first Claude poll so the delay feels intentional, not hung.
    private var pendingSkeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 150, height: 6)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 7)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 96, height: 6)
            Text("Fetching usage…")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// Permanent failure the user can fix (UI-05): name the remedy and give a one-tap
    /// copy of the exact CLI command, instead of a dead-end sentence.
    @ViewBuilder private func actionable(_ reason: FailureReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(reason.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            if let command = reauthCommand {
                HStack(spacing: 8) {
                    Text("$ \(command)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                    Spacer(minLength: 6)
                    Button("Copy", action: copyCommand)
                        .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 2))
                        .font(.caption2)
                        .foregroundStyle(accent)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    private var renewalRow: some View {
        HStack {
            Text("Plan renews").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            if let renewalDate {
                Text(renewalDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("Add date", action: onOpenSettings)
                    .buttonStyle(HoverButtonStyle(horizontalPadding: 6, verticalPadding: 2))
                    .font(.caption2)
                    .foregroundStyle(accent)
            }
        }
    }

    /// The CLI command that re-authenticates each provider (nil for unknown providers).
    private var reauthCommand: String? {
        switch providerID {
        case .claude: return "claude"
        case .codex: return "codex login"
        default: return nil
        }
    }

    private func copyCommand() {
        guard let command = reauthCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
