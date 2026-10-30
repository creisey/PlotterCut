import CoreGraphics

struct Polyline {
    var points: [CGPoint]
    var closed: Bool
}

func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

extension Array where Element == Polyline {
    var bounds: CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for pl in self {
            for p in pl.points {
                minX = Swift.min(minX, p.x); minY = Swift.min(minY, p.y)
                maxX = Swift.max(maxX, p.x); maxY = Swift.max(maxY, p.y)
            }
        }
        guard minX <= maxX else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func applying(_ t: CGAffineTransform) -> [Polyline] {
        map { Polyline(points: $0.points.map { $0.applying(t) }, closed: $0.closed) }
    }
}
