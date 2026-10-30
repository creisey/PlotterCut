import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var m = AppModel()
    @State private var importing = false

    var body: some View {
        HSplitView {
            Form {
                Section("Datei") {
                    Button("SVG öffnen …") { importing = true }
                    if !m.fileName.isEmpty { Text(m.fileName).foregroundStyle(.secondary) }
                }
                Section("Anordnung") {
                    TextField("Skalierung %", value: $m.settings.scale, format: .number)
                    Toggle("90° drehen", isOn: $m.settings.rotate90)
                    Toggle("Spiegeln", isOn: $m.settings.mirror)
                    TextField("Position X (mm)", value: $m.settings.offsetX, format: .number)
                    TextField("Position Y (mm)", value: $m.settings.offsetY, format: .number)
                    Stepper("Kopien: \(m.settings.copies)", value: $m.settings.copies, in: 1...100)
                    TextField("Abstand (mm)", value: $m.settings.gap, format: .number)
                    Toggle("Entgitterrahmen", isOn: $m.settings.weedBox)
                    TextField("Rahmenabstand (mm)", value: $m.settings.weedMargin, format: .number)
                }
                Section("Messer") {
                    TextField("Messerversatz (mm)", value: $m.settings.bladeOffset, format: .number)
                    TextField("Overcut (mm)", value: $m.settings.overcut, format: .number)
                    TextField("Geschwindigkeit VS (0 = Plotter)", value: $m.velocity, format: .number)
                    TextField("Druck FS (0 = Plotter)", value: $m.force, format: .number)
                    TextField("Materialbreite (mm)", value: $m.mediaWidth, format: .number)
                }
                Section("Verbindung") {
                    Picker("Port", selection: $m.port) {
                        Text("–").tag("")
                        ForEach(m.ports, id: \.self) { Text($0).tag($0) }
                    }
                    Button("Ports aktualisieren") { m.refreshPorts() }
                    Picker("Baudrate", selection: $m.baud) {
                        ForEach([1200, 2400, 4800, 9600, 19200, 38400, 57600], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Handshake", selection: $m.flow) {
                        ForEach(FlowControl.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section {
                    Button("Testschnitt (10 × 10 mm)") { m.testCut() }.disabled(m.busy)
                    Button("Schneiden") { m.cut() }.disabled(m.source.isEmpty || m.busy)
                    if m.tooWide { Text("Motiv breiter als Material!").foregroundStyle(.red) }
                    if !m.status.isEmpty { Text(m.status).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 300, maxWidth: 380)

            VStack(alignment: .leading, spacing: 4) {
                CutPreview(paths: m.placed, mediaWidth: m.mediaWidth)
                Text("Waagrecht = Vorschub, senkrecht = Materialbreite")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 500, minHeight: 500)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.svg]) { result in
            if case .success(let url) = result { m.load(url) }
        }
        .onAppear { m.refreshPorts() }
    }
}

struct CutPreview: View {
    let paths: [Polyline]
    let mediaWidth: Double

    var body: some View {
        Canvas { ctx, size in
            let b = paths.bounds
            let worldW = max(b.maxX, 100) + 10
            let worldH = max(CGFloat(mediaWidth), b.maxY)
            let s = min((size.width - 20) / worldW, (size.height - 20) / worldH)
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: 10 + p.x * s, y: 10 + (worldH - p.y) * s) }

            let mediaTop = 10 + (worldH - CGFloat(mediaWidth)) * s
            ctx.fill(Path(CGRect(x: 10, y: mediaTop, width: worldW * s, height: CGFloat(mediaWidth) * s)),
                     with: .color(.gray.opacity(0.12)))

            var path = Path()
            for pl in paths {
                guard let f = pl.points.first else { continue }
                path.move(to: pt(f))
                for q in pl.points.dropFirst() { path.addLine(to: pt(q)) }
            }
            ctx.stroke(path, with: .color(.accentColor), lineWidth: 1)
        }
    }
}
