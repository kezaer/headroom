import Foundation
import Testing
@testable import HeadroomCore

struct MirrorPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func liveFreshnessUsesNormalTreatment() {
        let treatment = MirrorPresentation.treatment(for: .live)

        #expect(treatment == .normal)
        #expect(treatment.isDimmed == false)
        #expect(treatment.pillText == nil)
        #expect(treatment.noticeText == nil)
    }

    @Test func transientStaleFreshnessDimsWithStalePill() {
        let treatment = MirrorPresentation.treatment(
            for: .stale(message: "Using last snapshot", needsAttention: false)
        )

        #expect(treatment == .stale)
        #expect(treatment.isDimmed)
        #expect(treatment.pillText == "Stale")
        #expect(treatment.noticeText == nil)
    }

    @Test func attentionStaleFreshnessPointsBackToMacWithoutCLIText() {
        let treatment = MirrorPresentation.treatment(
            for: .stale(message: "Authentication expired", needsAttention: true)
        )

        #expect(treatment.isDimmed)
        #expect(treatment.pillText == nil)
        #expect(treatment.noticeText == "Sign in again on your Mac")
        #expect(treatment.noticeText?.contains("$") == false)
        #expect(treatment.noticeText?.localizedStandardContains("claude") == false)
    }

    @Test func pendingFreshnessUsesSkeletonTreatment() {
        let treatment = MirrorPresentation.treatment(for: .pending)

        #expect(treatment == .skeleton)
        #expect(treatment.isDimmed)
    }

    @Test func resetTextUsesSharedSemanticCopyInsteadOfSourceLabel() {
        let window = window(
            resetLabel: "Resets 2:00 PM",
            resetsAt: now.addingTimeInterval(2 * 3600)
        )

        #expect(MirrorPresentation.resetText(for: window, now: now) == "Resets in 2h")
    }

    @Test func resetTextComputesFallbackCountdown() {
        let future = window(resetLabel: nil, resetsAt: now.addingTimeInterval(4 * 3600 + 59 * 60))
        let past = window(resetLabel: nil, resetsAt: now.addingTimeInterval(-10))

        #expect(MirrorPresentation.resetText(for: future, now: now) == "Resets in 4h 59m")
        #expect(MirrorPresentation.resetText(for: past, now: now) == "Resets now")
    }

    @Test func updatedLabelWrapsCountdown() {
        #expect(MirrorPresentation.updatedLabel(generatedAt: nil, now: now) == nil)
        #expect(MirrorPresentation.updatedLabel(generatedAt: now, now: now) == "just now")
        #expect(MirrorPresentation.updatedLabel(generatedAt: now.addingTimeInterval(-300), now: now) == "5 min ago")
    }

    @Test func lowChipOnlyShowsForCriticalNonDimmedWindows() {
        #expect(MirrorPresentation.showsLowChip(severity: .critical, dimmed: false))
        #expect(MirrorPresentation.showsLowChip(severity: .critical, dimmed: true) == false)
        #expect(MirrorPresentation.showsLowChip(severity: .low, dimmed: false) == false)
        #expect(MirrorPresentation.showsLowChip(severity: .healthy, dimmed: false) == false)
    }

    @Test func companionRendersEveryWindowRetainedByTheProjector() {
        let fable = WidgetWindowSummary(
            kind: .other("Weekly (Fable)"),
            label: "Weekly (Fable)",
            percentRemaining: 54,
            resetsAt: now,
            resetLabel: "Resets Jul 9",
            severity: .healthy
        )
        let provider = WidgetProviderSummary(
            id: "claude",
            displayName: "Claude",
            planLabel: "Max",
            freshness: .live,
            windows: [window(resetLabel: nil), fable],
            renewalDate: nil
        )

        #expect(MirrorPresentation.windows(for: provider).map(\.label) == ["Session", "Weekly (Fable)"])
    }

    @Test func unavailableWindowHidesPercentageAndUsesUnavailableResetCopy() {
        let unavailable = WidgetWindowSummary(
            kind: .other("Weekly (Fable)"),
            label: "Weekly (Fable)",
            percentRemaining: 54,
            resetsAt: now,
            resetLabel: "Resets Jul 9",
            severity: .healthy,
            freshness: .unavailable(since: now.addingTimeInterval(-60))
        )

        #expect(unavailable.displayPercentRemaining == nil)
        #expect(MirrorPresentation.resetText(for: unavailable, now: now) == "Unavailable")
    }

    private func window(
        resetLabel: String?,
        resetsAt: Date? = nil,
        severity: WidgetUsageSeverity = .healthy
    ) -> WidgetWindowSummary {
        WidgetWindowSummary(
            kind: .fiveHour,
            label: "Session",
            percentRemaining: 42,
            resetsAt: resetsAt ?? now,
            resetLabel: resetLabel,
            severity: severity
        )
    }
}
