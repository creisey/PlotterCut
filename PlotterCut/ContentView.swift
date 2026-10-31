import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var m = AppModel()
    @State private var importing = false
    @State private var showInfo = false
    @State private var showPlotter = false

    private var fileTypes: [UTType] {
        [.svg, .pdf] + [UTType(filenameExtension: "ai")].compactMap { $0 }
    }

    var body: some View {
        HSplitView {
            Form {
                Section {
                    HStack {
                        Button { m.cut() } label: {
                            Label("Schneiden", systemImage: "scissors").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(m.source.isEmpty || m.busy)
                        Button("Testschnitt") { m.testCut() }
                            .controlSize(.large)
                            .disabled(m.busy)
                    }
                    Text(m.status.isEmpty ? "Bereit · \(m.port.isEmpty ? "kein Port" : m.port)" : m.status)
                        .font(.caption).foregroundStyle(.secondary)
                    if m.tooWide { Text("Motiv breiter als Material!").foregroundStyle(.red) }
                }

                Section("Datei") {
                    HStack {
                        Button("Datei öffnen …") { importing = true }
                        Spacer()
                        Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                            .help("Hinweise zum Import")
                            .popover(isPresented: $showInfo, arrowEdge: .trailing) { ImportInfo() }
                    }
                    HStack {
                        Text(m.fileName.isEmpty ? "Keine Datei" : m.fileName)
                        Spacer()
                        Text(".svg · .ai · .pdf").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Section("Grösse und Anordnung") {
                    TextField("Breite (mm)", value: $m.designWidth, format: .number.precision(.fractionLength(1)))
                        .disabled(m.source.isEmpty)
                    TextField("Höhe (mm)", value: $m.designHeight, format: .number.precision(.fractionLength(1)))
                        .disabled(m.source.isEmpty)
                    Toggle(isOn: $m.lockAspect) {
                        Label("Seitenverhältnis beibehalten", systemImage: m.lockAspect ? "lock" : "lock.open")
                    }
                    Toggle("90° drehen", isOn: $m.settings.rotate90)
                    Toggle("Spiegeln", isOn: $m.settings.mirror)
                    TextField("Position X (mm)", value: $m.settings.offsetX, format: .number)
                    TextField("Position Y (mm)", value: $m.settings.offsetY, format: .number)
                    Stepper("Kopien: \(m.settings.copies)", value: $m.settings.copies, in: 1...100)
                    TextField("Abstand (mm)", value: $m.settings.gap, format: .number)
                    Toggle("Entgitterrahmen", isOn: $m.settings.weedBox)
                    TextField("Rahmenabstand (mm)", value: $m.settings.weedMargin, format: .number)
                }

                Section {
                    DisclosureGroup("Plotter-Einstellungen", isExpanded: $showPlotter) {
                        Text("Messer").font(.headline).padding(.top, 6)
                        TextField("Messerversatz (mm)", value: $m.settings.bladeOffset, format: .number)
                        TextField("Overcut (mm)", value: $m.settings.overcut, format: .number)
                        TextField("Vorschub nach Schnitt (mm)", value: $m.settings.advance, format: .number)
                        TextField("Geschwindigkeit VS (0 = Plotter)", value: $m.velocity, format: .number)
                            .disabled(m.format == .dmpl)
                        TextField("Druck FS (0 = Plotter)", value: $m.force, format: .number)
                            .disabled(m.format == .dmpl)
                        TextField("Materialbreite (mm)", value: $m.mediaWidth, format: .number)

                        Text("Verbindung").font(.headline).padding(.top, 10)
                        Picker("Format", selection: $m.format) {
                            ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                        }
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
                        TextField("Abschluss-Befehle (HPGL)", text: $m.endCommands)
                            .disabled(m.format == .dmpl)
                        Toggle("Steuerleitungen nach dem Senden abschalten", isOn: $m.dropLines)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, maxWidth: 400)

            VStack(alignment: .leading, spacing: 4) {
                CutPreview(paths: m.placed, mediaWidth: m.mediaWidth)
                HStack {
                    Text("Waagrecht = Vorschub, senkrecht = Materialbreite, Lineale in mm")
                    Spacer()
                    if !m.source.isEmpty {
                        let b = m.placed.bounds
                        Text("\(Double(b.width).formatted(.number.precision(.fractionLength(1)))) × \(Double(b.height).formatted(.number.precision(.fractionLength(1)))) mm")
                            .monospacedDigit()
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 500, minHeight: 500)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: fileTypes) { result in
            if case .success(let url) = result { m.load(url) }
        }
        .onAppear { m.refreshPorts() }
    }
}

struct ImportInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Was geschnitten wird").font(.headline)
            Group {
                Text("• Formate: .svg, .ai und .pdf")
                Text("• Nur Pfade werden geschnitten.")
                Text("• Schrift vorher in Pfade umwandeln, sonst wird sie ignoriert.")
                Text("• .ai mit «PDF-kompatible Datei erstellen» speichern (Standard in Illustrator).")
                Text("• Pixelbilder werden ignoriert.")
                Text("• Schnittmasken werden nicht berücksichtigt: Verdecktes wird mitgeschnitten.")
                Text("• Konturen werden auf ihrer Mittellinie geschnitten, die Strichstärke zählt nicht.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding()
        .frame(width: 340, alignment: .leading)
    }
}

struct CutPreview: View {
    let paths: [Polyline]
    let mediaWidth: Double

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 38, right: CGFloat = 10, top: CGFloat = 10, bottom: CGFloat = 24
            let availW = max(size.width - left - right, 10)
            let availH = max(size.height - top - bottom, 10)

            // Ausschnitt: Nullpunkt bis Motiv plus Rand
            let b = paths.bounds
            let extent = max(b.maxX, b.maxY, 20)
            let margin = max(extent * 0.08, 3)
            let s = min(availW / (max(b.maxX, 20) + margin), availH / (max(b.maxY, 20) + margin))
            let worldW = availW / s, worldH = availH / s
            let originY = top + availH
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: left + p.x * s, y: originY - p.y * s) }

            let plot = CGRect(x: left, y: top, width: availW, height: availH)
            var inner = ctx
            inner.clip(to: Path(plot))

            // Material
            let mediaH = CGFloat(mediaWidth) * s
            inner.fill(Path(CGRect(x: left, y: originY - mediaH, width: availW, height: mediaH)),
                       with: .color(.gray.opacity(0.12)))
            if CGFloat(mediaWidth) < worldH {
                var edge = Path()
                edge.move(to: CGPoint(x: left, y: originY - mediaH))
                edge.addLine(to: CGPoint(x: left + availW, y: originY - mediaH))
                inner.stroke(edge, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            // Lineale (Beschriftung in mm)
            let minor = [1, 2, 5, 10, 20, 50, 100].first { CGFloat($0) * s >= 4 } ?? 100
            let label = [10, 20, 50, 100, 200, 500, 1000].first { CGFloat($0) * s >= 40 } ?? 1000
            func tickLength(_ k: Int) -> CGFloat {
                k % label == 0 ? 8 : (k % (minor * 5) == 0 ? 5 : 3)
            }
            var ticks = Path()
            for k in stride(from: 0, through: Int(worldW), by: minor) {
                let x = left + CGFloat(k) * s
                ticks.move(to: CGPoint(x: x, y: originY))
                ticks.addLine(to: CGPoint(x: x, y: originY + tickLength(k)))
                if k % label == 0 {
                    ctx.draw(Text("\(k)").font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: originY + 10), anchor: .top)
                }
            }
            for k in stride(from: 0, through: Int(worldH), by: minor) {
                let y = originY - CGFloat(k) * s
                ticks.move(to: CGPoint(x: left, y: y))
                ticks.addLine(to: CGPoint(x: left - tickLength(k), y: y))
                if k % label == 0 {
                    ctx.draw(Text("\(k)").font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: left - 10, y: y), anchor: .trailing)
                }
            }
            ctx.stroke(ticks, with: .color(.secondary), lineWidth: 0.5)

            // Motiv
            var path = Path()
            for pl in paths {
                guard let f = pl.points.first else { continue }
                path.move(to: pt(f))
                for q in pl.points.dropFirst() { path.addLine(to: pt(q)) }
            }
            inner.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
    }
}
