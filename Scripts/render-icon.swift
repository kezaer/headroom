// AppKit fallback for generate-app-icon.sh on a Mac without librsvg.
import AppKit

let arguments = CommandLine.arguments
let artwork = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
let alpha = !arguments[1].hasSuffix("/ios.svg")
for argument in arguments.dropFirst(3) {
    guard let size = Int(argument),
          let svg = String(data: artwork, encoding: .utf8),
          let image = NSImage(data: Data(svg.replacingOccurrences(
            of: "<svg ", with: "<svg width=\"\(size)\" height=\"\(size)\" "
          ).utf8)),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                        bitsPerSample: 8, samplesPerPixel: alpha ? 4 : 3, hasAlpha: alpha, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: "\(arguments[2])_\(size).png"))
}
