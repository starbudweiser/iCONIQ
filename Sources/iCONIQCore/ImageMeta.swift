import Foundation
import ImageIO

public enum ImageMeta {
    /// Format d'après les octets (signature), sinon d'après l'extension / le type MIME.
    public static func sniff(_ data: Data, hint: String? = nil) -> String? {
        let b = [UInt8](data.prefix(16))
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if b.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if b.count >= 12, b[0...3] == [0x52, 0x49, 0x46, 0x46], b[8...11] == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        if b.starts(with: [0x69, 0x63, 0x6E, 0x73]) { return "icns" }
        if b.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "pdf" }
        if b.starts(with: [0x00, 0x00, 0x01, 0x00]) { return "ico" }
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        if head.contains("<svg") { return "svg" }
        guard let h = hint?.lowercased() else { return nil }
        for (k, v) in [("svg", "svg"), ("png", "png"), ("jpeg", "jpg"), ("jpg", "jpg"), ("gif", "gif"), ("webp", "webp"), ("icns", "icns"), ("pdf", "pdf"), ("icon", "ico"), ("ico", "ico")] where h.contains(k) { return v }
        return nil
    }

    public static let supported: Set<String> = ["svg", "png", "jpg", "jpeg", "gif", "webp", "icns", "pdf", "ico", "tiff", "heic"]

    public static func size(data: Data, fmt: String) -> (width: Int, height: Int) {
        if fmt == "svg" { return svgSize(String(decoding: data.prefix(4096), as: UTF8.self)) }
        guard fmt != "pdf", let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return ((p[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p[kCGImagePropertyPixelHeight] as? Int) ?? 0)
    }

    static func svgSize(_ head: String) -> (Int, Int) {
        func attr(_ n: String) -> Double? {
            guard let r = head.range(of: "\\b\(n)=\"([0-9.]+)", options: .regularExpression) else { return nil }
            return Double(head[r].drop { !$0.isNumber })
        }
        if let w = attr("width"), let h = attr("height") { return (Int(w), Int(h)) }
        if let r = head.range(of: "viewBox=\"([^\"]+)\"", options: .regularExpression) {
            let p = head[r].dropFirst(9).dropLast().split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            if p.count == 4 { return (Int(p[2]), Int(p[3])) }
        }
        return (0, 0)
    }
}
