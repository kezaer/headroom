import AppKit
import PacemarkCore

/// The original vessel mark used in the Ledger header.
enum VesselGlyph {
    @MainActor static func image(palette: MenuBarPalette) -> NSImage {
        // Keep the same proportions as the small Pacemark mark.
        let size = NSSize(width: 11, height: 18)
        let wallWidth: CGFloat = 1.6
        return NSImage(size: size, flipped: false) { bounds in
            let wallRect = bounds.insetBy(dx: wallWidth / 2, dy: wallWidth / 2)
            let wall = NSBezierPath(roundedRect: wallRect, xRadius: wallRect.width / 2, yRadius: wallRect.width / 2)
            wall.lineWidth = wallWidth
            palette.ink.menuBarColor.setStroke()
            wall.stroke()

            NSGraphicsContext.saveGraphicsState()
            let inner = bounds.insetBy(dx: wallWidth + 0.6, dy: wallWidth + 0.6)
            NSBezierPath(roundedRect: inner, xRadius: inner.width / 2, yRadius: inner.width / 2).addClip()
            palette.liquid(for: .healthy).menuBarColor.setFill()
            NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * 0.35).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
}
