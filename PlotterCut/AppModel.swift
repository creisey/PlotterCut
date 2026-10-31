import Foundation
import CoreGraphics
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var source: [Polyline] = []
    @Published var fileName = ""
    @Published var ports: [String] = []
    @Published var status = ""
    @Published var busy = false

    // Gespeicherte Einstellungen
    @Published var settings = CutSettings() { didSet { save() } }
    @Published var mediaWidth: Double = 380 { didSet { save() } }
    @Published var port = "" { didSet { save() } }
    @Published var baud = 9600 { didSet { save() } }
    @Published var flow: FlowControl = .rtscts { didSet { save() } }
    @Published var format: OutputFormat = .dmpl { didSet { save() } }
    @Published var velocity = 0 { didSet { save() } }
    @Published var force = 0 { didSet { save() } }
    @Published var endCommands = "PU;SP0;" { didSet { save() } }
    @Published var dropLines = false { didSet { save() } }

    private struct Stored: Codable {
        var settings: CutSettings
        var mediaWidth: Double
        var port: String
        var baud: Int
        var flow: FlowControl
        var format: OutputFormat
        var velocity: Int
        var force: Int
        var endCommands: String
        var dropLines: Bool
    }
    private let storeKey = "PlotterCutSettings"

    init() {
        defer { loadDemo() }
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        settings = s.settings
        mediaWidth = s.mediaWidth
        port = s.port
        baud = s.baud
        flow = s.flow
        format = s.format
        velocity = s.velocity
        force = s.force
        endCommands = s.endCommands
        dropLines = s.dropLines
    }

    private func save() {
        let s = Stored(settings: settings, mediaWidth: mediaWidth, port: port, baud: baud, flow: flow,
                       format: format, velocity: velocity, force: force,
                       endCommands: endCommands, dropLines: dropLines)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    var placed: [Polyline] { Layout.place(source, settings) }
    var tooWide: Bool { placed.bounds.maxY > CGFloat(mediaWidth) }

    // MARK: Grösse in mm (Motiv ohne Kopien und Rahmen)

    var designWidth: Double {
        get {
            let b = source.bounds
            return settings.rotate90 ? Double(b.height) * settings.scaleY / 100
                                     : Double(b.width) * settings.scaleX / 100
        }
        set {
            let b = source.bounds
            if settings.rotate90 { setScale(y: newValue, base: b.height) } else { setScale(x: newValue, base: b.width) }
        }
    }

    var designHeight: Double {
        get {
            let b = source.bounds
            return settings.rotate90 ? Double(b.width) * settings.scaleX / 100
                                     : Double(b.height) * settings.scaleY / 100
        }
        set {
            let b = source.bounds
            if settings.rotate90 { setScale(x: newValue, base: b.width) } else { setScale(y: newValue, base: b.height) }
        }
    }

    var lockAspect: Bool {
        get { settings.lockAspect }
        set {
            settings.lockAspect = newValue
            if newValue { settings.scaleY = settings.scaleX }
        }
    }

    private func setScale(x size: Double, base: CGFloat) {
        guard base > 0, size > 0 else { return }
        settings.scaleX = size / Double(base) * 100
        if settings.lockAspect { settings.scaleY = settings.scaleX }
    }

    private func setScale(y size: Double, base: CGFloat) {
        guard base > 0, size > 0 else { return }
        settings.scaleY = size / Double(base) * 100
        if settings.lockAspect { settings.scaleX = settings.scaleY }
    }

    // MARK: Demo

    private func loadDemo() {
        guard source.isEmpty else { return }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Polyline {
            let n = 180
            var pts = (0..<n).map { k -> CGPoint in
                let t = 2 * CGFloat.pi * CGFloat(k) / CGFloat(n)
                return CGPoint(x: cx + r * cos(t), y: cy + r * sin(t))
            }
            pts.append(pts[0])
            return Polyline(points: pts, closed: true)
        }
        let paths = [circle(15, 33, 15), circle(37, 33, 15), circle(26, 15, 15)]
        let b = paths.bounds
        source = paths.applying(CGAffineTransform(translationX: -b.minX, y: -b.minY))
        fileName = "Demo"
    }

    // MARK: Aktionen

    func refreshPorts() {
        ports = SerialPort.list()
        if !ports.contains(port) {
            port = ports.first(where: { $0.contains("usbserial") }) ?? ports.first ?? ""
        }
    }

    func load(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            switch url.pathExtension.lowercased() {
            case "ai", "pdf": source = try PDFImporter.load(url: url)
            default:          source = try SVGImporter.load(url: url)
            }
            fileName = url.lastPathComponent
            status = "\(source.count) Pfade geladen"
        } catch {
            status = error.localizedDescription
        }
    }

    func cut() { send(placed) }

    func testCut() {
        let x = CGFloat(settings.offsetX), y = CGFloat(settings.offsetY)
        let sq = [CGPoint(x: x, y: y), CGPoint(x: x + 10, y: y), CGPoint(x: x + 10, y: y + 10),
                  CGPoint(x: x, y: y + 10), CGPoint(x: x, y: y)]
        send([Polyline(points: sq, closed: true)])
    }

    private func send(_ paths: [Polyline]) {
        guard !port.isEmpty else { status = "Kein Port gewählt"; return }
        let pts = Knife.prepare(paths, offset: settings.bladeOffset, overcut: settings.overcut)
        let text: String
        switch format {
        case .dmpl: text = DMPL.make(pts, advance: settings.advance)
        case .hpgl: text = HPGL.make(pts, velocity: velocity, force: force,
                                     advance: settings.advance, end: endCommands)
        }
        let data = Data(text.utf8)
        let port = port, baud = baud, flow = flow, dropLines = dropLines
        busy = true
        status = "Sende …"
        Task {
            let result = await Task.detached { () -> String in
                do {
                    try SerialPort.send(data, to: port, baud: baud, flow: flow, dropLines: dropLines)
                    return "Gesendet"
                } catch {
                    return error.localizedDescription
                }
            }.value
            busy = false
            status = result
        }
    }
}
