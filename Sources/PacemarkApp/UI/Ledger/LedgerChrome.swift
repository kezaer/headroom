#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif
import SwiftUI
import AppKit
import PacemarkCore
#if SWIFT_PACKAGE
import PacemarkSharedUI
#endif

struct LedgerHeader: View {
    let status: PopoverHeaderStatus?
    let live: Int
    let waitingStart: Date?
    let refreshing: Bool
    let refresh: () -> Void
    let settings: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.loadingDate) private var pinnedDate

    var body: some View {
        HStack(spacing: PDS.Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: PDS.Space.s) {
                SettingsAppIcon(size: PDS.Metrics.headerMark, header: true)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions.height / 2 + NSFont.systemFont(ofSize: 13, weight: .semibold).capHeight / 2
                    }
                Text("Pacemark").font(PopoverLedgerType.header).kerning(-0.1)
                    .anchorPreference(key: PopoverHeaderTitleAnchorKey.self, value: .bounds) { $0 }
            }
            statusChip("\(live) live", isLive: live > 0).fixedSize()
            if let waitingStart {
                TimelineView(.periodic(from: waitingStart, by: 1)) { tick in
                    let elapsed = max(0, (pinnedDate ?? tick.date).timeIntervalSince(waitingStart))
                    statusChip("Waiting · \(LedgerStatusClock.text(elapsed))", isLive: false)
                        .accessibilityLabel(PopoverHeaderStatusText.waiting(elapsed: elapsed))
                }
            } else if let status {
                statusChip(status.text, isLive: false)
            }
            Spacer(minLength: 0)
            LedgerIconButton(icon: "arrow.clockwise", title: "Refresh", action: refresh)
                .disabled(refreshing)
                .keyboardShortcut("r", modifiers: .command)
            LedgerIconButton(icon: "gearshape", title: "Settings", action: settings)
                .keyboardShortcut(",", modifiers: .command)
        }
        .frame(height: LedgerMetrics.headerHeight)
    }

    private func statusChip(_ text: String, isLive: Bool) -> some View {
        HStack(spacing: PDS.Space.xs) {
            Circle().fill(isLive
                ? Color(nsColor: MenuBarPalette(isDarkMenuBar: scheme == .dark).liquid(for: .healthy).menuBarColor)
                : Color.secondary)
                .frame(width: 5, height: 5)
            Text(text).font(PopoverLedgerType.unit).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, PDS.Space.xs)
        .frame(height: 18)
        .background(.primary.opacity(isLive ? 0.06 : 0), in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(isLive ? 0 : 0.12)) }
    }
}

struct LedgerFooter: View {
    let store: UsageStore
    let freshness: PopoverHeaderStatus
    let staleCount: Int
    var openMenuBarSettings: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let run = store.userRefreshRun
        let work = store.visibleRefreshWork
        let holdEnd = work.clearedAt?.addingTimeInterval(LoadingMotionConstants.endHoldDuration)
        let titles = run?.entries.keys.reduce(into: [AccountKey: String]()) {
            $0[$1] = store.refreshReceiptTitle(for: $1)
        } ?? [:]

        HStack(spacing: PDS.Space.xs) {
            LoadingTimeline(active: false, until: holdEnd, interval: 1 / 4) { date in
                let resting = !work.isInFlight && !(holdEnd.map { date < $0 } ?? false)
                let receipt = RefreshReceiptPresentation.line(run: run, isResting: resting, now: date) { titles[$0] ?? "" }
                let stale = staleCount > 0 ? " · \(staleCount) stale" : ""
                let text = if let receipt {
                    receipt.count.map { "Refreshing · \($0)" } ?? receipt.text
                } else if work.isInFlight && !resting {
                    "Refreshing…"
                } else {
                    (freshness.kind == .updated ? "Updated " + freshness.text.lowercased() : freshness.text) + stale
                }
                Text(text)
                    .font(PopoverLedgerType.sentence).monospacedDigit()
                    .foregroundStyle(ProviderStyle.tertiaryText(scheme: scheme))
                    .lineLimit(1)
                    .pdsHoverTip(text)
            }
            Spacer(minLength: 0)
            // T3 fork: temporary shortcut to Settings › Menu Bar meter style.
            LedgerIconButton(icon: "slider.horizontal.3", title: "Menu Bar Settings", action: openMenuBarSettings)
            LedgerIconButton(icon: "power", title: "Quit Pacemark") { NSApp.terminate(nil) }
        }
        .frame(height: LedgerMetrics.footerHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(.primary.opacity(0.09)).frame(height: 0.5)
                .padding(.horizontal, -LedgerMetrics.margin)
        }
        .padding(.top, PDS.Space.xs)
    }
}

private struct LedgerIconButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(PDS.Typography.rowTitle)
                .foregroundStyle(PDS.Ink.inkSecondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(HoverButtonStyle(horizontalPadding: 0, verticalPadding: 0))
        .pdsHoverTip(title)
        .accessibilityLabel(title)
    }
}

struct LedgerSurfaceGlow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            let tint = PacemarkColorValues.containerBackgroundGlow(dark: scheme == .dark)
            GeometryReader { proxy in
                RadialGradient(colors: [Color(nsColor: tint.menuBarColor), .clear],
                               center: .top, startRadius: 0, endRadius: max(proxy.size.height * 0.60, 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: LedgerMetrics.corner, style: .continuous))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct LedgerEmptyTile: View {
    let settings: () -> Void

    var body: some View {
        VStack(spacing: PDS.Space.s) {
            Text("No subscriptions are being read").font(PopoverLedgerType.name)
            Button("Open Settings", action: settings).buttonStyle(SetupChipButtonStyle(size: .small))
        }
        .frame(maxWidth: .infinity)
        .padding(PDS.Space.m)
        .modifier(PDSCardSurface())
    }
}
