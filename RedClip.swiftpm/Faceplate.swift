import SwiftUI

/// The Red Clip faceplate: Tyrone's picture (Resources: RCPlate, with every moving part removed)
/// with the live parts drawn on top in exactly the same places: knob pointers and values, LED
/// meters, the screen, the CLIP readout, the lit buttons and their labels.
/// Every coordinate below is a pixel position in the 1448 x 997 picture. The app and the AUv3
/// plug-in both show this view and scale it to fit.
@MainActor
struct FaceplateView: View {
    @ObservedObject var face: FaceModel
    @ObservedObject var params: ParamStore

    static let size = CGSize(width: 1448, height: 997)

    private var theme: PlateTheme { face.theme }

    // knob centres in the picture
    static let bigKnobs: [(Param, CGPoint, HelpTopic)] = [
        (.inputDB, CGPoint(x: 208.9, y: 581.5), .input),
        (.driveDB, CGPoint(x: 465.4, y: 581.5), .drive),
        (.ceilingDB, CGPoint(x: 723.4, y: 581.4), .ceiling),
        (.mix, CGPoint(x: 983.1, y: 581.0), .mix),
        (.outputDB, CGPoint(x: 1240.8, y: 581.8), .output)
    ]
    static let redKnob = CGPoint(x: 198.1, y: 795.8)
    static let fireKnob = CGPoint(x: 677.6, y: 796.6)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(theme.image("RCPlate"))
                .resizable()
                .interpolation(.high)
                .frame(width: Self.size.width, height: Self.size.height)
            header
            displays
            knobs
            redRow
            bottomRow
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .clipped()
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            // preset: arrows step, the name opens the menu (Audio first, then Presets)
            HitArea { params.stepPreset(-1) }
                .helpTarget(.presets, face).place(x: 523, y: 25, w: 52, h: 53)
            HitArea { params.stepPreset(1) }
                .helpTarget(.presets, face).place(x: 871, y: 25, w: 52, h: 53)
            Menu {
                if !face.isPlugin {
                    Section("Audio") {
                        Button { face.importRequested = true } label: {
                            Label("Import Audio from Files…", systemImage: "square.and.arrow.down")
                        }
                        if face.sampleFiles.isEmpty {
                            Text("Samples folder is empty")
                        } else {
                            Menu {
                                ForEach(face.sampleFiles) { item in
                                    Button(item.name) { face.loadSample?(item.url) }
                                }
                            } label: {
                                Label("Samples", systemImage: "square.stack.3d.down.right")
                            }
                        }
                        Button { face.loadDemo?() } label: { Label("Demo Loop", systemImage: "music.note") }
                    }
                }
                Section("Presets") {
                    ForEach(Preset.banks, id: \.self) { bank in
                        Menu(bank) {
                            ForEach(Preset.factory.indices.filter { Preset.factory[$0].bank == bank }, id: \.self) { i in
                                Button(Preset.factory[i].name) { params.apply(i) }
                            }
                        }
                    }
                }
                Section("Settings") {
                    Picker(selection: $face.faceplate) {
                        ForEach(Faceplate.allCases, id: \.self) { f in Text(f.title).tag(f) }
                    } label: {
                        Label("Faceplate", systemImage: "paintbrush")
                    }
                    .pickerStyle(.menu)
                }
            } label: {
                Text(params.presetName)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Plate.text)
                    .frame(width: 290, height: 53)
                    .contentShape(Rectangle())
            }
            .helpTarget(.presets, face)
            .place(x: 578, y: 25, w: 290, h: 53)

            // A / B
            abCell("A", on: !params.onB, x: 958) { params.selectSlot(b: false) }
            abCell("B", on: params.onB, x: 1015) { params.selectSlot(b: true) }

            // undo (the icon is part of the picture)
            HitArea { params.undo() }
                .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(params.canUndo ? 0 : 0.45)).padding(3)
                    .allowsHitTesting(false))
                .helpTarget(.undo, face).place(x: 1112, y: 26, w: 62, h: 53)

            // ? help key
            Button {
                face.helpEnabled.toggle()
                if face.helpEnabled { face.showHelp(.help) }
            } label: {
                ZStack {
                    if face.helpEnabled {
                        RoundedRectangle(cornerRadius: 9).stroke(Plate.glow.opacity(0.9), lineWidth: 2)
                            .shadow(color: Plate.glow, radius: 6).padding(3)
                    }
                    Text("?")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(face.helpEnabled ? Plate.glowHot : Plate.glow)
                        .shadow(color: Plate.glow.opacity(face.helpEnabled ? 1 : 0.5), radius: face.helpEnabled ? 8 : 3)
                }
                .frame(width: 62, height: 54).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { face.showHelp(.help) } else { face.hoverEnded(.help) } }
            .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [.help: $0] }
            .place(x: 1182, y: 27, w: 62, h: 54)

            // power (lit in the picture); off = dark glass over it
            Button { face.togglePower() } label: {
                ZStack {
                    if !face.isPowered {
                        Circle().fill(Color.black.opacity(0.62)).padding(4)
                        Image(systemName: "power")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .frame(width: 70, height: 70).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .helpTarget(.power, face)
            .place(x: 1275, y: 17, w: 70, h: 70)
        }
    }

    private func abCell(_ letter: String, on: Bool, x: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(theme.image(on ? "RCABLit" : "RCABOff")).resizable()
                Text(letter)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(on ? Plate.glow : theme.textDim)
                    .shadow(color: on ? Plate.glow.opacity(0.8) : .clear, radius: 5)
            }
            .frame(width: 57, height: 51).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .helpTarget(.ab, face)
        .place(x: x, y: 28, w: 57, h: 51)
    }

    // MARK: Meters, screen, CLIP readout

    private var displays: some View {
        ZStack(alignment: .topLeading) {
            PlateMeters(reader: face.meters, isInput: true)
                .helpTarget(.inputMeter, face).place(x: 111, y: 148, w: 72, h: 251)
            PlateMeters(reader: face.meters, isInput: false)
                .helpTarget(.outputMeter, face).place(x: 1224, y: 148, w: 75, h: 251)
            PlateScreen(shared: face.shared, ceilingDB: params[.ceilingDB], reader: face.meters)
                .helpTarget(.screen, face).place(x: 268, y: 126, w: 914, h: 260)
            PlateClipNumber(reader: face.meters)
                .helpTarget(.clipReadout, face).place(x: 591, y: 402, w: 266, h: 53)
        }
    }

    // MARK: Knobs

    private var knobs: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.bigKnobs.indices, id: \.self) { i in
                let item = Self.bigKnobs[i]
                PlateKnob(value: params.binding(item.0), range: item.0.range, defaultValue: item.0.defaultValue,
                          capRadius: 56, pointerFrom: 34, pointerTo: 53, pointerWidth: 5, theme: theme)
                    .helpTarget(item.2, face)
                    .place(x: item.1.x - 80, y: item.1.y - 80, w: 160, h: 160)
                PlateValue(text: Self.valueText(item.0, params[item.0]), size: 21, theme: theme)
                    .place(x: item.1.x - 70, y: 676, w: 140, h: 30)
            }
        }
    }

    static func valueText(_ p: Param, _ v: Float) -> String {
        switch p {
        case .inputDB, .outputDB: return Fmt.db(v)
        case .driveDB, .ceilingDB: return Fmt.dbPlain(v)
        default: return Fmt.pct(v)
        }
    }

    // MARK: Red / Fire / Box Tone / Delta

    private var redRow: some View {
        ZStack(alignment: .topLeading) {
            PlateKnob(value: params.binding(.gold), range: Param.gold.range, defaultValue: 0,
                      capRadius: 31, pointerFrom: 17, pointerTo: 29, pointerWidth: 4, theme: theme)
                .helpTarget(.red, face)
                .place(x: Self.redKnob.x - 48, y: Self.redKnob.y - 48, w: 96, h: 96)
            PlateValue(text: Fmt.pct(params[.gold]), size: 15, theme: theme)
                .place(x: Self.redKnob.x - 36, y: 845, w: 72, h: 24)

            PlateSegments(cells: [("MODERN", 282, 387), ("CLASSIC", 387, 490)], y: 758, h: 33,
                          selection: params.binding(.goldMode), fontSize: 14, theme: theme)
                .helpTarget(.redStyle, face).place(x: 282, y: 758, w: 208, h: 33)
            PlateToggle(title: "UNITY GAIN", icon: nil, isOn: params.flag(.unity), fontSize: 15, offColor: theme.text)
                .helpTarget(.unity, face).place(x: 312, y: 808, w: 152, h: 35)

            PlateKnob(value: params.binding(.alchemy), range: Param.alchemy.range, defaultValue: 0,
                      capRadius: 31, pointerFrom: 17, pointerTo: 29, pointerWidth: 4, theme: theme)
                .helpTarget(.fire, face)
                .place(x: Self.fireKnob.x - 48, y: Self.fireKnob.y - 48, w: 96, h: 96)
            PlateValue(text: Fmt.pct(params[.alchemy]), size: 15, theme: theme)
                .place(x: Self.fireKnob.x - 36, y: 845, w: 72, h: 24)

            PlateSegments(cells: [("FLAT", 820, 912), ("MODERN", 912, 1013), ("CLASSIC", 1013, 1116)], y: 792, h: 40,
                          selection: params.binding(.boxTone), fontSize: 14, theme: theme)
                .helpTarget(.boxTone, face).place(x: 820, y: 792, w: 296, h: 40)
            PlateToggle(title: "DELTA", icon: "triangle", isOn: params.flag(.delta), fontSize: 16, offColor: Plate.glow)
                .helpTarget(.delta, face).place(x: 1180, y: 794, w: 133, h: 40)
        }
    }

    // MARK: Clip Mode / Link / Oversampling / Bypass

    private var bottomRow: some View {
        ZStack(alignment: .topLeading) {
            PlateSegments(cells: [("HARD", 123, 243), ("CLASSIC", 243, 363), ("MODERN", 363, 486)], y: 922, h: 46,
                          selection: params.binding(.clipMode), fontSize: 16, theme: theme)
                .helpTarget(.clipMode, face).place(x: 123, y: 922, w: 363, h: 46)
            PlateToggle(title: "LINK", icon: "link", isOn: params.flag(.link), fontSize: 17, offColor: Plate.glow)
                .helpTarget(.link, face).place(x: 567, y: 908, w: 123, h: 50)
            PlateSegments(cells: [("1X", 767, 877), ("2X", 877, 982), ("4X", 982, 1093)], y: 922, h: 44,
                          selection: params.binding(.oversampling), fontSize: 16, theme: theme)
                .helpTarget(.oversampling, face).place(x: 767, y: 922, w: 326, h: 44)
            PlateBypass(isOn: params.flag(.bypass), theme: theme)
                .helpTarget(.bypass, face).place(x: 1162, y: 907, w: 165, h: 51)
        }
    }
}

// MARK: - Faceplate finishes

/// Face1 is the red picture; Face1_platinum is the same face in a platinum finish.
enum Faceplate: String, CaseIterable {
    case face1 = "Face1"
    case face1Platinum = "Face1_platinum"

    var title: String { self == .face1 ? "Face1 (Red)" : "Face1 Platinum" }
}

/// What changes between finishes: the pictures and the colour of the printed legends.
struct PlateTheme {
    let suffix: String              // asset-name suffix, "" or "Platinum"
    let text: Color                 // values, unlit legends
    let textDim: Color              // unselected A/B letter
    let litText: Color              // legend on a lit red cell
    let textShadow: Color
    let pointer: [Color]            // knob pointer gradient

    func image(_ base: String) -> String { base + suffix }

    static let red = PlateTheme(
        suffix: "",
        text: Color(red: 0.97, green: 0.94, blue: 0.93),
        textDim: Color(white: 0.72),
        litText: Color(red: 0.32, green: 0.02, blue: 0.03),
        textShadow: .black.opacity(0.45),
        pointer: [Color(red: 1, green: 0.97, blue: 0.9), Color(red: 0.86, green: 0.82, blue: 0.75)])

    static let platinum = PlateTheme(
        suffix: "Platinum",
        text: Color(red: 0.13, green: 0.13, blue: 0.14),
        textDim: Color(white: 0.3),
        litText: Color(red: 1, green: 0.96, blue: 0.95),
        textShadow: .white.opacity(0.5),
        pointer: [Color(white: 0.12), Color(white: 0.02)])
}

// MARK: - Colours and layout helpers

enum Plate {
    static let text = Color(red: 0.97, green: 0.94, blue: 0.93)
    static let textDim = Color(white: 0.72)
    static let glow = Color(red: 1.0, green: 0.27, blue: 0.27)
    static let glowHot = Color(red: 1.0, green: 0.55, blue: 0.52)
    static let litText = Color(red: 0.32, green: 0.02, blue: 0.03)
}

extension View {
    /// Puts a view at a rectangle given in picture pixels (top-left origin).
    func place(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }
}

/// An invisible button over a part of the picture.
struct HitArea: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}

// MARK: - Knob (cap is in the picture; only the pointer moves)

struct PlateKnob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let capRadius: CGFloat
    let pointerFrom: CGFloat
    let pointerTo: CGFloat
    let pointerWidth: CGFloat
    let theme: PlateTheme
    @State var dragStart: Float?

    var body: some View {
        let span = range.upperBound - range.lowerBound
        let norm = Double((value - range.lowerBound) / span)
        let length: CGFloat = pointerTo - pointerFrom
        let mid: CGFloat = (pointerFrom + pointerTo) / 2
        ZStack {
            Color.clear
            Capsule()
                .fill(LinearGradient(colors: theme.pointer, startPoint: .top, endPoint: .bottom))
                .frame(width: pointerWidth, height: length)
                .shadow(color: .black.opacity(0.55), radius: 1, x: 0.5, y: 1)
                .offset(y: -mid)
                .rotationEffect(.degrees(-135 + 270 * norm))
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if dragStart == nil { dragStart = value }
                    // Tension: a full sweep takes 900 points of drag on every knob, big or small
                    let delta = Float(-g.translation.height + g.translation.width * 0.3) / 900 * span
                    value = min(max((dragStart ?? value) + delta, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
    }
}

/// The value printed under a knob.
struct PlateValue: View {
    let text: String
    let size: CGFloat
    let theme: PlateTheme
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(theme.text)
            .shadow(color: theme.textShadow, radius: 1, y: 1)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

// MARK: - Segmented selectors (lit / unlit cell textures from the picture)

struct PlateSegments: View {
    /// (label, left x, right x) in picture pixels
    let cells: [(String, CGFloat, CGFloat)]
    let y: CGFloat
    let h: CGFloat
    @Binding var selection: Float
    let fontSize: CGFloat
    let theme: PlateTheme

    var body: some View {
        let x0: CGFloat = cells.first?.1 ?? 0
        ZStack(alignment: .topLeading) {
            ForEach(cells.indices, id: \.self) { i in
                cell(i, x0: x0)
            }
        }
    }

    private func cell(_ i: Int, x0: CGFloat) -> some View {
        let (label, l, r) = cells[i]
        let on = Int(selection.rounded()) == i
        return Button { selection = Float(i) } label: {
            ZStack {
                Image(theme.image(on ? "RCSegLit" : "RCSegOff")).resizable()
                Text(label)
                    .font(.system(size: fontSize, weight: .semibold))
                    .tracking(fontSize * 0.12)
                    .foregroundStyle(on ? theme.litText : theme.text)
            }
            .frame(width: r - l, height: h).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .place(x: l - x0, y: 0, w: r - l, h: h)
    }
}

/// Unity / Link / Delta: the button body is in the picture; this draws the legend and the lit edge.
struct PlateToggle: View {
    let title: String
    let icon: String?
    @Binding var isOn: Bool
    let fontSize: CGFloat
    let offColor: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                if isOn {
                    RoundedRectangle(cornerRadius: 7).fill(Plate.glow.opacity(0.12))
                    RoundedRectangle(cornerRadius: 7).stroke(Plate.glow, lineWidth: 2)
                        .shadow(color: Plate.glow, radius: 6)
                }
                HStack(spacing: 8) {
                    if let icon { Image(systemName: icon).font(.system(size: fontSize * 1.05, weight: .semibold)) }
                    Text(title).font(.system(size: fontSize, weight: .semibold)).tracking(fontSize * 0.14)
                }
                .foregroundStyle(isOn ? Plate.glowHot : offColor)
                .shadow(color: isOn ? Plate.glow : .clear, radius: 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Bypass: LED dot + legend (the button body is in the picture).
struct PlateBypass: View {
    @Binding var isOn: Bool
    let theme: PlateTheme
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 18) {
                Circle()
                    .fill(isOn ? AnyShapeStyle(Plate.glow)
                               : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.6), Color(white: 0.28)],
                                                              center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 10)))
                    .frame(width: 17, height: 17)
                    .shadow(color: isOn ? Plate.glow : .black.opacity(0.5), radius: isOn ? 7 : 1)
                Text("BYPASS").font(.system(size: 17, weight: .semibold)).tracking(2.4)
                    .foregroundStyle(theme.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meters (two LED columns in the picture's slots)

struct PlateMeters: View {
    let reader: MeterReader
    let isInput: Bool
    private let segments = 24

    var body: some View {
        TimelineView(.animation) { ctx in
            let _ = reader.update(ctx.date)
            let l = isInput ? reader.inL : reader.outL
            let r = isInput ? reader.inR : reader.outR
            let hold = isInput ? reader.inHold : reader.outHold
            let over = isInput ? reader.clipLit : hold >= 0.999
            Canvas { g, size in
                // the two slots: 32 px wide at the left and right edges (as in the picture)
                let slotW: CGFloat = 32
                draw(g, CGRect(x: 0, y: 0, width: slotW, height: size.height), level: l, hold: hold, over: over)
                draw(g, CGRect(x: size.width - slotW, y: 0, width: slotW, height: size.height), level: r, hold: hold, over: over)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ slot: CGRect, level g: Float, hold: Float, over: Bool) {
        let inner = slot.insetBy(dx: 3, dy: 3)
        ctx.fill(Path(roundedRect: inner, cornerRadius: 3), with: .color(Color.black))
        let level: CGFloat = 1 - FaceScale.position(gainToDB(g))
        let holdLevel: CGFloat = 1 - FaceScale.position(gainToDB(hold))
        let n = CGFloat(segments)
        let padY: CGFloat = 5, gap: CGFloat = 2.6
        let segH: CGFloat = (inner.height - 2 * padY - gap * (n - 1)) / n
        let holdIdx = Int((holdLevel * n).rounded(.up)) - 1
        for idx in 0..<segments {
            let lo = CGFloat(idx) / n
            let fill: CGFloat = min(max((level - lo) * n, 0), 1)
            let top = idx >= segments - 3
            let y: CGFloat = inner.maxY - padY - CGFloat(idx + 1) * segH - CGFloat(idx) * gap
            let rect = CGRect(x: inner.minX + 4, y: y, width: inner.width - 8, height: segH)
            let shape = Path(roundedRect: rect, cornerRadius: 1.5)
            ctx.fill(shape, with: .color(Color(red: 0.26, green: 0.03, blue: 0.04)))
            var lit: CGFloat = fill
            if idx == holdIdx && holdLevel > 0.02 { lit = max(lit, 0.9) }
            if top && over { lit = 1 }
            if lit > 0 {
                var glow = ctx
                glow.addFilter(.shadow(color: Plate.glow.opacity(Double(0.8 * lit)), radius: 4))
                let c = top ? (over ? Color.white : Plate.glowHot) : Color(red: 1, green: 0.1, blue: 0.1)
                glow.fill(shape, with: .color(c.opacity(Double(0.25 + 0.75 * lit))))
            }
        }
    }
}

// MARK: - Screen (the picture's glass and dB labels stay; the trace is drawn over them)

struct PlateScreen: View {
    let shared: SharedState
    let ceilingDB: Float
    let reader: MeterReader

    // the plot inside this view (the view sits at x 268, y 126 in the picture):
    // 0 dB line at y 162, -60 at y 371, traces from x 317 to 1167
    static let plot = CGRect(x: 317 - 268, y: 162 - 126, width: 1167 - 317, height: 371 - 162)

    var body: some View {
        TimelineView(.animation) { ctx in
            let _ = reader.update(ctx.date)
            let scroll = reader.scroller.update(total: shared.waveTotal.pointee,
                                                rate: Double(shared.waveRate.pointee), now: ctx.date)
            let screen = WaveformView(shared: shared, ceilingDB: ceilingDB, reader: reader)
            let labelY: CGFloat = Self.plot.minY + FaceScale.position(ceilingDB) * Self.plot.height - 14
            ZStack(alignment: .topLeading) {
                Canvas { g, _ in screen.draw(g, Self.plot, scroll) }
                Text(String(format: "CEILING  %.1f dB", ceilingDB))
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1.2)
                    .underline(color: Plate.glow)
                    .foregroundStyle(reader.reduction > 0.05 ? Plate.glowHot : Plate.glow)
                    .shadow(color: Plate.glow.opacity(0.9), radius: 3 + CGFloat(min(reader.reduction, 6)) * 1.5)
                    .fixedSize()
                    .position(x: Self.plot.maxX - 64, y: labelY)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The number in the CLIP readout ("CLIP" and "dB" are in the picture).
struct PlateClipNumber: View {
    let reader: MeterReader
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let _ = reader.update(ctx.date)
            Text(String(format: "%.1f", reader.reduction))
                .font(.system(size: 38, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.3))
                .shadow(color: Plate.glow.opacity(0.85), radius: 6)
                .position(x: 738 - 591, y: 428 - 402)
        }
    }
}
