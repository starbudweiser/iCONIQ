// Dessine l'icône d'iCONIQ : quatre tuiles (trois en contour, une pleine violette) sur fond sombre, à plat (Socle).
// Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let violet = NSColor(srgbRed: 0x8b / 255, green: 0x5c / 255, blue: 0xf6 / 255, alpha: 1)
let background = NSColor(white: 0.118, alpha: 1)
guard CommandLine.arguments.count > 1,
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

// Gabarit macOS : carré arrondi de 824 px centré.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
cg.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
cg.setFillColor(background.cgColor)
cg.fillPath()

let cell: CGFloat = 214, gap: CGFloat = 36, radius: CGFloat = 52, stroke: CGFloat = 26
for (i, (dx, dy)) in [(-1.0, 1.0), (1.0, 1.0), (-1.0, -1.0), (1.0, -1.0)].enumerated() {
    let x = size / 2 + (dx > 0 ? gap / 2 : -gap / 2 - cell)
    let y = size / 2 + (dy > 0 ? gap / 2 : -gap / 2 - cell)
    let r = CGRect(x: x, y: y, width: cell, height: cell)
    if i == 3 {
        cg.setFillColor(violet.cgColor)
        cg.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        cg.fillPath()
    } else {
        cg.setStrokeColor(NSColor.white.cgColor)
        cg.setLineWidth(stroke)
        cg.addPath(CGPath(roundedRect: r.insetBy(dx: stroke / 2, dy: stroke / 2), cornerWidth: radius - 8, cornerHeight: radius - 8, transform: nil))
        cg.strokePath()
    }
}

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
