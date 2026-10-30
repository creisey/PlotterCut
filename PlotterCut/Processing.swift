import CoreGraphics

struct CutSettings {
    var scale: Double = 100        // %
    var rotate90 = false
    var mirror = false
    var offsetX: Double = 2        // mm
    var offsetY: Double = 2
    var copies = 1
    var gap: Double = 5
    var weedBox = false
    var weedMargin: Double = 3
    var bladeOffset: Double = 0.25
    var overcut: Double = 1
}

enum Layout {
    static func place(_ src: [Polyline], _ s: CutSettings) -> [Polyline] {
        guard !src.isEmpty else { return [] }
        let f = CGFloat(s.scale / 100)
        var p = src.applying(CGAffineTransform(scaleX: f, y: f))
        if s.rotate90 { p = p.applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)) }
        if s.mirror { p = p.applying(CGAffineTransform(scaleX: -1, y: 1)) }
        var b = p.bounds
        p = p.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY))
        b = p.bounds

        var all: [Polyline] = []
        for k in 0..<max(1, s.copies) {
            all += p.applying(CGAffineTransform(translationX: CGFloat(k) * (b.width + CGFloat(s.gap)), y: 0))
        }
        if s.weedBox {
            let m = CGFloat(s.weedMargin)
            let r = all.bounds.insetBy(dx: -m, dy: -m)
            all.append(Polyline(points: [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                                         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                                         CGPoint(x: r.minX, y: r.minY)], closed: true))
        }
        let bb = all.bounds
        return all.applying(CGAffineTransform(translationX: CGFloat(s.offsetX) - bb.minX,
                                              y: CGFloat(s.offsetY) - bb.minY))
    }
}

/// Overcut und Messerversatz-Kompensation für Schleppmesser.
enum Knife {
    static func prepare(_ paths: [Polyline], offset: Double, overcut: Double) -> [[CGPoint]] {
        paths.compactMap { pl in
            var pts = dedupe(pl.points)
            guard pts.count > 1 else { return nil }
            if pl.closed && overcut > 0 { pts = addOvercut(pts, CGFloat(overcut)) }
            return offset > 0 ? compensate(pts, CGFloat(offset)) : pts
        }
    }

    private static func dedupe(_ pts: [CGPoint]) -> [CGPoint] {
        var out: [CGPoint] = []
        for p in pts where out.last.map({ dist($0, p) > 0.01 }) ?? true { out.append(p) }
        return out
    }

    private static func addOvercut(_ pts: [CGPoint], _ len: CGFloat) -> [CGPoint] {
        var out = pts, rest = len
        for k in 1..<pts.count {
            let a = pts[k - 1], b = pts[k], d = dist(a, b)
            if d >= rest {
                let t = rest / d
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                break
            }
            out.append(b); rest -= d
        }
        return out
    }

    private static func compensate(_ p: [CGPoint], _ r: CGFloat) -> [CGPoint] {
        func dir(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            let d = dist(a, b)
            return CGVector(dx: (b.x - a.x) / d, dy: (b.y - a.y) / d)
        }
        var prev = dir(p[0], p[1])
        var out = [CGPoint(x: p[0].x + r * prev.dx, y: p[0].y + r * prev.dy)]
        let maxStep = 10 * CGFloat.pi / 180
        for k in 1..<p.count {
            let d = dir(p[k - 1], p[k])
            if k > 1 {
                let c = p[k - 1]
                let a0 = atan2(prev.dy, prev.dx)
                var da = atan2(d.dy, d.dx) - a0
                while da > .pi { da -= 2 * .pi }
                while da < -.pi { da += 2 * .pi }
                let steps = max(1, Int((abs(da) / maxStep).rounded(.up)))
                for st in 1...steps {
                    let a = a0 + da * CGFloat(st) / CGFloat(steps)
                    out.append(CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
                }
            }
            out.append(CGPoint(x: p[k].x + r * d.dx, y: p[k].y + r * d.dy))
            prev = d
        }
        return out
    }
}

enum HPGL {
    /// 40 Plottereinheiten pro mm
    static func make(_ paths: [[CGPoint]], velocity: Int, force: Int) -> String {
        func u(_ v: CGFloat) -> Int { Int((v * 40).rounded()) }
        var s = "IN;"
        if velocity > 0 { s += "VS\(velocity);" }
        if force > 0 { s += "FS\(force);" }
        s += "SP1;"
        for pts in paths {
            s += "PU\(u(pts[0].x)),\(u(pts[0].y));"
            for p in pts.dropFirst() { s += "PD\(u(p.x)),\(u(p.y));" }
        }
        s += "PU0,0;"
        return s
    }
}
