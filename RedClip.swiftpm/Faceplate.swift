import SwiftUI

/// The Red Clip faceplate: Tyrone's picture (iPad: RCPlate, full screen; iPhone: RCPhonePlate; with every
/// moving part removed) with the live parts drawn on top in exactly the same places: knob
/// pointers and values, LED meters, the screen, the CLIP readout, the lit buttons and their labels.
/// Positions come from a PlateLayout in picture pixels; the iPad and iPhone faces share all of
/// this code, so every control behaves the same on both. The app and the AUv3 plug-in both show
/// this view and scale it to fit.
@MainActor
struct FaceplateView: View {
    @ObservedObject var face: FaceModel
    @ObservedObject var params: ParamStore
    var layout: PlateLayout? = nil

    private var theme: PlateTheme { face.theme }
    private var L: PlateLayout { layout ?? .current(face.faceplate) }

    /// In a DAW the iPhone face is cropped above its built-in transport.
    private var height: CGFloat { face.isPlugin ? L.pluginHeight : L.size.height }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(theme.image(L.plate))
                .resizable()
                .interpolation(.high)
                .frame(width: L.size.width, height: L.size.height)
            header
            displays
            knobs
            selectors
        }
        .frame(width: L.size.width, height: height, alignment: .topLeading)
        .clipped()
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            // preset: arrows step, the name opens the menu (Audio first, then Presets)
            HitArea { params.stepPreset(-1) }
                .helpTarget(.presets, face).place(L.presetPrev)
            HitArea { params.stepPreset(1) }
                .helpTarget(.presets, face).place(L.presetNext)
            Button { face.toggleRCMenu() } label: {
                Text(params.presetName)
                    .font(.system(size: L.presetFont, weight: .regular))
                    .foregroundStyle(Plate.text)
                    .lineLimit(1)
                    .frame(width: L.presetName.width, height: L.presetName.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open preset menu, \(params.presetName)")
            .rcMenuAnchor(.presets, face: face)
            .helpTarget(.presets, face)
            .place(L.presetName)

            // A / B
            abCell("A", on: !params.onB, rect: L.a) { params.selectSlot(b: false) }
            abCell("B", on: params.onB, rect: L.b) { params.selectSlot(b: true) }

            // undo (the icon is part of the picture)
            HitArea { params.undo() }
                .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(params.canUndo ? 0 : 0.45)).padding(3)
                    .allowsHitTesting(false))
                .helpTarget(.undo, face).place(L.undo)

            // ? help key (works like Console E's: toggle; touch or hover a control for its bubble)
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
                        .font(.system(size: L.helpFont, weight: .bold, design: .rounded))
                        .foregroundStyle(face.helpEnabled ? Plate.glowHot : Plate.glow)
                        .shadow(color: Plate.glow.opacity(face.helpEnabled ? 1 : 0.5), radius: face.helpEnabled ? 8 : 3)
                }
                .frame(width: L.help.width, height: L.help.height).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { face.showHelp(.help) } else { face.hoverEnded(.help) } }
            .anchorPreference(key: HelpAnchorKey.self, value: .bounds) { [.help: $0] }
            .place(L.help)

            // power (lit in the picture); off = dark glass over it
            Button { face.togglePower() } label: {
                ZStack {
                    if !face.isPowered {
                        Circle().fill(Color.black.opacity(0.62)).padding(4)
                        Image(systemName: "power")
                            .font(.system(size: L.powerIcon, weight: .bold))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .frame(width: L.power.width, height: L.power.height).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .helpTarget(.power, face)
            .place(L.power)
        }
    }

    private func abCell(_ letter: String, on: Bool, rect: CGRect, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Image(theme.image(on ? L.abLit : L.abOff)).resizable()
                Text(letter)
                    .font(.system(size: L.letterFont, weight: .semibold))
                    .foregroundStyle(on ? Plate.glow : theme.textDim)
                    .shadow(color: on ? Plate.glow.opacity(0.8) : .clear, radius: 5)
            }
            .frame(width: rect.width, height: rect.height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .helpTarget(.ab, face)
        .place(rect)
    }

    // MARK: Meters, screen, CLIP readout

    private var displays: some View {
        ZStack(alignment: .topLeading) {
            PlateMeters(shared: face.shared, state: face.meters.stereo, isInput: true, geometry: L.meterIn)
                .helpTarget(.inputMeter, face).place(L.meterIn.frame)
            PlateMeters(shared: face.shared, state: face.meters.stereo, isInput: false, geometry: L.meterOut)
                .helpTarget(.outputMeter, face).place(L.meterOut.frame)
            PlateScreen(shared: face.shared, scope: face.meters.scope, ceilingDB: params[.ceilingDB], isPlugin: face.isPlugin)
                .helpTarget(.screen, face).place(L.screen)
            PlateClipNumber(reader: face.meters, center: CGPoint(x: L.clipNumber.x - L.clip.minX, y: L.clipNumber.y - L.clip.minY),
                            fontSize: L.clipFont)
                .helpTarget(.clipReadout, face).place(L.clip)
            clipClock
        }
    }

    /// The Clip Clock panel in the bottom-left corner of the screen's glass (screen units, 258 high).
    private var clipClock: some View {
        let s = L.screen.height / PlateScreen.H, size = ClipClockPanel.size
        return ClipClockPanel(clock: face.shared.clipClock, onReset: face.clipClockReset)
            .scaleEffect(s)
            .helpTarget(.clipClock, face)
            .place(x: L.screen.minX + 60 * s, y: L.screen.minY + 166 * s, w: size.width * s, h: size.height * s)
    }

    // MARK: Knobs (Input, Drive, Ceiling, Mix, Output, Red, Fire)

    private var knobs: some View {
        ZStack(alignment: .topLeading) {
            ForEach(L.knobs.indices, id: \.self) { i in
                let k = L.knobs[i]
                let box = k.pointerTo * 1.55
                // MIX turns the Wet level while the parallel mixer is unlinked
                let p = k.param == .mix && params.mixUnlinked ? Param.wet : k.param
                PlateKnob(value: params.binding(p), range: p.range, defaultValue: p.defaultValue,
                          capRadius: k.pointerTo, pointerFrom: k.pointerFrom, pointerTo: k.pointerTo,
                          pointerWidth: k.pointerWidth, theme: theme)
                    .helpTarget(k.topic, face)
                    .place(x: k.center.x - box, y: k.center.y - box, w: box * 2, h: box * 2)
                if k.param == .mix {
                    mixReadout(k)
                } else {
                    PlateValue(text: Self.valueText(k.param, params[k.param]), size: k.valueFont, theme: theme)
                        .place(k.value)
                }
            }
        }
    }

    /// The value under MIX opens the parallel mixer (separate Dry and Wet). Unlinked, it shows both levels.
    private func mixReadout(_ k: PlateLayout.Knob) -> some View {
        let text = params.mixUnlinked
            ? String(format: "D %.0f  W %.0f", params[.dry], params[.wet])
            : Self.valueText(.mix, params[.mix])
        return Button { face.toggleRCMenu(page: .mixer, anchor: .mixer) } label: {
            ZStack {
                Color.clear
                PlateValue(text: text, size: k.valueFont, theme: theme)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open parallel mixer, \(text)")
        .rcMenuAnchor(.mixer, face: face)
        .helpTarget(.mixer, face)
        .place(k.value)
    }

    static func valueText(_ p: Param, _ v: Float) -> String {
        switch p {
        case .inputDB, .outputDB: return Fmt.db(v)
        case .driveDB, .ceilingDB: return Fmt.dbPlain(v)
        default: return Fmt.pct(v)
        }
    }

    // MARK: Red style / Box Tone / Clip Mode / Oversampling, Unity / Delta / Link / Bypass

    private var selectors: some View {
        ZStack(alignment: .topLeading) {
            ForEach(L.segments.indices, id: \.self) { i in
                let s = L.segments[i]
                let x0 = s.cells.first?.1 ?? 0, x1 = s.cells.last?.2 ?? 0
                PlateSegments(cells: s.cells, y: s.y, h: s.h, selection: params.binding(s.param),
                              fontSize: s.font, theme: theme, lit: L.segLit, off: L.segOff)
                    .helpTarget(s.topic, face).place(x: x0, y: s.y, w: x1 - x0, h: s.h)
            }
            PlateToggle(title: "UNITY GAIN", icon: nil, isOn: params.flag(.unity), fontSize: L.unity.font, offColor: theme.text)
                .helpTarget(.unity, face).place(L.unity.rect)
            PlateToggle(title: "DELTA", icon: "triangle", isOn: params.flag(.delta), fontSize: L.delta.font, offColor: Plate.glow)
                .helpTarget(.delta, face).place(L.delta.rect)
            PlateToggle(title: "LINK", icon: "link", isOn: params.flag(.link), fontSize: L.link.font, offColor: Plate.glow)
                .helpTarget(.link, face).place(L.link.rect)
            PlateBypass(isOn: params.flag(.bypass), theme: theme, fontSize: L.bypass.font)
                .helpTarget(.bypass, face).place(L.bypass.rect)
        }
    }
}

// MARK: - Faceplate finishes

/// Face1 is the red picture; Face1_platinum is the same face in a platinum finish.
enum Faceplate: String, CaseIterable {
    case face1 = "Face1"
    case face1Platinum = "Face1_platinum"

    var title: String { self == .face1 ? "RedClip Standard" : "RedClip Platinum" }
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
    func place(_ r: CGRect) -> some View {
        place(x: r.minX, y: r.minY, w: r.width, h: r.height)
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
            .minimumScaleFactor(0.6)
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
    var lit = "RCSegLit"
    var off = "RCSegOff"

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
                Image(theme.image(on ? lit : off)).resizable()
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
    var fontSize: CGFloat = 17
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: fontSize * 1.06) {
                Circle()
                    .fill(isOn ? AnyShapeStyle(Plate.glow)
                               : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.6), Color(white: 0.28)],
                                                              center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 10)))
                    .frame(width: fontSize, height: fontSize)
                    .shadow(color: isOn ? Plate.glow : .black.opacity(0.5), radius: isOn ? 7 : 1)
                Text("BYPASS").font(.system(size: fontSize, weight: .semibold)).tracking(fontSize * 0.14)
                    .foregroundStyle(theme.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meters (from the RED CLIP animation pack: RMS-style LEDs with a separate peak hold)

/// Level detectors for the four LED strips: 40 ms rise / 250 ms fall smoothing of the RMS of
/// every sample since the last frame, peak markers that hold for 600 ms and then fall at 20 dB/s.
/// Fed from the audio thread's sample rings (input after the Input knob, before Drive and the
/// clipper; final output after Mix, Output and Bypass, never capped at the ceiling). Every sample
/// the engine wrote counts, however the audio blocks and display frames line up; the last level
/// is kept between blocks and decays to silence once no audio has arrived for 150 ms.
/// These are digital RMS-style level meters, not calibrated analog VU meters.
final class StereoMeterState {
    static let staleAfter: TimeInterval = 0.15
    private(set) var levels = [Double](repeating: 0, count: 4)     // inL, inR, outL, outR (linear RMS)
    private(set) var hold = [Double](repeating: -120, count: 4)    // dBFS; at or below -60 nothing is drawn
    private var timers = [Double](repeating: 0, count: 4)
    private var targetRms = [Double](repeating: 0, count: 4)
    private var last: Date?
    private var lastSnapshot = Date.distantPast
    private var lastTotal = -1

    func update(_ shared: SharedState, now: Date) {
        if let last, now.timeIntervalSince(last) < 0.008 { return }      // once per frame
        let dt = min(max(now.timeIntervalSince(last ?? now), 0), 0.1)
        last = now
        let total = shared.ringTotal.acquire()
        // Samples written since the last frame. A long stall can't read more than half the ring,
        // so the audio thread is never overwriting the stretch being read.
        let fresh = lastTotal < 0 ? 0 : min(max(total &- lastTotal, 0), SharedState.ringSize / 2)
        lastTotal = total
        if fresh > 0 { lastSnapshot = now }
        let stale = now.timeIntervalSince(lastSnapshot) > Self.staleAfter
        for n in 0..<4 {
            let ring = n == 0 ? shared.meterInL : n == 1 ? shared.meterInR : n == 2 ? shared.meterOutL : shared.meterOutR
            var sum: Double = 0, peak: Double = 0
            for k in 0..<fresh {
                let v = Double(ring[(total - 1 - k) & SharedState.ringMask])
                sum += v * v
                peak = max(peak, abs(v))
            }
            if fresh > 0 { targetRms[n] = (sum / Double(fresh)).squareRoot() }
            let rms = stale ? 0 : targetRms[n]
            if stale { peak = 0 }
            let coeff = exp(-dt / (rms > levels[n] ? 0.04 : 0.25))
            levels[n] = coeff * levels[n] + (1 - coeff) * rms
            let pdb = 20 * log10(max(peak, 1e-6))
            let holdLeft = timers[n]
            timers[n] = max(0, holdLeft - dt)
            hold[n] = max(-120, hold[n] - 20 * max(0, dt - holdLeft))   // falls only once the hold runs out
            if pdb >= hold[n] { hold[n] = pdb; timers[n] = 0.6 }
        }
    }
}

/// Two LED strips in the picture's meter slots. Positions are the faceplate pixels used by the
/// animation pack (strip x ranges, and the 24 segment rows).
struct PlateMeters: View {
    let shared: SharedState
    let state: StereoMeterState
    let isInput: Bool
    let geometry: PlateLayout.Meter

    /// dB printed at each of the face's scale marks (rows come from the layout).
    static let markDB: [CGFloat] = [0, -6, -12, -18, -24, -36, -60]

    func dbAt(y: CGFloat) -> CGFloat { Self.interp(y, geometry.markY, Self.markDB) }
    func yAt(db: CGFloat) -> CGFloat { Self.interp(db, Self.markDB.reversed(), geometry.markY.reversed()) }
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
            // SwiftUI only redraws a Canvas whose captured values changed, so it takes this frame's
            // readings and time as values; reading the (unchanged) state object inside it would
            // leave the strips frozen on their first, empty frame.
            let levels = state.levels, hold = state.hold, frame = ctx.date
            Canvas { g, _ in
                _ = frame
                let ox = geometry.frame.minX
                let oy = geometry.frame.minY
                let first = isInput ? 0 : 2
                for side in 0..<2 {
                    let n = first + side
                    let (x0, x1) = geometry.strips[side]
                    let db = 20 * log10(max(levels[n], 1e-6))
                    g.fill(Path(CGRect(x: x0 - 1 - ox, y: geometry.backTop - oy, width: x1 - x0 + 3, height: geometry.backHeight)),
                           with: .color(Color(red: 0.039, green: 0.027, blue: 0.031)))
                    for (y0, y1) in geometry.slots {
                        let threshold = dbAt(y: (y0 + y1) / 2)
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
                    if hold[n] <= -60 { continue }
                    let py = yAt(db: CGFloat(min(hold[n], 0)))
                    g.fill(Path(CGRect(x: x0 - ox, y: py - oy, width: x1 - x0 + 1, height: 2)),
                           with: .color(Color(hex: 0xff8587)))
                }
            }
        }
    }
}

// MARK: - Screen (from the RED CLIP animation pack: live input vs final output)

/// The live scope on the picture's glass, read straight from the audio the engine (or the
/// host) is processing; nothing here is simulated from knob positions.
///   - grey: the original input; red: the final output (after Mix, Output and Bypass), both
///     over the same ~120 ms, lined up in time and on one fixed linear scale (+/-1.5);
///   - each display column shows the min..max of its samples, so transients survive;
///   - where the clipper took peaks off, the removed part is shaded and the +/- ceiling guide
///     lights up over it. The guides follow the Ceiling control and mark the clip stage: Mix
///     and Output can move the final output past them;
///   - 30 updates a second, suspended while the screen is hidden or the app is inactive;
///     paused audio freezes it, stopping clears it, silence is a flat line.
/// All reading happens here on the UI thread (ScopeReader); the audio thread only writes rings.
struct PlateScreen: View {
    let shared: SharedState
    let scope: ScopeReader
    let ceilingDB: Float
    var isPlugin = false
    @Environment(\.scenePhase) private var phase
    @State private var visible = false

    // Drawn in the scope's own space: 258 high, and as wide as the glass's shape needs
    // (910 on the iPad face, about 420 on the iPhone face), then scaled onto the glass.
    static let H: CGFloat = 258, left: CGFloat = 57, cy: CGFloat = 133, scale: CGFloat = 56
    static let fps = 30.0

    /// In the app, inactive or background pauses it; a plug-in window follows its own visibility.
    private var live: Bool { visible && (isPlugin || phase == .active) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / Self.fps, paused: !live)) { timeline in
            Canvas { g, size in
                let s = size.height / Self.H
                g.scaleBy(x: s, y: s)
                draw(g, W: size.width / s, frame: timeline.date)
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .allowsHitTesting(true)
    }

    private func draw(_ c: GraphicsContext, W: CGFloat, frame: Date) {
        let L = Self.left, R = W - 19, cy = Self.cy, k = Self.scale
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: 258)), with: .color(Color(hex: 0x0b0c0e)))
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: 258)),
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
        let cols = W > 600 ? 12 : 6
        for j in 0...cols {
            let x = L + (R - L) * CGFloat(j) / CGFloat(cols)
            var p = Path(); p.move(to: CGPoint(x: x, y: 42)); p.addLine(to: CGPoint(x: x, y: 244))
            c.stroke(p, with: .color(Color(hex: 0x18191b)), lineWidth: 1)
        }
        // +/- ceiling guides (clip-stage reference, from the Ceiling control)
        let ceil = CGFloat(dbToGain(ceilingDB))
        for sgn: CGFloat in [-1, 1] {
            var p = Path(); p.move(to: CGPoint(x: L, y: cy - sgn * ceil * k)); p.addLine(to: CGPoint(x: R, y: cy - sgn * ceil * k))
            c.stroke(p, with: .color(Color(hex: 0x91282b)), style: StrokeStyle(lineWidth: 1, dash: [6, 7]))
        }
        c.draw(Text("INPUT").font(.system(size: 13)).foregroundColor(Color(hex: 0xb3b9c2)), at: CGPoint(x: 12, y: 15), anchor: .leading)
        c.draw(Text("CLIPPED OUTPUT").font(.system(size: 13)).foregroundColor(Color(hex: 0xff4145)), at: CGPoint(x: 80, y: 15), anchor: .leading)
        c.draw(Text(String(format: "CEILING  %.1f dB", ceilingDB)).font(.system(size: 13)).foregroundColor(Color(hex: 0xff4145)),
               at: CGPoint(x: W - 12, y: 15), anchor: .trailing)

        // the newest ~120 ms, one column per unit of width
        _ = frame
        scope.update(shared, columns: Int(R - L))
        let n = scope.columns
        let colW = (R - L) / CGFloat(n)
        @inline(__always) func y(_ v: Float) -> CGFloat { cy - CGFloat(max(min(v, 2.2), -2.2)) * k }
        @inline(__always) func x(_ i: Int) -> CGFloat { L + (CGFloat(i) + 0.5) * colW }

        /// A min..max band across the columns, at least `thick` tall so a quiet trace still shows.
        func band(_ lo: [Float], _ hi: [Float], thick: CGFloat) -> Path {
            var p = Path()
            for i in 0..<n {
                let top = min(y(hi[i]), (y(hi[i]) + y(lo[i])) / 2 - thick / 2)
                if i == 0 { p.move(to: CGPoint(x: L, y: top)) }
                p.addLine(to: CGPoint(x: x(i), y: top))
            }
            for i in stride(from: n - 1, through: 0, by: -1) {
                let bottom = max(y(lo[i]), (y(hi[i]) + y(lo[i])) / 2 + thick / 2)
                p.addLine(to: CGPoint(x: x(i), y: bottom))
                if i == 0 { p.addLine(to: CGPoint(x: L, y: bottom)) }
            }
            p.closeSubpath()
            return p
        }

        // body of the output (dark red, between the trace and the centre line)
        var shade = Path()
        for i in 0..<n {
            let pt = CGPoint(x: x(i), y: y(max(scope.outMax[i], 0)))
            if i == 0 { shade.move(to: CGPoint(x: L, y: cy)) }
            shade.addLine(to: pt)
        }
        for i in stride(from: n - 1, through: 0, by: -1) { shade.addLine(to: CGPoint(x: x(i), y: y(min(scope.outMin[i], 0)))) }
        shade.closeSubpath()
        c.fill(shade, with: .color(Color(hex: 0x390f13)))

        // original input (grey)
        c.fill(band(scope.inMin, scope.inMax, thick: 2), with: .color(Color(hex: 0x89929f)))

        // what the clipper took off: shaded from its output up to its input, and the guide lit
        var cut = Path(), lit = Path()
        let gTop = cy - ceil * k, gBottom = cy + ceil * k
        for i in 0..<n {
            let r = scope.removed(i)
            let x0 = L + CGFloat(i) * colW
            if r.top > 0.002 {
                cut.addRect(CGRect(x: x0, y: y(scope.clipInMax[i]), width: colW + 0.5,
                                   height: max(0, y(scope.clipOutMax[i]) - y(scope.clipInMax[i]))))
                lit.addRect(CGRect(x: x0, y: gTop - 1.25, width: colW + 0.5, height: 2.5))
            }
            if r.bottom > 0.002 {
                cut.addRect(CGRect(x: x0, y: y(scope.clipOutMin[i]), width: colW + 0.5,
                                   height: max(0, y(scope.clipInMin[i]) - y(scope.clipOutMin[i]))))
                lit.addRect(CGRect(x: x0, y: gBottom - 1.25, width: colW + 0.5, height: 2.5))
            }
        }
        c.fill(cut, with: .color(Color(hex: 0xff4145).opacity(0.3)))

        // final output (red)
        c.fill(band(scope.outMin, scope.outMax, thick: 3), with: .color(Color(hex: 0xff3d42)))

        var glow = c
        glow.addFilter(.shadow(color: Color(hex: 0xff4145), radius: 4))
        glow.fill(lit, with: .color(Color(hex: 0xff6a6e)))

        c.draw(Text("AMPLITUDE").font(.system(size: 11)).foregroundColor(Color(hex: 0x666b72)), at: CGPoint(x: 12, y: 242), anchor: .leading)
        c.draw(Text("120 ms").font(.system(size: 11)).foregroundColor(Color(hex: 0x666b72)), at: CGPoint(x: W - 19, y: 242), anchor: .trailing)
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
    var center = CGPoint(x: 738 - 591, y: 428 - 402)
    var fontSize: CGFloat = 38
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            let _ = reader.update(ctx.date)
            Text(String(format: "%.1f", reader.reduction))
                .font(.system(size: fontSize, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color(red: 1, green: 0.3, blue: 0.3))
                .shadow(color: Plate.glow.opacity(0.85), radius: 6)
                .position(center)
        }
    }
}
