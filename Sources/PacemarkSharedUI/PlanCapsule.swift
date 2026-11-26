#if SWIFT_PACKAGE
import PacemarkCore
#elseif canImport(PacemarkCore)
import PacemarkCore
#endif
import SwiftUI

/// Plan pill with an optional banked-reset bead. Hover, Critical, and the first-show
/// reveal all resolve in `PlanCapsulePresentation`; this view only paints that result.
public struct PlanCapsule: View {
    public let planDisplayName: String?
    public let bankedResets: Int?
    public let isCritical: Bool
    public let isRevealing: Bool
    public var scale: CGFloat = 1

    public init(
        planDisplayName: String?,
        bankedResets: Int?,
        isCritical: Bool,
        isRevealing: Bool,
        scale: CGFloat = 1
    ) {
        self.planDisplayName = planDisplayName
        self.bankedResets = bankedResets
        self.isCritical = isCritical
        self.isRevealing = isRevealing
        self.scale = scale
    }

    @State private var isHovering = false
    /// Stays true for the frame that leaves Critical or reveal, so that close uses
    /// `settle` rather than the hover-out curve (KTD8).
    @State private var lastWasAttention = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        let presentation = PlanCapsulePresentation.resolve(
            planDisplayName: planDisplayName,
            bankedResets: bankedResets,
            isHovering: isHovering,
            isCritical: isCritical,
            isRevealing: isRevealing
        )
        HStack(spacing: PDS.Space.xs * scale) {
            if !presentation.planText.isEmpty {
                Text(presentation.planText)
                    .kerning(IdentityRowMetrics.capsuleLabelKerning * scale)
            }
            if presentation.showsBead {
                Circle()
                    .fill(ProviderStyle.planLabelInk(scheme: scheme))
                    .frame(width: 4 * scale, height: 4 * scale)
                    .accessibilityHidden(true)
            } else if let detail = presentation.detail {
                Text(presentation.planText.isEmpty ? detail : "· \(detail)")
                    .kerning(IdentityRowMetrics.capsuleLabelKerning * scale)
            }
        }
        .foregroundStyle(ProviderStyle.planLabelInk(scheme: scheme))
        .identityMetadataLabel(scale: scale)
        .onHover { isHovering = $0 }
        .animation(resolved(animation, .crossfade), value: presentation.visibleLabel)
        .animation(resolved(animation, .movement), value: presentation.state)
        .onChange(of: isCritical || isRevealing) { _, active in
            lastWasAttention = active
        }
    }

    private var animation: Animation {
        if isCritical || isRevealing { return PacemarkMotion.valueSpring }
        if lastWasAttention && !isHovering { return PacemarkMotion.settle }
        return isHovering ? PacemarkMotion.hoverIn : PacemarkMotion.hoverOut
    }

    private func resolved(_ animation: Animation, _ kind: PacemarkMotion.Kind) -> Animation? {
        PacemarkMotion.resolved(animation, kind, reduceMotion: reduceMotion)
    }
}
