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
            PlateMeters(shared: face.shared, state: face.meters.stereo, isInput: true)
                .helpTarget(.inputMeter, face).place(x: 111, y: 148, w: 72, h: 251)
            PlateMeters(shared: face.shared, state: face.meters.stereo, isInput: false)
                .helpTarget(.outputMeter, face).place(x: 1224, y: 148, w: 75, h: 251)
            PlateScreen(shared: face.shared, ceilingDB: params[.ceilingDB])
                .helpTarget(.screen, face).place(x: 273, y: 128, w: 910, h: 258)
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

// MARK: - Meters (from the RED CLIP animation pack: RMS-style LEDs with a separate peak hold)

/// Level detectors for the four LED strips: ~20 ms RMS window, 40 ms rise / 250 ms fall smoothing,
/// peak markers that hold for 600 ms and then fall at 20 dB/s. Fed from the audio thread's
/// sample rings (input after the Input knob, final output). These are digital RMS-style level
/// meters, not calibrated analog VU meters.
final class StereoMeterState {
    private(set) var levels = [Double](repeating: 0, count: 4)     // inL, inR, outL, outR (linear RMS)
    private(set) var hold = [Double](repeating: -60, count: 4)     // dBFS
    private var timers = [Double](repeating: 0, count: 4)
    private var last: Date?
    private var lastTotal = -1

    func update(_ shared: SharedState, now: Date) {
        let dt = min(max(now.timeIntervalSince(last ?? now), 0), 0.1)
        if let last, now.timeIntervalSince(last) < 0.008 { return }      // once per frame
        last = now
        let total = shared.ringTotal.pointee
        let moving = total != lastTotal
        lastTotal = total
        let window = max(1, Int(Double(shared.sampleRate.pointee) * 0.02))
        let rings = [shared.meterInL, shared.meterInR, shared.meterOutL, shared.meterOutR]
        for n in 0..<4 {
            var sum: Double = 0, peak: Double = 0
            if moving {
                for k in 0..<window {
                    let v = Double(rings[n][(total - 1 - k) & SharedState.ringMask])
                    sum += v * v
                    peak = max(peak, abs(v))
                }
            }
            let rms = (sum / Double(window)).squareRoot()
            let coeff = exp(-dt / (rms > levels[n] ? 0.04 : 0.25))
            levels[n] = coeff * levels[n] + (1 - coeff) * rms
            let pdb = 20 * log10(max(peak, 1e-6))
            timers[n] = max(0, timers[n] - dt)
            if timers[n] == 0 { hold[n] -= 20 * dt }
            if pdb >= hold[n] { hold[n] = pdb; timers[n] = 0.6 }
            hold[n] = max(hold[n], -80)
        }
    }
}

/// Two LED strips in the picture's meter slots. Positions are the faceplate pixels used by the
/// animation pack (strip x ranges, and the 24 segment rows).
struct PlateMeters: View {
    let shared: SharedState
    let state: StereoMeterState
    let isInput: Bool

    /// The view sits at x 111 (input) / 1224 (output), y 148 in the picture.
    static let originX: (input: CGFloat, output: CGFloat) = (111, 1224)
    static let originY: CGFloat = 148
    static let strips: [(CGFloat, CGFloat)] = [(115, 135), (157, 176), (1231, 1250), (1274, 1292)]
    static let slots: [(CGFloat, CGFloat)] = [(154, 160), (166, 169), (175, 179), (183, 188), (193, 197), (202, 208),
        (210, 216), (220, 226), (229, 236), (240, 245), (250, 256), (260, 266), (270, 276), (281, 286),
        (291, 297), (301, 307), (312, 317), (322, 327), (332, 338), (342, 348), (353, 359), (362, 369),
        (373, 379), (383, 390)]
    /// The face's scale marks: pixel rows for 0, -6, -12, -18, -24, -36, -60 dB.
    static let markY: [CGFloat] = [154, 201, 244, 285, 328, 371, 390]
    static let markDB: [CGFloat] = [0, -6, -12, -18, -24, -36, -60]

    static func dbAt(y: CGFloat) -> CGFloat { interp(y, markY, markDB) }
    static func yAt(db: CGFloat) -> CGFloat { interp(db, markDB.reversed(), markY.reversed()) }
    static func interp(_ v: CGFloat, _ xs: [CGFloat], _ ys: [CGFloat]) -> CGFloat {
        if v <= xs[0] { return ys[0] }
        for i in 1..<xs.count where v <= xs[i] {
            return ys[i - 1] + (ys[i] - ys[i - 1]) * (v - xs[i - 1]) / (xs[i] - xs[i - 1])
        }
        return ys[ys.count - 1]
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let _ = state.update(shared, now: ctx.date)
            Canvas { g, _ in
                let ox = isInput ? Self.originX.input : Self.originX.output
                let oy = Self.originY
                for n in (isInput ? 0..<2 : 2..<4) {
                    let (x0, x1) = Self.strips[n]
                    let db = 20 * log10(max(state.levels[n], 1e-6))
                    g.fill(Path(CGRect(x: x0 - 1 - ox, y: 152 - oy, width: x1 - x0 + 3, height: 242)),
                           with: .color(Color(red: 0.039, green: 0.027, blue: 0.031)))
                    for (y0, y1) in Self.slots {
                        let threshold = Self.dbAt(y: (y0 + y1) / 2)
                        let active = CGFloat(db) >= threshold
                        let rect = CGRect(x: x0 - ox, y: y0 - oy, width: x1 - x0 + 1, height: y1 - y0 + 1)
                        let grad = Gradient(stops: [
                            .init(color: active ? Color(hex: 0x962025) : Color(hex: 0x20080b), location: 0),
                            .init(color: active ? Color(hex: 0xf51518) : Color(hex: 0x2a080b), location: 0.5),
                            .init(color: active ? Color(hex: 0x960608) : Color(hex: 0x1e0609), location: 1)])
                        g.fill(Path(rect), with: .linearGradient(grad, startPoint: CGPoint(x: 0, y: rect.minY),
                                                                 endPoint: CGPoint(x: 0, y: rect.maxY)))
                        g.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)),
                               with: .color(active ? Color(hex: 0xff393f) : Color(hex: 0x3a0f12)))
                    }
                    let py = Self.yAt(db: CGFloat(min(max(state.hold[n], -60), 0)))
                    g.fill(Path(CGRect(x: x0 - ox, y: py - oy, width: x1 - x0 + 1, height: 2)),
                           with: .color(Color(hex: 0xff8587)))
                }
            }
        }
    }
}

// MARK: - Screen (from the RED CLIP animation pack: time-aligned input vs clipped output)

/// Oscilloscope over the picture's screen: the last 120 ms of the signal going into the clipper
/// (grey) and the clipped output (red, filled), on a linear bipolar amplitude axis with the
/// +/- ceiling dashed. Fed from the audio thread's sample rings; nothing here touches the audio.
struct PlateScreen: View {
    let shared: SharedState
    let ceilingDB: Float

    static let points = 1300
    // layout in the scope's own 910 x 258 space (the view sits at x 273, y 128 in the picture)
    static let left: CGFloat = 57, right: CGFloat = 891, cy: CGFloat = 133, scale: CGFloat = 56

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { g, size in
                let sx = size.width / 910, sy = size.height / 258
                g.scaleBy(x: sx, y: sy)
                draw(g)
            }
        }
        .allowsHitTesting(true)
    }

    private func draw(_ c: GraphicsContext) {
        let L = Self.left, R = Self.right, cy = Self.cy, k = Self.scale
        c.fill(Path(CGRect(x: 0, y: 0, width: 910, height: 258)), with: .color(Color(hex: 0x0b0c0e)))
        c.fill(Path(CGRect(x: 0, y: 0, width: 910, height: 258)),
               with: .radialGradient(Gradient(colors: [Color(red: 0.627, green: 0.667, blue: 0.725).opacity(0.07),
                                                       Color(red: 0.627, green: 0.667, blue: 0.725).opacity(0)]),
                                     center: CGPoint(x: 90, y: 25), startRadius: 1, endRadius: 260))
        // amplitude grid + labels
        for step in 0...6 {
            let v = -1.5 + Double(step) * 0.5
            let y = cy - CGFloat(v) * k
            var p = Path(); p.move(to: CGPoint(x: L, y: y)); p.addLine(to: CGPoint(x: R, y: y))
            c.stroke(p, with: .color(v == 0 ? Color(hex: 0x292a2c) : Color(hex: 0x191a1c)), lineWidth: 1)
            let label = v == 0 ? "0" : (v > 0 ? "+" : "") + String(format: "%.1f", v)
            c.draw(Text(label).font(.system(size: 11)).foregroundColor(Color(hex: 0x898d93)),
                   at: CGPoint(x: 9, y: y), anchor: .leading)
        }
        for j in 0...12 {
            let x = L + (R - L) * CGFloat(j) / 12
            var p = Path(); p.move(to: CGPoint(x: x, y: 42)); p.addLine(to: CGPoint(x: x, y: 244))
            c.stroke(p, with: .color(Color(hex: 0x18191b)), lineWidth: 1)
        }
        // +/- ceiling
        let ceil = CGFloat(dbToGain(ceilingDB))
        for sgn: CGFloat in [-1, 1] {
            var p = Path(); p.move(to: CGPoint(x: L, y: cy - sgn * ceil * k)); p.addLine(to: CGPoint(x: R, y: cy - sgn * ceil * k))
            c.stroke(p, with: .color(Color(hex: 0x91282b)), style: StrokeStyle(lineWidth: 1, dash: [6, 7]))
        }
        c.draw(Text("INPUT").font(.system(size: 13)).foregroundColor(Color(hex: 0xb3b9c2)), at: CGPoint(x: 12, y: 15), anchor: .leading)
        c.draw(Text("CLIPPED OUTPUT").font(.system(size: 13)).foregroundColor(Color(hex: 0xff4145)), at: CGPoint(x: 80, y: 15), anchor: .leading)
        c.draw(Text(String(format: "CEILING  %.1f dB", ceilingDB)).font(.system(size: 13)).foregroundColor(Color(hex: 0xff4145)),
               at: CGPoint(x: 700, y: 15), anchor: .leading)

        // the newest 120 ms from the rings
        let total = shared.ringTotal.pointee
        let span = max(2, min(SharedState.ringSize - 8, Int(Double(shared.sampleRate.pointee) * 0.12)))
        let n = Self.points
        if total > 4 {
            let newest = total - 1
            func sample(_ ring: UnsafeMutablePointer<Float>, _ i: Int) -> CGFloat {
                let back = span - 1 - (i * (span - 1)) / (n - 1)
                let v = CGFloat(ring[(newest - back) & SharedState.ringMask])
                return max(min(v, 2.2), -2.2)        // keep the trace on the glass
            }
            func path(_ ring: UnsafeMutablePointer<Float>) -> Path {
                var p = Path()
                for i in 0..<n {
                    let pt = CGPoint(x: L + (R - L) * CGFloat(i) / CGFloat(n - 1), y: cy - sample(ring, i) * k)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                return p
            }
            let out = path(shared.scopePost)
            var fill = out
            fill.addLine(to: CGPoint(x: R, y: cy)); fill.addLine(to: CGPoint(x: L, y: cy)); fill.closeSubpath()
            c.fill(fill, with: .color(Color(hex: 0x390f13)))
            c.stroke(path(shared.scopePre), with: .color(Color(hex: 0x89929f)), lineWidth: 2)
            c.stroke(out, with: .color(Color(hex: 0xff3d42)), lineWidth: 3)
        }
        c.draw(Text("AMPLITUDE").font(.system(size: 11)).foregroundColor(Color(hex: 0x666b72)), at: CGPoint(x: 12, y: 242), anchor: .leading)
        c.draw(Text("120 ms").font(.system(size: 11)).foregroundColor(Color(hex: 0x666b72)), at: CGPoint(x: 770, y: 242), anchor: .leading)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
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
