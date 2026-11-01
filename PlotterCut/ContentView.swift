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
                            Label(L.t("Schneiden", "Cut"), systemImage: "scissors").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(m.source.isEmpty || m.busy)
                        Button(L.t("Testschnitt", "Test cut")) { m.testCut() }
                            .controlSize(.large)
                            .disabled(m.busy)
                    }
                    Text(m.status.isEmpty ? L.t("Bereit", "Ready") + " · " + (m.port.isEmpty ? L.t("kein Port", "no port") : m.port) : m.status)
                        .font(.caption).foregroundStyle(.secondary)
                    if m.tooWide { Text(L.t("Motiv breiter als Material!", "Design wider than material!")).foregroundStyle(.red) }
                }

                Section(L.t("Datei", "File")) {
                    HStack {
                        Button(L.t("Datei öffnen …", "Open file …")) { importing = true }
                        Spacer()
                        Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.borderless)
                            .help(L.t("Hinweise zum Import", "Import notes"))
                            .popover(isPresented: $showInfo, arrowEdge: .trailing) { ImportInfo() }
                    }
                    HStack {
                        Text(m.fileName.isEmpty ? L.t("Keine Datei", "No file") : m.fileName)
                        Spacer()
                        Text(".svg · .ai · .pdf").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }

                Section(L.t("Grösse und Anordnung", "Size and layout")) {
                    TextField(L.t("Skalierung (%)", "Scale (%)"), value: $m.scalePercent, format: .number.precision(.fractionLength(0...2)))
                        .disabled(m.source.isEmpty)
                    TextField(L.t("Breite (mm)", "Width (mm)"), value: $m.designWidth, format: .number.precision(.fractionLength(1)))
                        .disabled(m.source.isEmpty)
                    TextField(L.t("Höhe (mm)", "Height (mm)"), value: $m.designHeight, format: .number.precision(.fractionLength(1)))
                        .disabled(m.source.isEmpty)
                    Toggle(isOn: $m.lockAspect) {
                        Label(L.t("Seitenverhältnis beibehalten", "Keep aspect ratio"), systemImage: m.lockAspect ? "lock" : "lock.open")
                    }
                    Toggle(L.t("90° drehen", "Rotate 90°"), isOn: $m.settings.rotate90)
                    Toggle(L.t("Spiegeln", "Mirror"), isOn: $m.settings.mirror)
                    TextField(L.t("Position X (mm)", "Position X (mm)"), value: $m.settings.offsetX, format: .number)
                    TextField(L.t("Position Y (mm)", "Position Y (mm)"), value: $m.settings.offsetY, format: .number)
                    Stepper(L.t("Kopien", "Copies") + ": \(m.settings.copies)", value: $m.settings.copies, in: 1...100)
                    TextField(L.t("Abstand (mm)", "Gap (mm)"), value: $m.settings.gap, format: .number)
                    Toggle(L.t("Entgitterrahmen", "Weeding box"), isOn: $m.settings.weedBox)
                    TextField(L.t("Rahmenabstand (mm)", "Box margin (mm)"), value: $m.settings.weedMargin, format: .number)
                }

                Section {
                    DisclosureGroup(L.t("Plotter-Einstellungen", "Plotter settings"), isExpanded: $showPlotter) {
                        Text(L.t("Messer", "Blade")).font(.headline).padding(.top, 6)
                        TextField(L.t("Messerversatz (mm)", "Blade offset (mm)"), value: $m.settings.bladeOffset, format: .number)
                        TextField(L.t("Overcut (mm)", "Overcut (mm)"), value: $m.settings.overcut, format: .number)
                        TextField(L.t("Vorschub nach Schnitt (mm)", "Feed after cut (mm)"), value: $m.settings.advance, format: .number)
                        TextField(L.t("Geschwindigkeit VS (0 = Plotter)", "Speed VS (0 = plotter)"), value: $m.velocity, format: .number)
                            .disabled(m.format == .dmpl)
                        TextField(L.t("Druck FS (0 = Plotter)", "Force FS (0 = plotter)"), value: $m.force, format: .number)
                            .disabled(m.format == .dmpl)
                        TextField(L.t("Materialbreite (mm)", "Material width (mm)"), value: $m.mediaWidth, format: .number)

                        Text(L.t("Verbindung", "Connection")).font(.headline).padding(.top, 10)
                        Picker(L.t("Format", "Format"), selection: $m.format) {
                            ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Port", selection: $m.port) {
                            Text("–").tag("")
                            ForEach(m.ports, id: \.self) { Text($0).tag($0) }
                        }
                        Button(L.t("Ports aktualisieren", "Refresh ports")) { m.refreshPorts() }
                        Picker(L.t("Baudrate", "Baud rate"), selection: $m.baud) {
                            ForEach([1200, 2400, 4800, 9600, 19200, 38400, 57600], id: \.self) { Text("\($0)").tag($0) }
                        }
                        Picker("Handshake", selection: $m.flow) {
                            ForEach(FlowControl.allCases) { Text($0.label).tag($0) }
                        }
                        TextField(L.t("Abschluss-Befehle (HPGL)", "End commands (HPGL)"), text: $m.endCommands)
                            .disabled(m.format == .dmpl)
                        Toggle(L.t("Steuerleitungen nach dem Senden abschalten", "Drop control lines after sending"), isOn: $m.dropLines)
                    }
                }

                Section {
                    Picker(L.t("Sprache", "Language"), selection: $m.language) {
                        ForEach(Lang.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 320, maxWidth: 400)

            VStack(alignment: .leading, spacing: 4) {
                CutPreview(paths: m.placed, mediaWidth: m.mediaWidth, extent: m.viewExtent)
                HStack {
                    Text(L.t("Waagrecht = Vorschub, senkrecht = Materialbreite, Lineale in mm", "Horizontal = feed, vertical = material width, rulers in mm"))
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
            Text(L.t("Was geschnitten wird", "What gets cut")).font(.headline)
            Group {
                Text(L.t("• Formate: .svg, .ai und .pdf", "• Formats: .svg, .ai and .pdf"))
                Text(L.t("• Nur Pfade werden geschnitten.", "• Only paths are cut."))
                Text(L.t("• Schrift vorher in Pfade umwandeln, sonst wird sie ignoriert.", "• Convert text to outlines first, otherwise it is ignored."))
                Text(L.t("• .ai mit «PDF-kompatible Datei erstellen» speichern (Standard in Illustrator).", "• Save .ai with «Create PDF Compatible File» (Illustrator default)."))
                Text(L.t("• Pixelbilder werden ignoriert.", "• Raster images are ignored."))
                Text(L.t("• Schnittmasken werden nicht berücksichtigt: Verdecktes wird mitgeschnitten.", "• Clipping masks are ignored: hidden parts are cut too."))
                Text(L.t("• Konturen werden auf ihrer Mittellinie geschnitten, die Strichstärke zählt nicht.", "• Strokes are cut along their centre line, stroke width is ignored."))
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
    let extent: CGSize

    var body: some View {
        Canvas { ctx, size in
            let left: CGFloat = 38, right: CGFloat = 10, top: CGFloat = 10, bottom: CGFloat = 24
            let availW = max(size.width - left - right, 10)
            let availH = max(size.height - top - bottom, 10)

            // Zoom aus dem beim Laden eingepassten Sichtbereich, Masse bleiben 1:1
            let margin = max(max(extent.width, extent.height) * 0.08, 3)
            let s = min(availW / (extent.width + margin), availH / (extent.height + margin))
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
