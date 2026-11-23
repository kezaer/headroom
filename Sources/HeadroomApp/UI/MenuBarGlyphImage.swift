import AppKit
import HeadroomCore

@MainActor
enum MenuBarGlyphImage {
    static func image(
        for meter: MenuBarMeter, palette: MenuBarPalette, presentation: MenuBarSlosh.Presentation
    ) -> NSImage {
        VesselGlyph.menuBarImage(
            fill: meter.fill, severity: meter.summary.severity, isNeutral: meter.summary.isNeutral,
            palette: palette, wavePhase: presentation.wavePhase, ink: presentation.ink, kind: meter.glyph
        )
    }
}
