import SwiftUI
import AppKit
import HeadroomCore

/// Provider brand mark used at small UI sizes. Bundled SVGs render through AppKit;
/// SF Symbols remain the fallback for unknown providers.
struct ProviderLogoView: View {
    let providerID: ProviderID
    var size: CGFloat = 16

    var body: some View {
        // Per-provider optical-size correction inside a fixed slot (shared with iOS via
        // HeadroomCore), so Claude's edge-to-edge starburst and Codex's inset blob read as
        // equal weight across every surface.
        let scale = CGFloat(HeadroomBrandMark.opticalScale(for: providerID.raw))
        if let image = BrandIconImage.image(for: providerID) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: size * scale, height: size * scale)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: ProviderStyle.symbol(for: providerID))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(ProviderStyle.accent(for: providerID))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

private enum BrandIconImage {
    static func image(for providerID: ProviderID) -> NSImage? {
        guard let name = ProviderStyle.svgResourceName(for: providerID),
              let url = url(forResource: name),
              let svg = NSImage(contentsOf: url) else {
            return nil
        }
        // The brand SVGs are a 10pt viewBox. `ImageRenderer` (the marketing hero export)
        // rasterizes nested images at their intrinsic size and upscales — blurring a 10pt
        // mark ~8×. Bake a high-res bitmap once so the offscreen export stays crisp; the
        // live app draws this `.resizable()` and downsamples cleanly, so it's unaffected.
        let hi = NSImage(size: NSSize(width: 256, height: 256))
        hi.lockFocus()
        svg.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
        hi.unlockFocus()
        return hi
    }

    private static func url(forResource name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "svg") {
            return url
        }
        let swiftPMBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Headroom_HeadroomApp.bundle")
        return Bundle(url: swiftPMBundleURL)?
            .url(forResource: name, withExtension: "svg")
    }
}
