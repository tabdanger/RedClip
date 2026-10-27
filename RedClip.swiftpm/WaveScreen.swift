import SwiftUI

// MARK: - WAVEFORM
//
// The screen shows the newest few seconds as magnitude envelopes in dBFS, measured at two taps
// in ClipDSP.process:
//
//   INPUT    the base-rate sample after the Input and Drive gains (x * sIn * sDrive), the last
//            point before the oversampled clip stage (Red, the clipper, Broil and Alchemy all
//            run inside that stage, after this tap);
//   OUTPUT   the wet branch after the clip stage, the down-sampling filter, Box Tone and the
//            anti-overshoot clamp: the clipped signal before the Wet / Dry blend (or Delta),
//            Output, Unity and Bypass;
//   CLIPPED  the clipper's own gain reduction, |into| / |out of| the clip curve on every
//            oversampled sample (the same measure as CLIP and MAX CLIP).
//
// The wet branch leaves the oversampling filters 0 / 4 / 5 frames (1x / 2x / 4x) after the
// input went in, and the clip stage sits 0 / 2 / 2 frames ahead of the output, so the audio
// thread holds the input and clip copies back that many frames before summarising. Every tick
// (64 frames) then describes one moment on all three layers. The audio itself is never delayed
// and no stage moves.
//
// Threads: the audio thread folds each 64 frames into one tick (peaks, sum of squares, gain
// reduction, timeline position) and pushes it into preallocated atomic arrays, only while the
// screen is showing; no allocation, lock, log or dispatch. The UI copies the newest window out
// at 30 fps and reduces it to display columns (max per column, so short transients survive).
// If the copy was overrun while reading, that frame is skipped; the audio never waits.

/// Envelope ticks from the audio thread to the screen. Allocated once, never resized.
final class WaveFeed: @unchecked Sendable {
    static let tickFrames = 64
    static let size = 16384                       // power of two: 5 s at up to 192 kHz
    static let mask = size - 1

    let on = AtomicInt(0)                        // 1 = the screen is showing; the audio thread fills ticks
    let frame = AtomicInts(count: WaveFeed.size)     // timeline position of the tick's first output frame
    let clock = AtomicInts(count: WaveFeed.size)     // SongClock raw value of that position
    let frames = AtomicInts(count: WaveFeed.size)    // frames in the tick (tickFrames)
    let mark = AtomicInts(count: WaveFeed.size)      // MAX CLIP serial if that maximum came out here, else 0
    let inPeak = AtomicFloats(count: WaveFeed.size)  // largest |input tap| (L or R)
    let outPeak = AtomicFloats(count: WaveFeed.size) // largest |output tap|
    let outSquares = AtomicFloats(count: WaveFeed.size) // sum over the tick of (L^2 + R^2) / 2, output tap
    let clip = AtomicFloats(count: WaveFeed.size)    // most the clipper took off in the tick, dB
    let written = AtomicInt(0)                   // ticks written so far (never wraps), published per tick

    deinit {
        on.deallocate(); written.deallocate()
        for a in [frame, clock, frames, mark] { a.deallocate() }
        for a in [inPeak, outPeak, outSquares, clip] { a.deallocate() }
    }

    /// Audio thread: one finished tick.
    @inline(__always) func push(frame f: Int, clock c: Int, frames n: Int, inPeak i: Float, outPeak o: Float,
                                outSquares sq: Float, clip db: Float, mark m: Int) {
        let w = written.value
        let k = w & WaveFeed.mask
        frame[k] = f; clock[k] = c; frames[k] = n; mark[k] = m
        inPeak[k] = i; outPeak[k] = o; outSquares[k] = sq; clip[k] = db
        written.publish(w &+ 1)                  // last, after the tick is filled
    }

    /// UI: copies of the newest `count` ticks (fewer if fewer exist), oldest first; nil if the
    /// audio thread lapped the copy while it was being made (skip this frame).
    func newest(_ count: Int) -> WaveTicks? {
        let end = written.acquire()
        let n = min(count, end, WaveFeed.size - 256)
        var t = WaveTicks(written: end, count: n)
        for j in 0..<n {
            let k = (end - n + j) & WaveFeed.mask
            t.frame[j] = frame[k]; t.clock[j] = clock[k]; t.frames[j] = frames[k]; t.mark[j] = mark[k]
            t.inPeak[j] = inPeak[k]; t.outPeak[j] = outPeak[k]; t.outSquares[j] = outSquares[k]; t.clip[j] = clip[k]
        }
        guard written.acquire() - (end - n) < WaveFeed.size else { return nil }
        return t
    }
}

/// A copy of some ticks, oldest first.
struct WaveTicks {
    var written: Int
    var frame: [Int], clock: [Int], frames: [Int], mark: [Int]
    var inPeak: [Float], outPeak: [Float], outSquares: [Float], clip: [Float]
    var count: Int { frame.count }

    init(written: Int, count n: Int) {
        self.written = written
        let ints = [Int](repeating: 0, count: n), floats = [Float](repeating: 0, count: n)
        frame = [Int](repeating: -1, count: n); clock = ints; frames = ints; mark = ints
        inPeak = floats; outPeak = floats; outSquares = floats; clip = floats
    }
}

/// One display column: the loudest of its ticks (so a one-tick transient still shows).
struct WaveColumn: Equatable {
    var has = false
    var inPeak: Float = 0, outPeak: Float = 0
    var clipDB: Float = 0
    var frame = -1, clock = 0                    // the column's first tick
    var mark = 0
}

enum WaveColumns {
    /// Reduces the ticks to `count` columns across a window of `window` ticks, newest on the
    /// right; columns older than the first tick stay empty.
    static func make(_ t: WaveTicks, count: Int, window: Int) -> [WaveColumn] {
        var cols = [WaveColumn](repeating: WaveColumn(), count: max(count, 1))
        guard count > 0, window > 0 else { return cols }
        let offset = window - t.count               // empty ticks on the left
        for j in 0..<t.count {
            let c = min((offset + j) * count / window, count - 1)
            guard c >= 0 else { continue }
            if !cols[c].has { cols[c].has = true; cols[c].frame = t.frame[j]; cols[c].clock = t.clock[j] }
            cols[c].inPeak = max(cols[c].inPeak, t.inPeak[j])
            cols[c].outPeak = max(cols[c].outPeak, t.outPeak[j])
            cols[c].clipDB = max(cols[c].clipDB, t.clip[j])
            if t.mark[j] != 0 { cols[c].mark = t.mark[j] }
        }
        return cols
    }

    /// Largest output sample and the output's RMS over the ticks, both dBFS (-inf if silent).
    static func peakAndRMS(_ t: WaveTicks) -> (peak: Float, rms: Float) {
        var peak: Float = 0, sum: Double = 0, n = 0
        for j in 0..<t.count {
            peak = max(peak, t.outPeak[j])
            sum += Double(t.outSquares[j]); n += t.frames[j]
        }
        let rms = n > 0 ? Float((sum / Double(n)).squareRoot()) : 0
        return (peak > 0 ? 20 * log10(peak) : -.infinity, rms > 0 ? 20 * log10(rms) : -.infinity)
    }
}

enum WaveTime {
    /// "0:44.2"
    static func tenths(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "-:--" }
        let t = Int((seconds * 10).rounded(.down))
        return String(format: "%d:%02d.%d", t / 600, (t / 10) % 60, t % 10)
    }

    static func dBFS(_ db: Float) -> String {
        guard db.isFinite, db > -120 else { return "-inf" }
        return String(format: "%.1f", db).replacingOccurrences(of: "-", with: "\u{2212}")
    }
}

/// The audio-flow memory the screen keeps between frames (a class, so drawing can update it).
private final class WaveSeen {
    var written = -1
    var changed = Date.distantPast
}

// MARK: - The screen

/// The full-width waveform on the screen's glass, drawn in the screen's own units (258 high;
/// about 932 wide on the iPad face, 422 on the iPhone face). Rows, top to bottom: the WAVEFORM
/// tag, status, legend and ceiling (the iPhone's narrower glass puts the legend on a second
/// row); the plot; the time ruler; the readouts. Labels never sit inside the waveform.
struct PlateWaveScreen: View {
    let shared: SharedState
    let ceilingDB: Float
    var zoom: MeterZoom = .full
    var bypassed = false
    var isPlugin = false
    var onZoom: () -> Void = {}
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    @State private var seen = WaveSeen()

    static let H: CGFloat = 258
    static let side: CGFloat = 14
    static let headerY: CGFloat = 16, legendRowY: CGFloat = 33   // legendRowY: iPhone only

    static let inputColor = Color(hex: 0x737983)
    static let outputColor = Color(hex: 0xe4e7ec)
    static let clipColor = Color(hex: 0xff3b40)
    static let ceilingColor = Color(hex: 0xf0a43a)
    static let labelColor = Color(hex: 0x898d93)
    static let valueColor = Color(hex: 0xf1f1f3)

    /// Rows for a glass `W` units wide.
    struct Rows {
        let narrow: Bool
        let L: CGFloat, R: CGFloat, top: CGFloat, bottom: CGFloat
        let rulerY: CGFloat, dividerY: CGFloat, readout1: CGFloat, readout2: CGFloat
        let seconds: Double                       // the window
        init(W: CGFloat) {
            let n = W < 600
            narrow = n
            L = n ? 36 : 44; R = W - (n ? 26 : 30)        // room for the ceiling needle on the right
            top = n ? 48 : 40
            bottom = n ? 184 : 188
            rulerY = n ? 195 : 200
            dividerY = n ? 205 : 214
            readout1 = n ? 219 : 236
            readout2 = n ? 241 : 236
            seconds = n ? 3 : 5
        }
    }

    /// In the app, inactive or background pauses it; a plug-in window follows its own visibility.
    private var live: Bool { visible && (isPlugin || phase == .active) }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.height / Self.H
            let W = geo.size.width / s
            let rows = Rows(W: W)
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
                    Canvas { g, _ in
                        draw(g, W: W, rows: rows, now: tl.date)
                    }
                }
                .frame(width: W, height: Self.H)
                .accessibilityElement()
                .accessibilityLabel("Waveform: input in grey, output in white, clipping in red, over the last \(Int(rows.seconds)) seconds")
                scaleTarget(rows)
                resetButton(W, rows)
            }
            .frame(width: W, height: Self.H, alignment: .topLeading)
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onAppear { visible = true; shared.wave.on.value = 1 }
        .onDisappear { visible = false; shared.wave.on.value = 0 }
    }

    // MARK: Scale (double-tap to zoom) and reset

    private func scaleTarget(_ r: Rows) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onZoom)
            .frame(width: r.L, height: r.bottom - r.top + 20)
            .position(x: r.L / 2, y: (r.top + r.bottom) / 2)
            .accessibilityLabel("Zoom the waveform, \(zoom.label)")
            .accessibilityAddTraits(.isButton)
    }

    private func resetButton(_ W: CGFloat, _ r: Rows) -> some View {
        Button { shared.resetClipMax() } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.labelColor)
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x16171a)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset max clip")
        .position(x: W - Self.side - 14, y: r.narrow ? r.readout2 : r.readout1)
    }

    // MARK: Drawing (every frame)

    static func y(_ db: Float, _ r: Rows, _ zoom: MeterZoom) -> CGFloat {
        r.bottom - (r.bottom - r.top) * zoom.position(db)
    }

    static func y(amplitude a: Float, _ r: Rows, _ zoom: MeterZoom) -> CGFloat {
        y(20 * log10(max(a, 1e-7)), r, zoom)
    }

    /// The scale's labelled steps: the top, then 0 down to the floor.
    static func scaleMarks(_ zoom: MeterZoom) -> [Float] {
        let step: Float = zoom == .zoom2 ? 3 : 6
        var marks: [Float] = [zoom.topDB]
        var db: Float = 0
        while db >= zoom.floorDB - 0.01 { marks.append(db); db -= step }
        return marks
    }

    private func draw(_ c: GraphicsContext, W: CGFloat, rows r: Rows, now: Date) {
        let rate = Double(max(shared.sampleRate.value, 8_000))
        let window = max(1, Int(r.seconds * rate) / WaveFeed.tickFrames)
        let ticks = shared.wave.newest(window)
        if let ticks, ticks.written != seen.written { seen.written = ticks.written; seen.changed = now }
        let flowing = now.timeIntervalSince(seen.changed) < 0.25

        // glass background, grid and scale
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: Self.H)), with: .color(Color(hex: 0x0b0c0e)))
        var grid = Path()
        for db in Self.scaleMarks(zoom) {
            let yy = Self.y(db, r, zoom)
            grid.move(to: CGPoint(x: r.L, y: yy)); grid.addLine(to: CGPoint(x: r.R, y: yy))
            let text = db > 0 ? String(format: "+%.0f", db) : (db == 0 ? "0" : "\u{2212}\(Int(-db))")
            c.draw(Text(text).font(.system(size: 9.5)).monospacedDigit().foregroundColor(Self.labelColor),
                   at: CGPoint(x: r.L - 7, y: yy), anchor: .trailing)
        }
        c.stroke(grid, with: .color(Color.white.opacity(0.05)), lineWidth: 1)

        let count = max(Int((r.R - r.L).rounded()), 8)        // about one column per unit
        let colW = (r.R - r.L) / CGFloat(count)
        let cols = ticks.map { WaveColumns.make($0, count: count, window: window) } ?? []
        func x(_ i: Int) -> CGFloat { r.L + (CGFloat(i) + 0.5) * colW }

        if !cols.isEmpty {
            // INPUT (grey) and OUTPUT (silver) as filled envelopes rising from the floor
            func envelope(_ v: (WaveColumn) -> Float) -> (line: Path, fill: Path) {
                var line = Path(), fill = Path()
                var open = false
                for i in cols.indices {
                    guard cols[i].has else {
                        if open { fill.addLine(to: CGPoint(x: x(i - 1), y: r.bottom)); fill.closeSubpath(); open = false }
                        continue
                    }
                    let p = CGPoint(x: x(i), y: Self.y(amplitude: v(cols[i]), r, zoom))
                    if !open {
                        fill.move(to: CGPoint(x: p.x, y: r.bottom)); line.move(to: p); open = true
                    } else { line.addLine(to: p) }
                    fill.addLine(to: p)
                }
                if open { fill.addLine(to: CGPoint(x: x(cols.count - 1), y: r.bottom)); fill.closeSubpath() }
                return (line, fill)
            }
            let inE = envelope { $0.inPeak }, outE = envelope { $0.outPeak }
            c.fill(inE.fill, with: .linearGradient(Gradient(colors: [Self.inputColor.opacity(0.95), Self.inputColor.opacity(0.35)]),
                                                   startPoint: CGPoint(x: 0, y: r.top), endPoint: CGPoint(x: 0, y: r.bottom)))
            c.fill(outE.fill, with: .linearGradient(Gradient(colors: [Self.outputColor.opacity(0.32), Self.outputColor.opacity(0.06)]),
                                                    startPoint: CGPoint(x: 0, y: r.top), endPoint: CGPoint(x: 0, y: r.bottom)))

            // CLIPPED: where the clipper took something off, the part of the input above the output
            var cut = Path()
            for i in cols.indices where cols[i].has && cols[i].clipDB > 0.05 {
                let yIn = Self.y(amplitude: cols[i].inPeak, r, zoom), yOut = Self.y(amplitude: cols[i].outPeak, r, zoom)
                let top = min(yIn, yOut - 2)
                cut.addRect(CGRect(x: r.L + CGFloat(i) * colW, y: top, width: colW + 0.4, height: max(yOut - top, 1.5)))
            }
            c.fill(cut, with: .color(Self.clipColor.opacity(0.85)))
            c.stroke(outE.line, with: .color(Self.outputColor), style: StrokeStyle(lineWidth: 1.1, lineJoin: .round))

            // over the top of the scale: a mark on the top edge
            var overIn = Path(), overOut = Path()
            for i in cols.indices where cols[i].has {
                let topLin = pow(10, zoom.topDB / 20)
                if cols[i].inPeak > topLin { overIn.addRect(CGRect(x: r.L + CGFloat(i) * colW, y: r.top - 3, width: colW + 0.4, height: 3)) }
                if cols[i].outPeak > topLin { overOut.addRect(CGRect(x: r.L + CGFloat(i) * colW, y: r.top - 3, width: colW + 0.4, height: 3)) }
            }
            c.fill(overIn, with: .color(Self.inputColor))
            c.fill(overOut, with: .color(Self.clipColor))
        }

        drawCeiling(c, r)
        drawMaxMarker(c, r, cols: cols, colW: colW, rate: rate)
        drawRuler(c, r, cols: cols, rate: rate)
        if !r.narrow {
            c.draw(Text("DOUBLE-TAP SCALE TO ZOOM").font(.system(size: 8.5, weight: .medium)).tracking(0.8)
                    .foregroundColor(Color(hex: 0x5c6066)),
                   at: CGPoint(x: r.R - 4, y: r.bottom - 8), anchor: .trailing)
        }
        drawHeader(c, W: W, r, flowing: flowing)
        drawReadouts(c, W: W, r, ticks: ticks, rate: rate)
    }

    /// The Ceiling: an amber line across the plot and a needle at its right edge, on the current
    /// scale. Below the scale's floor, the needle sits on the bottom edge pointing down.
    private func drawCeiling(_ c: GraphicsContext, _ r: Rows) {
        let inside = ceilingDB >= zoom.floorDB
        let yy = Self.y(ceilingDB, r, zoom)
        if inside {
            var line = Path()
            line.move(to: CGPoint(x: r.L, y: yy)); line.addLine(to: CGPoint(x: r.R, y: yy))
            c.stroke(line, with: .color(Self.ceilingColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            var needle = Path()
            needle.move(to: CGPoint(x: r.R + 2, y: yy))
            needle.addLine(to: CGPoint(x: r.R + 10, y: yy - 5))
            needle.addLine(to: CGPoint(x: r.R + 10, y: yy + 5))
            needle.closeSubpath()
            c.fill(needle, with: .color(Self.ceilingColor))
        } else {
            var needle = Path()
            needle.move(to: CGPoint(x: r.R + 6, y: r.bottom + 2))
            needle.addLine(to: CGPoint(x: r.R + 1, y: r.bottom - 6))
            needle.addLine(to: CGPoint(x: r.R + 11, y: r.bottom - 6))
            needle.closeSubpath()
            c.fill(needle, with: .color(Self.ceilingColor))
            c.draw(Text(WaveTime.dBFS(ceilingDB)).font(.system(size: 8.5, weight: .medium)).monospacedDigit()
                    .foregroundColor(Self.ceilingColor),
                   at: CGPoint(x: r.R - 2, y: r.bottom - 8), anchor: .trailing)
        }
    }

    /// The MAX CLIP sample, where it came out of the clipper, while it is on screen.
    private func drawMaxMarker(_ c: GraphicsContext, _ r: Rows, cols: [WaveColumn], colW: CGFloat, rate: Double) {
        guard let m = shared.clipMax(), m.db > 0.05,
              let i = cols.lastIndex(where: { $0.mark == m.serial }) else { return }
        let xx = r.L + (CGFloat(i) + 0.5) * colW
        var line = Path()
        line.move(to: CGPoint(x: xx, y: r.top + 4)); line.addLine(to: CGPoint(x: xx, y: r.bottom))
        c.stroke(line, with: .color(Self.clipColor.opacity(0.9)), lineWidth: 1)
        var tri = Path()
        tri.move(to: CGPoint(x: xx - 4, y: r.top - 2)); tri.addLine(to: CGPoint(x: xx + 4, y: r.top - 2))
        tri.addLine(to: CGPoint(x: xx, y: r.top + 5)); tri.closeSubpath()
        c.fill(tri, with: .color(Self.clipColor))
        let label = "MAX @ " + stamp(m.frame, m.clock, rate)
        let right = xx < r.R - 90
        c.draw(Text(label).font(.system(size: 9.5, weight: .semibold)).monospacedDigit().foregroundColor(Self.clipColor),
               at: CGPoint(x: right ? xx + 7 : xx - 7, y: r.top + 2), anchor: right ? .leading : .trailing)
    }

    /// A timeline position as text: the file's or the host's time, or labelled analysis time.
    private func stamp(_ frame: Int, _ clock: SongClock, _ rate: Double) -> String {
        guard frame >= 0 else { return "-:--" }
        let t = WaveTime.tenths(Double(frame) / rate)
        return clock == .relative ? "+\(t) ELAPSED" : t
    }

    /// Whole seconds of each column's timeline position, spaced so the labels can be read.
    private func drawRuler(_ c: GraphicsContext, _ r: Rows, cols: [WaveColumn], rate: Double) {
        var ticks = Path()
        var lastX = -CGFloat.infinity
        var prev = Int.min
        let colW = (r.R - r.L) / CGFloat(max(cols.count, 1))
        for (i, col) in cols.enumerated() where col.has && col.frame >= 0 {
            let sec = Int(floor(Double(col.frame) / rate))
            defer { prev = sec }
            guard prev != Int.min, sec != prev else { continue }
            let xx = r.L + CGFloat(i) * colW
            guard xx - lastX >= (r.narrow ? 46 : 60), xx > r.L + 8, xx < r.R - 8 else { continue }
            lastX = xx
            ticks.move(to: CGPoint(x: xx, y: r.bottom)); ticks.addLine(to: CGPoint(x: xx, y: r.bottom + 3))
            let text = SongTime.text(Double(sec))
            c.draw(Text(col.clock == SongClock.relative.rawValue ? "+" + text : text).font(.system(size: 9.5)).monospacedDigit()
                    .foregroundColor(Self.labelColor),
                   at: CGPoint(x: xx, y: r.rulerY), anchor: .center)
        }
        c.stroke(ticks, with: .color(Color(hex: 0x4a4c50)), lineWidth: 1)
    }

    private func drawHeader(_ c: GraphicsContext, W: CGFloat, _ r: Rows, flowing: Bool) {
        let y0 = Self.headerY
        // WAVEFORM tag
        let tag = CGRect(x: Self.side, y: y0 - 8.5, width: 76, height: 17)
        c.fill(Path(roundedRect: tag, cornerRadius: 3),
               with: .linearGradient(Gradient(colors: [Color(hex: 0xe8363b), Color(hex: 0xa3171c)]),
                                     startPoint: CGPoint(x: 0, y: tag.minY), endPoint: CGPoint(x: 0, y: tag.maxY)))
        c.draw(Text("WAVEFORM").font(.system(size: 9.5, weight: .bold)).tracking(1.2).foregroundColor(.white),
               at: CGPoint(x: tag.midX, y: y0), anchor: .center)
        // status: LIVE while audio arrives, HOLD when it stops (paused source), BYPASS
        let status: (String, Color) = bypassed ? ("BYPASS", Self.ceilingColor)
            : (flowing ? ("LIVE", Self.clipColor) : ("HOLD", Self.labelColor))
        var x0 = tag.maxX + 10
        c.fill(Path(CGRect(x: x0, y: y0 - 3, width: 6, height: 6)), with: .color(status.1))
        c.draw(Text(status.0).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundColor(Color(hex: 0xd0d3d8)),
               at: CGPoint(x: x0 + 10, y: y0), anchor: .leading)
        // legend: beside the status on the iPad, on its own row on the iPhone
        let legendY = r.narrow ? Self.legendRowY : y0
        x0 = r.narrow ? Self.side : x0 + 62
        for (color, name) in [(Self.inputColor, "INPUT"), (Self.outputColor, "OUTPUT"), (Self.clipColor, "CLIPPED")] {
            c.fill(Path(CGRect(x: x0, y: legendY - 3.5, width: 7, height: 7)), with: .color(color))
            c.draw(Text(name).font(.system(size: 9.5, weight: .medium)).tracking(0.8).foregroundColor(Color(hex: 0xb3b9c2)),
                   at: CGPoint(x: x0 + 11, y: legendY), anchor: .leading)
            x0 += 11 + CGFloat(name.count) * 7.2 + 14
        }
        // CEILING with the parameter's value
        c.draw(Text("CEILING  \(WaveTime.dBFS(ceilingDB)) dBFS").font(.system(size: r.narrow ? 9.5 : 10.5, weight: .medium))
                .tracking(0.6).foregroundColor(Self.ceilingColor),
               at: CGPoint(x: W - Self.side, y: y0), anchor: .trailing)
    }

    private func drawReadouts(_ c: GraphicsContext, W: CGFloat, _ r: Rows, ticks: WaveTicks?, rate: Double) {
        var div = Path()
        div.move(to: CGPoint(x: Self.side, y: r.dividerY)); div.addLine(to: CGPoint(x: W - Self.side, y: r.dividerY))
        c.stroke(div, with: .color(Color.white.opacity(0.07)), lineWidth: 1)

        // elapsed / total
        let elapsed = SongTime.text(Double(max(0, shared.songFrame.value)) / rate)
        let time: String
        if isPlugin {
            let clock = SongClock(rawValue: shared.songClock.value) ?? .none
            time = clock == .relative ? "\(elapsed)  SINCE START" : (clock == .host ? "\(elapsed)  HOST" : "-:--")
        } else {
            time = "\(elapsed) / \(SongTime.text(Double(shared.songTotal.value) / rate))"
        }
        // processed peak and RMS over the window on screen
        let levels: (peak: Float, rms: Float) = ticks.map(WaveColumns.peakAndRMS) ?? (peak: -Float.infinity, rms: -Float.infinity)
        // MAX CLIP since the reset (or since the settings or the source last changed)
        var maxValue = "-- dB", maxAt = ""
        if let m = shared.clipMax(), m.db > 0.05 {
            maxValue = String(format: "%.1f dB", m.db)
            maxAt = " @ " + stamp(m.frame, m.clock, rate)
        }

        func label(_ t: String, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let w = CGFloat(t.count) * 6.4 + 6
            c.draw(Text(t).font(.system(size: 9, weight: .medium)).tracking(1).foregroundColor(Self.labelColor),
                   at: CGPoint(x: x, y: y), anchor: .leading)
            return x + w
        }
        func value(_ t: String, _ x: CGFloat, _ y: CGFloat, color: Color = Self.valueColor, size: CGFloat = 13) {
            c.draw(Text(t).font(.system(size: size, weight: .medium)).monospacedDigit().foregroundColor(color),
                   at: CGPoint(x: x, y: y), anchor: .leading)
        }

        if r.narrow {
            // two rows: time, PEAK, RMS / MAX SINCE RESET
            let y1 = r.readout1, y2 = r.readout2
            value(time, Self.side, y1, size: 12.5)
            var x = W * 0.42
            x = label("PEAK", x, y1); value("\(WaveTime.dBFS(levels.peak)) dBFS", x, y1, size: 11)
            x = W * 0.72
            x = label("RMS", x, y1); value("\(WaveTime.dBFS(levels.rms)) dBFS", x, y1, size: 11)
            x = label("MAX SINCE RESET", Self.side, y2)
            value(maxValue, x, y2, size: 12)
            value(maxAt, x + CGFloat(maxValue.count) * 7.4, y2, color: Self.clipColor, size: 11.5)
        } else {
            let y = r.readout1
            value(time, Self.side + 10, y, size: 14)
            var x = W * 0.25
            x = label("PEAK", x, y); value("\(WaveTime.dBFS(levels.peak)) dBFS", x, y)
            x = W * 0.43
            x = label("RMS", x, y); value("\(WaveTime.dBFS(levels.rms)) dBFS", x, y)
            x = W * 0.60
            x = label("MAX SINCE RESET", x, y)
            value(maxValue, x, y)
            value(maxAt, x + CGFloat(maxValue.count) * 7.8, y, color: Self.clipColor)
            var seps = Path()
            for f in [0.235, 0.415, 0.585] as [CGFloat] {
                seps.move(to: CGPoint(x: W * f, y: y - 8)); seps.addLine(to: CGPoint(x: W * f, y: y + 8))
            }
            c.stroke(seps, with: .color(Color.white.opacity(0.12)), lineWidth: 1)
        }
    }
}
