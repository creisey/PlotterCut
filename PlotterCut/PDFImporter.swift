import Foundation
import CoreGraphics

/// Sammelt Pfade aus dem PDF-Inhalt (Einheit: Punkt, y nach oben).
nonisolated final class PDFCollector {
    private var ctm = CGAffineTransform.identity
    private var stack: [CGAffineTransform] = []
    private var sub: [CGPoint] = []
    private var pending: [(points: [CGPoint], closed: Bool)] = []
    private var p = CGPoint.zero
    private var start = CGPoint.zero
    private(set) var result: [(points: [CGPoint], closed: Bool)] = []

    var current: CGPoint { p }

    private func tf(_ q: CGPoint) -> CGPoint { q.applying(ctm) }
    private func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    func push() { stack.append(ctm) }
    func pop() { if let t = stack.popLast() { ctm = t } }
    func concat(_ m: CGAffineTransform) { ctm = m.concatenating(ctm) }

    func move(_ x: CGFloat, _ y: CGFloat) {
        finishSub(closed: false)
        p = CGPoint(x: x, y: y); start = p
        sub = [tf(p)]
    }

    func line(_ x: CGFloat, _ y: CGFloat) {
        if sub.isEmpty { sub = [tf(p)] }
        p = CGPoint(x: x, y: y)
        sub.append(tf(p))
    }

    func curve(_ c1: CGPoint, _ c2: CGPoint, _ e: CGPoint) {
        if sub.isEmpty { sub = [tf(p)] }
        let a = tf(p), b = tf(c1), c = tf(c2), dd = tf(e)
        let len = d(a, b) + d(b, c) + d(c, dd)
        let n = max(2, min(200, Int((len / 1.4).rounded(.up)))) // ca. 0,5 mm
        for k in 1...n {
            let t = CGFloat(k) / CGFloat(n), u = 1 - t
            let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
            let x = w0 * a.x + w1 * b.x + w2 * c.x + w3 * dd.x
            let y = w0 * a.y + w1 * b.y + w2 * c.y + w3 * dd.y
            sub.append(CGPoint(x: x, y: y))
        }
        p = e
    }

    func close() {
        guard !sub.isEmpty else { return }
        let s0 = tf(start)
        if d(sub[sub.count - 1], s0) > 0.001 { sub.append(s0) }
        finishSub(closed: true)
        p = start
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        move(x, y); line(x + w, y); line(x + w, y + h); line(x, y + h); close()
    }

    /// Pfad wird gezeichnet: übernehmen
    func paint(closeFirst: Bool) {
        if closeFirst { close() }
        finishSub(closed: false)
        result += pending
        pending = []
    }

    /// Pfad nur als Schnittmaske (Operator n): verwerfen
    func discard() { sub = []; pending = [] }

    private func finishSub(closed: Bool) {
        if sub.count > 1 {
            pending.append((sub, closed || d(sub[0], sub[sub.count - 1]) < 0.01))
        }
        sub = []
    }
}

private nonisolated func pdfNum(_ s: CGPDFScannerRef) -> CGFloat {
    var v: CGPDFReal = 0
    _ = CGPDFScannerPopNumber(s, &v)
    return v
}

private nonisolated func pdfCollector(_ info: UnsafeMutableRawPointer?) -> PDFCollector {
    Unmanaged<PDFCollector>.fromOpaque(info!).takeUnretainedValue()
}

/// Liest .pdf und .ai (mit PDF-Kompatibilität). Liefert Pfade in mm, Ursprung links unten.
enum PDFImporter {
    static func load(url: URL) throws -> [Polyline] {
        guard let doc = CGPDFDocument(url as CFURL), let page = doc.page(at: 1),
              let table = CGPDFOperatorTableCreate() else { throw SVGError.unreadable }
        defer { CGPDFOperatorTableRelease(table) }

        CGPDFOperatorTableSetCallback(table, "q") { _, i in pdfCollector(i).push() }
        CGPDFOperatorTableSetCallback(table, "Q") { _, i in pdfCollector(i).pop() }
        CGPDFOperatorTableSetCallback(table, "cm") { s, i in
            let f = pdfNum(s), e = pdfNum(s), d = pdfNum(s), c = pdfNum(s), b = pdfNum(s), a = pdfNum(s)
            pdfCollector(i).concat(CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f))
        }
        CGPDFOperatorTableSetCallback(table, "m") { s, i in
            let y = pdfNum(s), x = pdfNum(s)
            pdfCollector(i).move(x, y)
        }
        CGPDFOperatorTableSetCallback(table, "l") { s, i in
            let y = pdfNum(s), x = pdfNum(s)
            pdfCollector(i).line(x, y)
        }
        CGPDFOperatorTableSetCallback(table, "c") { s, i in
            let y3 = pdfNum(s), x3 = pdfNum(s), y2 = pdfNum(s), x2 = pdfNum(s), y1 = pdfNum(s), x1 = pdfNum(s)
            pdfCollector(i).curve(CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2), CGPoint(x: x3, y: y3))
        }
        CGPDFOperatorTableSetCallback(table, "v") { s, i in
            let y3 = pdfNum(s), x3 = pdfNum(s), y2 = pdfNum(s), x2 = pdfNum(s)
            let col = pdfCollector(i)
            col.curve(col.current, CGPoint(x: x2, y: y2), CGPoint(x: x3, y: y3))
        }
        CGPDFOperatorTableSetCallback(table, "y") { s, i in
            let y3 = pdfNum(s), x3 = pdfNum(s), y1 = pdfNum(s), x1 = pdfNum(s)
            let e = CGPoint(x: x3, y: y3)
            pdfCollector(i).curve(CGPoint(x: x1, y: y1), e, e)
        }
        CGPDFOperatorTableSetCallback(table, "h") { _, i in pdfCollector(i).close() }
        CGPDFOperatorTableSetCallback(table, "re") { s, i in
            let h = pdfNum(s), w = pdfNum(s), y = pdfNum(s), x = pdfNum(s)
            pdfCollector(i).rect(x, y, w, h)
        }
        for op in ["S", "f", "F", "f*", "B", "B*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, i in pdfCollector(i).paint(closeFirst: false) }
        }
        for op in ["s", "b", "b*"] {
            CGPDFOperatorTableSetCallback(table, op) { _, i in pdfCollector(i).paint(closeFirst: true) }
        }
        CGPDFOperatorTableSetCallback(table, "n") { _, i in pdfCollector(i).discard() }

        let collector = PDFCollector()
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(collector).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        withExtendedLifetime(collector) { _ = CGPDFScannerScan(scanner) }

        let k: CGFloat = 25.4 / 72 // Punkt -> mm
        let paths = collector.result.map { r in
            Polyline(points: r.points.map { CGPoint(x: $0.x * k, y: $0.y * k) }, closed: r.closed)
        }
        guard !paths.isEmpty else { throw SVGError.empty }
        let b = paths.bounds
        return paths.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY))
    }
}
