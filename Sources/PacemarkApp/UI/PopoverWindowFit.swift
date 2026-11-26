import AppKit
import SwiftUI

/// SQ1 (macOS 15.0 report, 2026-10-11: "The header 'Usage' is clipped"): the popover's root.
/// A hosting view centres content that is taller than it, so a `MenuBarExtra` window shorter
/// than the popover cut the header and the footer by the same amount.
///
/// The root still answers the content's ideal size for every proposal, so the host sizes and
/// grows its window exactly as before. (A hosting view grows its window from the size its root
/// answers at the current bounds; answering the window's own height there stopped it growing, and
/// the column sizing tests caught it.) What changes is placement. In a window shorter than the
/// content (the proposal), the content is laid out at the window's height in a box centred on
/// this root's centre. The host centres this root in the window, so that box is the window: the
/// header sits at its top, and the card list (the one flexible piece) gives up the difference, so
/// the footer stays too. At or above the ideal height nothing moves.
struct PopoverTopPinnedLayout: Layout {
    /// The content's ideal height, reported from inside layout as it is placed. Only the
    /// window fitter reads it, and it acts on the next main turn, never during the pass.
    var reportIdealHeight: (@Sendable (CGFloat) -> Void)?
    /// The space below the status item, expressed in hosting-view points.
    var maximumContentHeight: CGFloat?

    /// The content's ideal height at the proposed width: what the fixed-height popover answered
    /// for every proposal before its card list could give up height.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: ideal.width, height: Self.visibleHeight(proposed: maximumContentHeight, ideal: ideal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let visible = Self.visibleHeight(proposed: proposal.height, ideal: bounds.height)
        content.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY - visible / 2),
            anchor: .top,
            proposal: ProposedViewSize(width: bounds.width, height: visible)
        )
        if let reportIdealHeight {
            // At the screen limit, keep the uncapped ideal available for the next column plan.
            let ideal = maximumContentHeight.map { bounds.height >= $0 } == true
                ? content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
                : bounds.height
            reportIdealHeight(ideal)
        }
    }

    /// The window's height when it is a real one shorter than the content, else the content's.
    /// Zero (a minimum-size probe) and infinity mean no window, so they keep the content's height.
    static func visibleHeight(proposed: CGFloat?, ideal: CGFloat) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 0, proposed < ideal else { return ideal }
        return proposed
    }
}

/// Fits the height with the top edge under the status item. Sequoia uses this for every layout.
/// Ledger also uses it on later systems because the open MenuBarExtra can keep its old frame
/// after disclosure changes the content's ideal height.
@MainActor
final class PopoverWindowHeightFitter {
    weak var window: NSWindow?
    /// A view inside the popover's hosting view (the window accessor), so the fit can count
    /// whatever the window wraps around that hosting view.
    weak var anchor: NSView?
    private var idealHeight: CGFloat?
    private var fitScheduled = false

    /// Heights reported during layout are acted on after the pass.
    func report(_ height: CGFloat, fitsLive: Bool = false) {
        if let idealHeight, abs(idealHeight - height) <= Self.tolerance { return }
        idealHeight = height
        scheduleFit(fitsLive: fitsLive)
    }

    /// The window just resolved or the popover opened: fit it to the last height reported.
    func scheduleFit(fitsLive: Bool = false) {
        guard (fitsLive || Self.isEnabled), !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fitScheduled = false
            if let idealHeight { fit(to: idealHeight) }
        }
    }

    func fitWhenClosed(adjustingBy adjustment: CGFloat) {
        guard let idealHeight, let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window, !window.isVisible else { return }
            fit(to: idealHeight + adjustment)
        }
    }

    func availableContentHeight() -> CGFloat? {
        guard let window, let bottom = visibleBottom(under: window) else { return nil }
        let height = window.frame.maxY - bottom - chromeHeight(in: window)
        return height > 0 ? height : nil
    }

    private func fit(to idealHeight: CGFloat) {
        guard let window else { return }
        let target = idealHeight + chromeHeight(in: window)
        guard let frame = Self.fittedFrame(current: window.frame, targetHeight: target, bottomLimit: visibleBottom(under: window))
        else { return }
        window.setFrame(frame, display: window.isVisible)
        window.invalidateShadow()
    }

    private func chromeHeight(in window: NSWindow) -> CGFloat {
        let host = anchor.flatMap(Self.outermostHostingView(containing:)) ?? window.contentView
        return Self.windowHeight(
            forContent: 0,
            windowHeight: window.frame.height,
            hostHeight: host?.bounds.height ?? window.frame.height,
            hostSafeArea: host.map { $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } ?? 0
        )
    }

    private func visibleBottom(under window: NSWindow) -> CGFloat? {
        Self.visibleBottom(
            under: window.frame,
            screens: NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) },
            fallback: window.screen?.visibleFrame
        )
    }

    nonisolated static let tolerance: CGFloat = 0.5

    /// The window height that gives the popover `content` points: the content plus whatever the
    /// window keeps outside the hosting view (a title bar or top inset, the brief's H2) and any
    /// safe area the hosting view keeps the content out of. A host taller than its window adds
    /// nothing.
    nonisolated static func windowHeight(
        forContent content: CGFloat, windowHeight: CGFloat, hostHeight: CGFloat, hostSafeArea: CGFloat = 0
    ) -> CGFloat {
        content + max(windowHeight - hostHeight, 0) + max(hostSafeArea, 0)
    }

    nonisolated static func visibleBottom(
        under frame: NSRect, screens: [(frame: NSRect, visible: NSRect)], fallback: NSRect?
    ) -> CGFloat? {
        visibleFrame(under: frame, screens: screens, fallback: fallback)?.minY
    }

    /// The visible frame of the screen the popover hangs from: the one holding the window's
    /// top-centre point (just inside it), not `NSWindow.screen`, which picks the screen with the
    /// largest overlap and so, with a display stacked below the menu-bar display, can be the
    /// lower one. `fallback` (the window's own screen) covers a top edge on no screen.
    nonisolated static func visibleFrame(
        under frame: NSRect, screens: [(frame: NSRect, visible: NSRect)], fallback: NSRect?
    ) -> NSRect? {
        let topCentre = NSPoint(x: frame.midX, y: frame.maxY - 1)
        return screens.first { $0.frame.contains(topCentre) }?.visible ?? fallback
    }

    /// The outermost hosting view above `anchor`: the one the host sized for the popover.
    static func outermostHostingView(containing anchor: NSView) -> NSView? {
        var found: NSView?
        var view: NSView? = anchor.superview
        while let current = view {
            if String(describing: type(of: current)).contains("HostingView") { found = current }
            view = current.superview
        }
        return found
    }

    /// `current` with its height changed to `targetHeight` and its top edge where it was, or nil
    /// when it is already within half a point. `bottomLimit` (the screen's visible bottom)
    /// keeps a tall popover above the Dock; the top-pinned layout scrolls what doesn't fit.
    nonisolated static func fittedFrame(current: NSRect, targetHeight: CGFloat, bottomLimit: CGFloat? = nil) -> NSRect? {
        var height = targetHeight
        if let bottomLimit, current.maxY - bottomLimit > 0 { height = min(height, current.maxY - bottomLimit) }
        guard height > 0, abs(current.height - height) > tolerance else { return nil }
        return NSRect(x: current.minX, y: current.maxY - height, width: current.width, height: height)
    }

    /// The macOS 15.0 report calls for automatic fitting of Standard and Compact too.
    static var isEnabled: Bool {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        if #unavailable(macOS 26.0) { return true }
        return false
    }

    #if DEBUG
    /// Exercises the macOS 15 path on 26: tests set it, and `PACEMARK_FORCE_POPOVER_HEIGHT_FIT=1`
    /// (or `0`) sets it for a debug `swift run`. Nil leaves it to the OS.
    static var debugOverride: Bool? = ProcessInfo.processInfo.environment["PACEMARK_FORCE_POPOVER_HEIGHT_FIT"]
        .map { $0 == "1" }
    #endif
}

/// SQ1: the header title's bounds. Only the hosting test reads it; nothing in the app does.
struct PopoverHeaderTitleAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
