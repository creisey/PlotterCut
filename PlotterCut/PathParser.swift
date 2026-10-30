import CoreGraphics

/// Wandelt SVG-Pfaddaten in Polylinien (mm) um, Kurven werden abgeflacht.
struct PathParser {
    let ctm: CGAffineTransform
    private var s: [UInt8] = []
    private var i = 0
    private var out: [Polyline] = []
    private var cur: [CGPoint] = []
    private var p = CGPoint.zero
    private var start = CGPoint.zero
    private var lastCtrl: CGPoint?
    private var lastCubic = false

    init(ctm: CGAffineTransform) { self.ctm = ctm }

    private var scale: CGFloat { sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c)) }
    private func tf(_ q: CGPoint) -> CGPoint { q.applying(ctm) }

    mutating func parse(_ d: String) -> [Polyline] {
        s = Array(d.utf8); i = 0
        var cmd: UInt8 = 0
        while true {
            skipSep()
            guard i < s.count else { break }
            let c = s[i]
            if (65...90).contains(c) || (97...122).contains(c) {
                i += 1; cmd = c
                if c | 0x20 == 122 { closePath(); continue }
            } else if cmd == 0 || cmd | 0x20 == 122 {
                break
            }
            let before = i
            guard step(cmd), i != before else { break }
            if cmd == 77 { cmd = 76 } else if cmd == 109 { cmd = 108 }
        }
        flush()
        return out
    }

    // MARK: Befehle

    private mutating func step(_ cmd: UInt8) -> Bool {
        let o = cmd >= 97 ? p : .zero
        switch cmd | 0x20 {
        case 109: // m
            guard let x = number(), let y = number() else { return false }
            flush()
            p = CGPoint(x: o.x + x, y: o.y + y); start = p; lastCtrl = nil
        case 108: // l
            guard let x = number(), let y = number() else { return false }
            lineTo(CGPoint(x: o.x + x, y: o.y + y))
        case 104: // h
            guard let x = number() else { return false }
            lineTo(CGPoint(x: o.x + x, y: p.y))
        case 118: // v
            guard let y = number() else { return false }
            lineTo(CGPoint(x: p.x, y: o.y + y))
        case 99: // c
            guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(),
                  let x = number(), let y = number() else { return false }
            cubic(CGPoint(x: o.x + x1, y: o.y + y1), CGPoint(x: o.x + x2, y: o.y + y2), CGPoint(x: o.x + x, y: o.y + y))
        case 115: // s
            guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return false }
            cubic(reflected(cubic: true), CGPoint(x: o.x + x2, y: o.y + y2), CGPoint(x: o.x + x, y: o.y + y))
        case 113: // q
            guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return false }
            quad(CGPoint(x: o.x + x1, y: o.y + y1), CGPoint(x: o.x + x, y: o.y + y))
        case 116: // t
            guard let x = number(), let y = number() else { return false }
            quad(reflected(cubic: false), CGPoint(x: o.x + x, y: o.y + y))
        case 97: // a
            guard let rx = number(), let ry = number(), let rot = number(),
                  let large = flag(), let sweep = flag(),
                  let x = number(), let y = number() else { return false }
            arc(rx, ry, rot, large, sweep, CGPoint(x: o.x + x, y: o.y + y))
        default:
            return false
        }
        return true
    }

    private func reflected(cubic: Bool) -> CGPoint {
        guard let c = lastCtrl, lastCubic == cubic else { return p }
        return CGPoint(x: 2 * p.x - c.x, y: 2 * p.y - c.y)
    }

    private mutating func begin() { if cur.isEmpty { cur = [tf(p)] } }

    private mutating func lineTo(_ q: CGPoint) {
        begin()
        cur.append(tf(q)); p = q; lastCtrl = nil
    }

    private mutating func cubic(_ c1: CGPoint, _ c2: CGPoint, _ e: CGPoint) {
        begin()
        let a = tf(p), b = tf(c1), c = tf(c2), d = tf(e)
        let len = dist(a, b) + dist(b, c) + dist(c, d)
        let n = max(2, min(200, Int((len / 0.5).rounded(.up))))
        for k in 1...n {
            let t = CGFloat(k) / CGFloat(n), u = 1 - t
            let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
            let x = w0 * a.x + w1 * b.x + w2 * c.x + w3 * d.x
            let y = w0 * a.y + w1 * b.y + w2 * c.y + w3 * d.y
            cur.append(CGPoint(x: x, y: y))
        }
        p = e; lastCtrl = c2; lastCubic = true
    }

    private mutating func quad(_ q: CGPoint, _ e: CGPoint) {
        let c1 = CGPoint(x: p.x + 2 / 3 * (q.x - p.x), y: p.y + 2 / 3 * (q.y - p.y))
        let c2 = CGPoint(x: e.x + 2 / 3 * (q.x - e.x), y: e.y + 2 / 3 * (q.y - e.y))
        cubic(c1, c2, e)
        lastCtrl = q; lastCubic = false
    }

    private mutating func arc(_ rxIn: CGFloat, _ ryIn: CGFloat, _ deg: CGFloat,
                              _ large: Bool, _ sweep: Bool, _ e: CGPoint) {
        if dist(p, e) < 1e-9 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { lineTo(e); return }
        begin()
        let phi = deg * .pi / 180
        let cp = cos(phi), sp = sin(phi)
        let dx = (p.x - e.x) / 2, dy = (p.y - e.y) / 2
        let x1 = cp * dx + sp * dy
        let y1 = -sp * dx + cp * dy
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
        let rx2 = rx * rx, ry2 = ry * ry
        let num = rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1
        let den = rx2 * y1 * y1 + ry2 * x1 * x1
        var co = den > 0 ? sqrt(max(0, num / den)) : 0
        if large == sweep { co = -co }
        let cx1 = co * rx * y1 / ry
        let cy1 = -co * ry * x1 / rx
        let cx = cp * cx1 - sp * cy1 + (p.x + e.x) / 2
        let cy = sp * cx1 + cp * cy1 + (p.y + e.y) / 2

        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry
        let t1 = ang(1, 0, ux, uy)
        var dt = ang(ux, uy, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && dt > 0 { dt -= 2 * .pi } else if sweep && dt < 0 { dt += 2 * .pi }

        let n = max(4, min(720, Int((abs(dt) * max(rx, ry) * scale / 0.5).rounded(.up))))
        for k in 1...n {
            let t = t1 + dt * CGFloat(k) / CGFloat(n)
            let ct = cos(t), st = sin(t)
            let x = cx + rx * ct * cp - ry * st * sp
            let y = cy + rx * ct * sp + ry * st * cp
            cur.append(tf(CGPoint(x: x, y: y)))
        }
        p = e; lastCtrl = nil
    }

    private mutating func closePath() {
        if !cur.isEmpty {
            let s0 = tf(start)
            if dist(cur[cur.count - 1], s0) > 0.001 { cur.append(s0) }
            if cur.count > 1 { out.append(Polyline(points: cur, closed: true)) }
        }
        cur = []; p = start; lastCtrl = nil
    }

    private mutating func flush() {
        if cur.count > 1 {
            out.append(Polyline(points: cur, closed: dist(cur[0], cur[cur.count - 1]) < 0.01))
        }
        cur = []
    }

    // MARK: Scanner

    private mutating func skipSep() {
        while i < s.count, [32, 44, 9, 10, 13].contains(s[i]) { i += 1 }
    }

    private mutating func number() -> CGFloat? {
        skipSep()
        let st = i
        if i < s.count, s[i] == 43 || s[i] == 45 { i += 1 }
        var dot = false, digits = false
        while i < s.count {
            let c = s[i]
            if c >= 48 && c <= 57 { digits = true; i += 1 }
            else if c == 46 && !dot { dot = true; i += 1 }
            else { break }
        }
        if digits, i < s.count, s[i] == 101 || s[i] == 69 {
            var j = i + 1
            if j < s.count, s[j] == 43 || s[j] == 45 { j += 1 }
            if j < s.count, s[j] >= 48 && s[j] <= 57 {
                i = j
                while i < s.count, s[i] >= 48 && s[i] <= 57 { i += 1 }
            }
        }
        guard digits else { i = st; return nil }
        return Double(String(decoding: s[st..<i], as: UTF8.self)).map { CGFloat($0) }
    }

    private mutating func flag() -> Bool? {
        skipSep()
        guard i < s.count, s[i] == 48 || s[i] == 49 else { return nil }
        defer { i += 1 }
        return s[i] == 49
    }
}
