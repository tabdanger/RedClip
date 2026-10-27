import SwiftUI

// MARK: - The SPECTRUM screen
//
// INPUT and OUTPUT (CLIPPED) spectra on the screen's glass, drawn in the screen's own units
// (258 high; about 932 wide on the iPad face, 422 on the iPhone face). Rows, top to bottom:
// the WAVE / SPECTRUM switch (Faceplate) and the status; the legend and the ceiling label; the plot (0 to -72 dBFS,
// 20 Hz to 20 kHz or Nyquist, log); the frequency labels; elapsed time and MAX CLIP.
//
// The curves come from SpectrumAnalyzer (Spectrum.swift), which works off the main thread; this
// view only draws its newest frame, 30 times a second, and only while it is on screen.
//
// The amber CEILING line is the clipper's time-domain peak threshold, drawn on the same dBFS
// scale for reference. It is not a limit on any frequency: the output curve is never clamped
// or flattened to it (clipping adds harmonics that can sit anywhere), and nothing here is
// derived from the area above it. CLIP and MAX CLIP come from the clipper's own telemetry.
struct PlateSpectrumScreen: View {
    let analyzer: SpectrumAnalyzer
    let shared: SharedState
    let ceilingDB: Float
    var bypassed = false
    var isPlugin = false
    @Environment(\.scenePhase) private var phase
    @State private var visible = false

    static let H: CGFloat = 258
    static let side: CGFloat = 14
    // rows (screen units)
    static let tagY: CGFloat = 16, legendY: CGFloat = 36
    static let plotTop: CGFloat = 52, plotBottom: CGFloat = 192
    static let freqLabelY: CGFloat = 204
    static let dividerY: CGFloat = 217, readoutY: CGFloat = 237
    // the fixed scale
    static let topDB: Float = 0, bottomDB: Float = -72

    static let inputColor = Color(hex: 0xc9cdd3)
    static let outputColor = Color(hex: 0xff3b40)
    static let ceilingColor = Color(hex: 0xf0a43a)
    static let labelColor = Color(hex: 0x898d93)
    static let ceilingNote = "Clipping threshold in the time domain; not a per-frequency limit."

    /// In the app, inactive or background stops it; a plug-in window follows its own visibility.
    private var live: Bool { visible && (isPlugin || phase == .active) }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.height / Self.H
            let W = geo.size.width / s
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
                    Canvas { g, _ in
                        _ = tl.date
                        draw(g, W: W, frame: analyzer.latest)
                    }
                }
                .frame(width: W, height: Self.H)
                .accessibilityElement()
                .accessibilityLabel("Spectrum analyser: input in grey, clipped output in red, 20 hertz to 20 kilohertz")
                labels(W)
                resetButton(W)
            }
            .frame(width: W, height: Self.H, alignment: .topLeading)
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onAppear { visible = true; if live { analyzer.start() } }
        .onDisappear { visible = false; analyzer.stop() }
        .onChange(of: live) { _, on in if on { analyzer.start() } else { analyzer.stop() } }
    }

    // MARK: Fixed labels (tag, legend, ceiling)

    private func labels(_ W: CGFloat) -> some View {
        let narrow = W < 600
        return ZStack(alignment: .topLeading) {
            HStack(spacing: narrow ? 8 : 12) {
                key(Self.inputColor, "INPUT", nil)
                key(Self.outputColor, "OUTPUT", "(CLIPPED)")
            }
            .fixedSize()
            .frame(width: 200, height: 14, alignment: .leading)
            .position(x: Self.side + 100, y: Self.legendY)
            .accessibilityElement(children: .combine)
            Text(ceilingText)
                .font(.system(size: narrow ? 9 : 10, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Self.ceilingColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: narrow ? 176 : 260, height: 14, alignment: .trailing)
                .position(x: W - Self.side - (narrow ? 88 : 130), y: Self.legendY)
                .accessibilityLabel(String(format: "Ceiling %.1f dBFS, peak reference", ceilingDB))
                .accessibilityHint(Self.ceilingNote)
        }
        .frame(width: W, height: Self.H, alignment: .topLeading)
    }

    private var ceilingText: String {
        let v = String(format: "%.1f", abs(ceilingDB))
        return "CEILING \(ceilingDB < -0.05 ? "\u{2212}" : "")\(v) dBFS \u{00B7} PEAK REF"
    }

    private func key(_ color: Color, _ title: String, _ note: String?) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 9.5, weight: .medium)).tracking(0.8).foregroundStyle(Color(hex: 0xb3b9c2))
            if let note {
                Text(note).font(.system(size: 9.5, weight: .medium)).tracking(0.6).foregroundStyle(Color(hex: 0xb3b9c2))
            }
        }
    }

    // MARK: Plot (every frame)

    static func y(_ db: Float) -> CGFloat {
        let t = CGFloat((topDB - db) / (topDB - bottomDB))
        return plotTop + (plotBottom - plotTop) * t
    }

    static func x(_ hz: Double, L: CGFloat, R: CGFloat, topHz: Double) -> CGFloat {
        L + (R - L) * CGFloat(log(hz / SpectrumEngine.lowHz) / log(topHz / SpectrumEngine.lowHz))
    }

    private func draw(_ c: GraphicsContext, W: CGFloat, frame: SpectrumFrame) {
        let narrow = W < 600
        let L: CGFloat = narrow ? 36 : 42, R = W - Self.side
        let top = Self.plotTop, bottom = Self.plotBottom
        let topHz = frame.topHz

        // dB grid every 12 dB, labelled on the left
        var grid = Path()
        for step in 0...6 {
            let db = -Float(step) * 12
            let yy = Self.y(db)
            grid.move(to: CGPoint(x: L, y: yy)); grid.addLine(to: CGPoint(x: R, y: yy))
            c.draw(Text(step == 0 ? "0" : "\u{2212}\(step * 12)").font(.system(size: 9.5)).monospacedDigit().foregroundColor(Self.labelColor),
                   at: CGPoint(x: L - 6, y: yy), anchor: .trailing)
        }
        // frequency grid: 1-2-5 decades, labels thinned on the iPhone's narrower glass
        let lines: [Double] = [20, 30, 40, 50, 60, 70, 80, 90, 100, 200, 300, 400, 500, 600, 700, 800, 900,
                               1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10_000, 20_000]
        let labelled: [Double] = narrow ? [20, 50, 100, 500, 1000, 5000, 20_000]
                                        : [20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000]
        for hz in lines where hz <= topHz {
            let xx = Self.x(hz, L: L, R: R, topHz: topHz)
            grid.move(to: CGPoint(x: xx, y: top)); grid.addLine(to: CGPoint(x: xx, y: bottom))
        }
        c.stroke(grid, with: .color(Color.white.opacity(0.055)), lineWidth: 1)
        let shown = labelled.filter { $0 <= topHz + 1 }
        for (i, hz) in shown.enumerated() {
            let xx = Self.x(hz, L: L, R: R, topHz: topHz)
            let last = i == shown.count - 1
            let name = hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))"
            c.draw(Text(last ? "\(name) Hz" : name).font(.system(size: 9.5)).monospacedDigit().foregroundColor(Self.labelColor),
                   at: CGPoint(x: last ? min(xx, R) : xx, y: Self.freqLabelY),
                   anchor: i == 0 ? .leading : (last ? .trailing : .center))
        }

        // the two traces: same points, same scale, same mapping
        let n = min(frame.input.count, frame.output.count)
        if n > 1 {
            func xAt(_ i: Int) -> CGFloat { L + (R - L) * CGFloat(i) / CGFloat(n - 1) }
            func curve(_ v: [Float]) -> (line: Path, fill: Path) {
                var line = Path()
                for i in 0..<n {
                    let p = CGPoint(x: xAt(i), y: min(max(Self.y(v[i]), top), bottom))
                    if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                }
                var fill = line
                fill.addLine(to: CGPoint(x: R, y: bottom)); fill.addLine(to: CGPoint(x: L, y: bottom))
                fill.closeSubpath()
                return (line, fill)
            }
            let inC = curve(frame.input), outC = curve(frame.output)
            c.fill(inC.fill, with: .linearGradient(Gradient(colors: [Self.inputColor.opacity(0.22), Self.inputColor.opacity(0.03)]),
                                                   startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            c.fill(outC.fill, with: .linearGradient(Gradient(colors: [Self.outputColor.opacity(0.30), Self.outputColor.opacity(0.04)]),
                                                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))
            c.stroke(inC.line, with: .color(Self.inputColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
            c.stroke(outC.line, with: .color(Self.outputColor), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))

            // over-range: anything above 0 dBFS gets a mark on the plot's top edge
            func over(_ v: [Float], _ color: Color, _ dy: CGFloat) {
                var marks = Path()
                var i = 0
                while i < n {
                    if v[i] > Self.topDB {
                        let xx = xAt(i)
                        marks.move(to: CGPoint(x: xx - 3, y: top + 5 + dy)); marks.addLine(to: CGPoint(x: xx + 3, y: top + 5 + dy))
                        marks.addLine(to: CGPoint(x: xx, y: top + dy)); marks.closeSubpath()
                        i += 6                                  // one mark per few points
                    } else { i += 1 }
                }
                c.fill(marks, with: .color(color))
            }
            over(frame.input, Self.inputColor, 0)
            over(frame.output, Self.outputColor, 0)
        }

        // CEILING: the clipper's peak threshold on the same dBFS scale (reference only)
        var ceil = Path()
        let cy = Self.y(ceilingDB)
        ceil.move(to: CGPoint(x: L, y: cy)); ceil.addLine(to: CGPoint(x: R, y: cy))
        c.stroke(ceil, with: .color(Self.ceilingColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

        // status beside the tag: LIVE while audio arrives, HOLD when the source is paused
        let status: (String, Color) = bypassed ? ("BYPASS", Self.ceilingColor)
            : (frame.live ? ("LIVE", Self.outputColor) : ("HOLD", Self.labelColor))
        let sx = 12 + ScreenViewSwitch.width + 10        // beside the WAVE / SPECTRUM switch
        c.fill(Path(CGRect(x: sx, y: Self.tagY - 3, width: 6, height: 6)), with: .color(status.1))
        c.draw(Text(status.0).font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundColor(Color(hex: 0xd0d3d8)),
               at: CGPoint(x: sx + 11, y: Self.tagY), anchor: .leading)

        // elapsed time (left half), MAX CLIP (right half), split by a faint line
        var divider = Path()
        divider.move(to: CGPoint(x: Self.side, y: Self.dividerY)); divider.addLine(to: CGPoint(x: W - Self.side, y: Self.dividerY))
        divider.move(to: CGPoint(x: W * 0.5, y: Self.dividerY + 6)); divider.addLine(to: CGPoint(x: W * 0.5, y: Self.H - 8))
        c.stroke(divider, with: .color(Color.white.opacity(0.07)), lineWidth: 1)

        let rate = Double(max(shared.sampleRate.value, 8_000))
        let elapsed = SongTime.text(Double(max(0, shared.songFrame.value)) / rate)
        let left: String
        if isPlugin {
            let clock = SongClock(rawValue: shared.songClock.value) ?? .none
            left = clock == .relative ? "\(elapsed)  SINCE START" : (clock == .host ? "\(elapsed)  HOST" : "-:--")
        } else {
            left = "\(elapsed) / \(SongTime.text(Double(shared.songTotal.value) / rate))"
        }
        c.draw(Text(left).font(.system(size: 14.5, weight: .medium)).monospacedDigit().foregroundColor(Color(hex: 0xf1f1f3)),
               at: CGPoint(x: W * 0.25, y: Self.readoutY), anchor: .center)
        let maxDB = shared.clipMaxDB.value
        let value = maxDB.isFinite && maxDB > 0.05 ? String(format: "%.1f dB", maxDB) : "-- dB"
        let mid = W * 0.5 + (W * 0.5 - 40) / 2
        c.draw(Text("MAX CLIP").font(.system(size: 9.5, weight: .medium)).tracking(1).foregroundColor(Self.labelColor),
               at: CGPoint(x: mid - 6, y: Self.readoutY), anchor: .trailing)
        c.draw(Text(value).font(.system(size: 14.5, weight: .medium)).monospacedDigit().foregroundColor(Color(hex: 0xf1f1f3)),
               at: CGPoint(x: mid + 2, y: Self.readoutY), anchor: .leading)
    }

    // MARK: MAX CLIP reset

    private func resetButton(_ W: CGFloat) -> some View {
        Button { shared.resetClipMax() } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.labelColor)
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0x16171a)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset max clip")
        .position(x: W - Self.side - 18, y: Self.readoutY)
    }
}
