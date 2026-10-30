import Foundation
import CoreGraphics

enum SVGError: LocalizedError {
    case unreadable, empty
    var errorDescription: String? {
        switch self {
        case .unreadable: return "SVG konnte nicht gelesen werden."
        case .empty: return "Keine schneidbaren Pfade gefunden."
        }
    }
}

/// Liefert Pfade in mm, y nach oben, Ursprung links unten.
enum SVGImporter {
    static func load(url: URL) throws -> [Polyline] {
        let doc = try XMLDocument(contentsOf: url, options: [.nodeLoadExternalEntitiesNever])
        guard let root = doc.rootElement() else { throw SVGError.unreadable }
        var out: [Polyline] = []
        walk(root, .identity, isRoot: true, &out)
        guard !out.isEmpty else { throw SVGError.empty }
        let flipped = out.applying(CGAffineTransform(scaleX: 1, y: -1))
        let b = flipped.bounds
        return flipped.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY))
    }

    private static let skipped: Set<String> = ["defs", "clipPath", "mask", "symbol", "marker",
                                               "pattern", "metadata", "style", "title", "desc", "text"]

    private static func walk(_ el: XMLElement, _ parent: CGAffineTransform, isRoot: Bool, _ out: inout [Polyline]) {
        let name = el.localName ?? el.name ?? ""
        var a: [String: String] = [:]
        for at in el.attributes ?? [] {
            if let k = at.localName ?? at.name { a[k] = at.stringValue ?? "" }
        }
        let style = (a["style"] ?? "").replacingOccurrences(of: " ", with: "")
        if skipped.contains(name) || a["display"] == "none" || style.contains("display:none") { return }

        let ctm = isRoot ? rootTransform(a) : parseTransform(a["transform"]).concatenating(parent)

        switch name {
        case "path":
            var pp = PathParser(ctm: ctm)
            out += pp.parse(a["d"] ?? "")
        case "rect":
            let x = v(a, "x"), y = v(a, "y"), w = v(a, "width"), h = v(a, "height")
            if w > 0 && h > 0 {
                let pts = [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), CGPoint(x: x + w, y: y + h),
                           CGPoint(x: x, y: y + h), CGPoint(x: x, y: y)]
                out.append(Polyline(points: pts.map { $0.applying(ctm) }, closed: true))
            }
        case "circle":
            let r = v(a, "r")
            ellipse(v(a, "cx"), v(a, "cy"), r, r, ctm, &out)
        case "ellipse":
            ellipse(v(a, "cx"), v(a, "cy"), v(a, "rx"), v(a, "ry"), ctm, &out)
        case "line":
            let pts = [CGPoint(x: v(a, "x1"), y: v(a, "y1")), CGPoint(x: v(a, "x2"), y: v(a, "y2"))]
            out.append(Polyline(points: pts.map { $0.applying(ctm) }, closed: false))
        case "polyline", "polygon":
            let n = (a["points"] ?? "").split(whereSeparator: { " ,\t\n\r".contains($0) }).compactMap { Double($0) }
            var pts = stride(from: 0, to: n.count - 1, by: 2).map { CGPoint(x: n[$0], y: n[$0 + 1]).applying(ctm) }
            if name == "polygon", let f = pts.first { pts.append(f) }
            if pts.count > 1 { out.append(Polyline(points: pts, closed: name == "polygon")) }
        default:
            break
        }

        for case let child as XMLElement in el.children ?? [] {
            walk(child, ctm, isRoot: false, &out)
        }
    }

    private static func v(_ a: [String: String], _ k: String) -> CGFloat {
        let s = (a[k] ?? "").replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)
        return CGFloat(Double(s) ?? 0)
    }

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
                                _ ctm: CGAffineTransform, _ out: inout [Polyline]) {
        guard rx > 0, ry > 0 else { return }
        let s = sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c))
        let n = max(24, min(720, Int(((rx + ry) * .pi * s / 0.5).rounded(.up))))
        var pts = (0..<n).map { k -> CGPoint in
            let t = 2 * CGFloat.pi * CGFloat(k) / CGFloat(n)
            return CGPoint(x: cx + rx * cos(t), y: cy + ry * sin(t)).applying(ctm)
        }
        pts.append(pts[0])
        out.append(Polyline(points: pts, closed: true))
    }

    private static func rootTransform(_ a: [String: String]) -> CGAffineTransform {
        let px: CGFloat = 25.4 / 96
        let vb = (a["viewBox"] ?? "").split(whereSeparator: { " ,".contains($0) })
            .compactMap { Double($0) }.map { CGFloat($0) }
        guard vb.count == 4, vb[2] > 0, vb[3] > 0 else { return CGAffineTransform(scaleX: px, y: px) }
        var sx = a["width"].flatMap(lengthMM).map { $0 / vb[2] }
        var sy = a["height"].flatMap(lengthMM).map { $0 / vb[3] }
        if sx == nil { sx = sy ?? px }
        if sy == nil { sy = sx }
        return CGAffineTransform(translationX: -vb[0], y: -vb[1])
            .concatenating(CGAffineTransform(scaleX: sx!, y: sy!))
    }

    private static func lengthMM(_ s: String) -> CGFloat? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let units: [(String, CGFloat)] = [("mm", 1), ("cm", 10), ("in", 25.4),
                                          ("pt", 25.4 / 72), ("pc", 25.4 / 6), ("px", 25.4 / 96)]
        for (u, f) in units where t.hasSuffix(u) {
            return Double(String(t.dropLast(u.count))).map { CGFloat($0) * f }
        }
        if t.hasSuffix("%") { return nil }
        return Double(t).map { CGFloat($0) * 25.4 / 96 }
    }

    static func parseTransform(_ s: String?) -> CGAffineTransform {
        guard let s, !s.isEmpty else { return .identity }
        let regex = try! NSRegularExpression(pattern: "(matrix|translate|scale|rotate|skewX|skewY)\\s*\\(([^)]*)\\)")
        let ns = s as NSString
        var result = CGAffineTransform.identity
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            let v = ns.substring(with: m.range(at: 2)).split(whereSeparator: { " ,\t\n".contains($0) })
                .compactMap { Double($0) }.map { CGFloat($0) }
            var t = CGAffineTransform.identity
            switch name {
            case "matrix" where v.count == 6:
                t = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            case "translate" where v.count >= 1:
                t = CGAffineTransform(translationX: v[0], y: v.count > 1 ? v[1] : 0)
            case "scale" where v.count >= 1:
                t = CGAffineTransform(scaleX: v[0], y: v.count > 1 ? v[1] : v[0])
            case "rotate" where v.count >= 1:
                let r = v[0] * .pi / 180
                if v.count >= 3 {
                    t = CGAffineTransform(translationX: -v[1], y: -v[2])
                        .concatenating(CGAffineTransform(rotationAngle: r))
                        .concatenating(CGAffineTransform(translationX: v[1], y: v[2]))
                } else {
                    t = CGAffineTransform(rotationAngle: r)
                }
            case "skewX" where v.count == 1:
                t = CGAffineTransform(a: 1, b: 0, c: tan(v[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where v.count == 1:
                t = CGAffineTransform(a: 1, b: tan(v[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                break
            }
            result = t.concatenating(result)
        }
        return result
    }
}
