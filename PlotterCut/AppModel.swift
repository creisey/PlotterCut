import Foundation
import CoreGraphics

@MainActor
final class AppModel: ObservableObject {
    @Published var source: [Polyline] = []
    @Published var fileName = ""
    @Published var settings = CutSettings()
    @Published var mediaWidth: Double = 380
    @Published var ports: [String] = []
    @Published var port = ""
    @Published var baud = 9600
    @Published var flow: FlowControl = .xonxoff
    @Published var velocity = 0
    @Published var force = 0
    @Published var status = ""
    @Published var busy = false

    var placed: [Polyline] { Layout.place(source, settings) }
    var tooWide: Bool { placed.bounds.maxY > CGFloat(mediaWidth) }

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
            source = try SVGImporter.load(url: url)
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
        let data = Data(HPGL.make(pts, velocity: velocity, force: force).utf8)
        let port = port, baud = baud, flow = flow
        busy = true
        status = "Sende …"
        Task {
            let result = await Task.detached { () -> String in
                do {
                    try SerialPort.send(data, to: port, baud: baud, flow: flow)
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
