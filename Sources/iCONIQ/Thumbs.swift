import AppKit
import ImageIO
import iCONIQCore

/// Aperçus d'icônes : rendus hors du fil principal, gardés en mémoire et sur disque (Cache/thumbs/<côté>/<id>.png).
final class Thumbs: @unchecked Sendable {
    static let shared = Thumbs()
    private let mem = NSCache<NSString, NSImage>()
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 6; q.qualityOfService = .userInitiated; return q
    }()

    init() { mem.countLimit = 4000 }

    func image(for icon: Icon, lib: Library, side: Int) async -> NSImage? {
        let key = "\(icon.id)-\(side)-\(icon.file)" as NSString
        if let m = mem.object(forKey: key) { return m }
        let url = lib.fileURL(icon)
        let disk = lib.cacheDir.appendingPathComponent("thumbs/\(side)/\(icon.id).png")
        return await withCheckedContinuation { cont in
            queue.addOperation { [mem] in
                if let img = NSImage(contentsOf: disk), (try? disk.checkResourceIsReachable()) == true {
                    mem.setObject(img, forKey: key); cont.resume(returning: img); return
                }
                guard let img = Self.render(url: url, fmt: icon.fmt, px: side) else { cont.resume(returning: nil); return }
                mem.setObject(img, forKey: key)
                try? FileManager.default.createDirectory(at: disk.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let rep = img.representations.first as? NSBitmapImageRep, let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: disk) }
                cont.resume(returning: img)
            }
        }
    }

    func forget() { mem.removeAllObjects() }

    /// Rendu carré de `px` pixels, l'icône tenant dans le carré.
    static func render(url: URL, fmt: String, px: Int) -> NSImage? {
        if fmt != "svg" && fmt != "pdf", let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
            // icns : la plus grande représentation
            func width(_ i: Int) -> Int { ((CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int) ?? 0 }
            let best = (0..<CGImageSourceGetCount(src)).max { width($0) < width($1) } ?? 0
            let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: px]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, best, opts as CFDictionary) else { return nil }
            return bitmap(px: px) { ctx in
                let r = fit(CGSize(width: cg.width, height: cg.height), in: px)
                ctx.cgContext.interpolationQuality = .high
                ctx.cgContext.draw(cg, in: r)
            }
        }
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
        return bitmap(px: px) { _ in img.draw(in: fit(img.size, in: px), from: .zero, operation: .sourceOver, fraction: 1) }
    }

    private static func fit(_ s: CGSize, in px: Int) -> CGRect {
        let k = min(CGFloat(px) / s.width, CGFloat(px) / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h)
    }

    private static func bitmap(px: Int, draw: (NSGraphicsContext) -> Void) -> NSImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw(ctx)
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: px, height: px))
        img.addRepresentation(rep)
        return img
    }
}

/// Export et copie d'icônes.
enum IconExport {
    static func png(_ icon: Icon, lib: Library, side: Int) -> Data? {
        guard let img = Thumbs.render(url: lib.fileURL(icon), fmt: icon.fmt, px: side), let rep = img.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Copie l'image, pas le fichier : « Lire les informations » du Finder, Aperçu, Figma… collent l'image comme icône.
    /// Types déposés : TIFF, PNG, SVG ou ICNS d'origine selon le format.
    @MainActor
    static func copy(_ icon: Icon, lib: Library) {
        let url = lib.fileURL(icon)
        let native = max(icon.width, icon.height)
        let side = icon.fmt == "svg" || native <= 0 ? 1024 : min(1024, max(256, native))
        let pb = NSPasteboard.general
        pb.clearContents()
        if let img = Thumbs.render(url: url, fmt: icon.fmt, px: side) {
            pb.writeObjects([img])   // TIFF
            if let rep = img.representations.first as? NSBitmapImageRep, let png = rep.representation(using: .png, properties: [:]) { pb.setData(png, forType: .png) }
        }
        if let data = try? Data(contentsOf: url) {
            if icon.fmt == "svg" { pb.setData(data, forType: NSPasteboard.PasteboardType("public.svg-image")) }
            if icon.fmt == "icns" { pb.setData(data, forType: NSPasteboard.PasteboardType("com.apple.icns")) }
        }
        lib.touch([icon.id])
    }

    @MainActor
    static func copySVGCode(_ icon: Icon, lib: Library) {
        guard icon.fmt == "svg", let s = try? String(contentsOf: lib.fileURL(icon), encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        lib.touch([icon.id])
    }
}
