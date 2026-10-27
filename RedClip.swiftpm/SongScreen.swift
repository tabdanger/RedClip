import SwiftUI

// MARK: - LIVE / SONG
//
// The screen has two views of the same audio. LIVE is the original scope (the newest 120 ms,
// PlateScreen). SONG is the whole song on a fixed timeline (PlateSongScreen) with a playhead
// that follows the audio's own clock. Switching only changes what is drawn: the audio, the DSP
// and every control carry on untouched.

enum ScreenMode: Int {
    case live, song
}

/// Scrubbing the SONG waveform (the app's own transport; a DAW's playhead isn't ours to move).
enum SongScrub {
    case began
    case moved(Double)      // 0...1 of the song
    case ended
}

/// How large the faceplate is really drawn (points per picture pixel), set by the root views
/// from the space the device or host window gives them, so the SONG screen can draw about one
/// column per real pixel at any size, including a resized plug-in window.
private struct PlateScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0.5
}

extension EnvironmentValues {
    var plateScale: CGFloat {
        get { self[PlateScaleKey.self] }
        set { self[PlateScaleKey.self] = newValue }
    }
}

// MARK: - The data behind the SONG screen

/// Keeps the SONG overview up to date on the main thread. The heavy work runs elsewhere:
///   - app: SongAnalyzer, on a background task, only while the SONG screen is showing. The
///     untouched file is summarised first (seconds), then the file goes through a private
///     ClipDSP with the current settings. A settings change marks the result stale at once
///     and starts a new analysis 0.3 s after the controls stop moving; a newer job stops an
///     older one;
///   - plug-in: ten times a second it folds what the audio thread captured into the overview.
/// It never touches the audio thread's state beyond reading the capture ring and atomics.
@MainActor
final class SongOverviewStore: ObservableObject {
    let shared: SharedState
    let isPlugin: Bool

    /// Bumps whenever the picture's data (or the settings it is compared against) changes.
    @Published private(set) var version = 0
    /// 0...1 while the app analyses the file; nil otherwise.
    @Published private(set) var progress: Double?
    private(set) var overview: SongOverview?
    /// The SONG screen is on screen. The app only analyses while it is.
    var isShowing = false {
        didSet { if isShowing && !oldValue { tick() } }
    }

    // app
    private var audio: SongAudio?
    private var source: (hi: [Float], lo: [Float])?
    private var processedStamp = SongStamp.none        // settings the overview was made with
    private var jobStamp = SongStamp.none              // settings of the job running now
    private let generation = AtomicInt(0)
    // both
    private var seenStamp = SongStamp.none
    private var seenAt = Date.distantPast
    // plug-in
    private var cursor = 0
    private var clock = SongClock.none
    private var epoch = -1
    private(set) var pluginTimeline = 0                // frames across the screen (rounded, grows)

    private var memo: (key: [Int], columns: SongColumns)?

    init(shared: SharedState, isPlugin: Bool) {
        self.shared = shared
        self.isPlugin = isPlugin
        if isPlugin { shared.captureOn.value = 1 }
        Timer.scheduledTimer(withTimeInterval: isPlugin ? 0.1 : 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var currentStamp: Int { SongStamp.of(shared.params) }
    var hasProcessed: Bool { processedStamp != SongStamp.none }
    var isStale: Bool { hasProcessed && processedStamp != currentStamp }
    var sampleRate: Double { overview?.sampleRate ?? Double(max(shared.sampleRate.value, 8_000)) }

    /// Frames across the screen: the file's length, or (plug-in) a round length holding
    /// everything captured and the playhead.
    var timelineFrames: Int { isPlugin ? pluginTimeline : shared.songTotal.value }

    // MARK: App: a new file

    func load(_ a: SongAudio) {
        let mine = generation.value &+ 1
        generation.value = mine
        audio = a
        source = nil
        overview = nil
        processedStamp = SongStamp.none
        jobStamp = SongStamp.none
        progress = 0
        memo = nil
        version &+= 1
        let g = generation
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                SongAnalyzer.source(a, stop: { g.value != mine })
            }.value
            guard generation.value == mine, let found else { return }
            source = found
            let o = SongOverview(totalFrames: a.frames, sampleRate: a.sampleRate)
            o.setSource(hi: found.hi, lo: found.lo)
            overview = o
            progress = nil
            memo = nil
            version &+= 1
            tick()
        }
    }

    private func analyse(_ stamp: Int) {
        guard let a = audio else { return }
        let settings = Param.allCases.map { shared[$0] }
        let mine = generation.value &+ 1
        generation.value = mine
        jobStamp = stamp
        progress = 0
        let g = generation
        let src = source
        Task {
            let made = await Task.detached(priority: .utility) { () -> SongOverview? in
                let o = SongAnalyzer.preview(a, settings: settings, stop: { g.value != mine }) { p in
                    Task { @MainActor [weak self] in
                        if g.value == mine { self?.progress = p }
                    }
                }
                if let o, let src { o.setSource(hi: src.hi, lo: src.lo) }
                return o
            }.value
            guard generation.value == mine else { return }     // a newer job (or file) took over
            jobStamp = SongStamp.none
            progress = nil
            if let made {
                overview = made
                processedStamp = stamp
            }
            memo = nil
            version &+= 1
        }
    }

    // MARK: Ticks

    private func tick() {
        let now = currentStamp
        if now != seenStamp {
            seenStamp = now
            seenAt = Date()
            memo = nil
            version &+= 1                                  // stale layers redraw dimmed straight away
        }
        if isPlugin { drainCapture(); return }
        // app: analyse again once the settings have been still for 0.3 s
        guard isShowing, audio != nil, source != nil,
              now != processedStamp, now != jobStamp,
              Date().timeIntervalSince(seenAt) >= 0.3 else { return }
        analyse(now)
    }

    private func drainCapture() {
        let mode = SongClock(rawValue: shared.songClock.value) ?? .none
        let rate = Double(max(shared.sampleRate.value, 8_000))
        let e = shared.songEpoch.value
        if overview == nil || mode != clock || e != epoch || overview?.sampleRate != rate {
            // a new session, clock or rate: positions from before don't belong on this timeline
            overview = SongOverview(totalFrames: 0, sampleRate: rate)
            clock = mode
            epoch = e
            cursor = shared.capture.written.acquire()
            pluginTimeline = Int(SongTime.roundedLength(0) * rate)
            memo = nil
            version &+= 1
        }
        guard let o = overview else { return }
        var added = 0
        shared.capture.drain(&cursor) { o.add($0); added += 1 }
        let reach = max(o.capturedEnd, shared.songFrame.value)
        let length = Int(SongTime.roundedLength(Double(reach) / rate) * rate)
        if length != pluginTimeline { pluginTimeline = length; added += 1 }
        if added > 0 {
            memo = nil
            version &+= 1
        }
    }

    // MARK: Reading

    /// Display columns for the current data, settings and width; cached until one changes.
    func columns(_ count: Int) -> SongColumns {
        guard let o = overview else { return .empty }
        let timeline = timelineFrames
        let key = [version, count, timeline]
        if let memo, memo.key == key { return memo.columns }
        let c = o.columns(count, timeline: timeline, current: currentStamp)
        memo = (key, c)
        return c
    }

    /// The status shown beside the legend: (text, needs attention).
    func badge(anyStale: Bool) -> (String, Bool)? {
        if isPlugin {
            if anyStale { return ("CAPTURED · OLDER SETTINGS", true) }
            switch clock {
            case .host: return ("CAPTURED AUDIO", false)
            case .relative: return ("CAPTURED · NO HOST TIME", true)
            default: return ("WAITING FOR AUDIO", false)
            }
        }
        if let p = progress {
            let pct = Int((p * 100).rounded())
            if overview == nil { return ("READING FILE", true) }
            return (hasProcessed ? "UPDATING \(pct)%" : "ANALYZING \(pct)%", true)
        }
        if !hasProcessed { return ("ANALYZING", true) }
        if isStale { return ("UPDATING", true) }
        return ("FULL FILE · CURRENT", false)
    }
}

// MARK: - The LIVE / SONG switch

/// A small two-cell switch in the screen's top-left corner, drawn on the glass in the screen's
/// own units (258 high). Its touch area reaches past the drawn cells into the empty strip above
/// and below them, so it stays easy to hit on the iPhone face without growing the faceplate.
struct ScreenModeSwitch: View {
    @Binding var mode: ScreenMode
    static let cell = CGSize(width: 52, height: 20)
    static let touch = CGSize(width: 60, height: 40)     // the whole switch is 2 x 60 by 40 units

    var body: some View {
        HStack(spacing: 0) {
            segment("LIVE", .live)
            segment("SONG", .song)
        }
        .frame(width: Self.touch.width * 2, height: Self.touch.height, alignment: .topLeading)
    }

    private func segment(_ title: String, _ m: ScreenMode) -> some View {
        let on = mode == m
        return Button { mode = m } label: {
            ZStack(alignment: .topLeading) {
                Color.clear
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(on ? Color.white : Color(hex: 0x8a8d93))
                    .frame(width: Self.cell.width, height: Self.cell.height)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xe8363b), Color(hex: 0xa3171c)],
                                                                    startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color(hex: 0x16171a))))
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(on ? Color(hex: 0xff6a6e).opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: on ? Plate.glow.opacity(0.55) : .clear, radius: 4)
                    .padding(.top, 5)
            }
            .frame(width: m == .live ? Self.cell.width : Self.touch.width * 2 - Self.cell.width, height: Self.touch.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m == .live ? "Live waveform" : "Whole song waveform")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - The SONG screen

/// The whole song on the screen's glass, in the screen's own units (258 high; about 932 wide on
/// the iPad face, 422 on the iPhone face). Rows, top to bottom: LIVE / SONG and CEILING; the
/// legend and the status; the waveform; the time ruler; elapsed / total and MAX CLIP. Labels
/// never sit inside the waveform.
///
/// The waveform is one Canvas fed with value columns (SongColumns), redrawn only when the data,
/// the settings or the width change. The playhead and the readouts are a second, light Canvas
/// redrawn at 30 fps from the audio clock (SharedState.songFrame): pause leaves the clock where
/// it is, so the playhead stops; a seek or a loop moves the clock, so it jumps, never sweeps.
struct PlateSongScreen: View {
    @ObservedObject var store: SongOverviewStore
    let shared: SharedState
    let ceilingDB: Float
    var zoom: MeterZoom = .full
    var isPlugin = false
    var scrub: ((SongScrub) -> Void)?
    @Environment(\.scenePhase) private var phase
    @Environment(\.plateScale) private var plateScale
    @Environment(\.displayScale) private var displayScale
    @State private var visible = false
    @State private var scrubbing = false

    static let H: CGFloat = 258
    // rows (screen units)
    static let legendY: CGFloat = 38
    static let plotTop: CGFloat = 50, plotBottom: CGFloat = 196
    static let rulerY: CGFloat = 199, rulerLabelY: CGFloat = 211
    static let readoutTop: CGFloat = 222, readoutY: CGFloat = 239
    static let side: CGFloat = 14

    static let inputColor = Color(hex: 0x737983)
    static let outputColor = Color(hex: 0xe4e7ec)
    static let clipColor = Color(hex: 0xff3b40)
    static let ceilingColor = Color(hex: 0xf0a43a)
    static let labelColor = Color(hex: 0x898d93)

    private var live: Bool { visible && (isPlugin || phase == .active) }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.height / Self.H
            let W = geo.size.width / s
            let plotW = W - 2 * Self.side
            // about one column per real pixel of the glass, whatever size it is drawn at
            let pixels = plotW * s * max(plateScale, 0.05) * max(displayScale, 1)
            let count = Int(min(max(pixels.rounded(), 64), 2048))
            let cols = store.columns(count)
            let anyStale = cols.state.contains(.stale)
            ZStack(alignment: .topLeading) {
                SongWaveCanvas(columns: cols, ceilingDB: ceilingDB, zoom: zoom, width: W,
                               hasData: store.overview != nil, isPlugin: isPlugin,
                               timelineSeconds: Double(store.timelineFrames) / store.sampleRate)
                    .equatable()
                    .frame(width: W, height: Self.H)
                legend(W, badge: store.badge(anyStale: anyStale))
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { tl in
                    Canvas { g, _ in
                        _ = tl.date
                        drawLive(g, W: W)
                    }
                }
                .frame(width: W, height: Self.H)
                .allowsHitTesting(false)
                scrubArea(W)
                resetButton(W)
            }
            .frame(width: W, height: Self.H, alignment: .topLeading)
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .onAppear { visible = true; store.isShowing = true }
        .onDisappear { visible = false; store.isShowing = false }
    }

    // MARK: Legend and status (row 2) and CEILING (row 1)

    private func legend(_ W: CGFloat, badge: (String, Bool)?) -> some View {
        // legend on the left (about 210 units), status in what is left of the row
        let legendW: CGFloat = 214
        let badgeW = max(60, W - 2 * Self.side - legendW)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 11) {
                key(Self.inputColor, "INPUT")
                key(Self.outputColor, "OUTPUT")
                key(Self.clipColor, "CLIPPED")
            }
            .frame(width: legendW, height: 14, alignment: .leading)
            .position(x: Self.side + legendW / 2, y: Self.legendY)
            if let badge {
                Text(badge.0)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(badge.1 ? Self.ceilingColor : Self.labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: badgeW, height: 14, alignment: .trailing)
                    .position(x: W - Self.side - badgeW / 2, y: Self.legendY)
            }
            Text(String(format: "CEILING  %.1f dB", ceilingDB))
                .font(.system(size: W < 600 ? 12 : 13))
                .foregroundStyle(Color(hex: 0xff4145))
                .lineLimit(1)
                .fixedSize()
                .frame(width: 180, height: 20, alignment: .trailing)
                .position(x: W - 12 - 90, y: 15)
        }
        .frame(width: W, height: Self.H, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func key(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 10, weight: .medium)).tracking(0.8).foregroundStyle(Color(hex: 0xb3b9c2))
        }
        .fixedSize()
    }

    // MARK: Playhead and readouts (from the audio clock, every frame)

    private func drawLive(_ c: GraphicsContext, W: CGFloat) {
        let L = Self.side, R = W - Self.side
        let rate = store.sampleRate
        let timeline = store.timelineFrames
        let frame = max(0, shared.songFrame.value)
        let haveTimeline = timeline > 0 && (isPlugin ? store.overview != nil : true)

        if haveTimeline {
            let x = L + (R - L) * CGFloat(min(Double(frame) / Double(timeline), 1))
            var line = Path()
            line.move(to: CGPoint(x: x, y: Self.plotTop + 4)); line.addLine(to: CGPoint(x: x, y: Self.plotBottom))
            c.stroke(line, with: .color(.white.opacity(0.95)), lineWidth: 1.2)
            var tri = Path()
            tri.move(to: CGPoint(x: x - 4.5, y: Self.plotTop - 2))
            tri.addLine(to: CGPoint(x: x + 4.5, y: Self.plotTop - 2))
            tri.addLine(to: CGPoint(x: x, y: Self.plotTop + 5))
            tri.closeSubpath()
            c.fill(tri, with: .color(.white))
        }

        // elapsed / total (left half), MAX CLIP (right half)
        let elapsed = SongTime.text(Double(frame) / rate)
        let left: String
        if isPlugin {
            let clock = SongClock(rawValue: shared.songClock.value) ?? .none
            left = clock == .relative ? "\(elapsed)  SINCE START" : (clock == .host ? "\(elapsed)  HOST" : "-:--")
        } else {
            left = "\(elapsed) / \(SongTime.text(Double(timeline) / rate))"
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

    // MARK: Controls

    /// Drag across the waveform to move the app's playhead (silent while dragging, like the
    /// transport's groove). Not in a DAW: Red Clip has no way to move the host's transport.
    @ViewBuilder
    private func scrubArea(_ W: CGFloat) -> some View {
        if let scrub, !isPlugin {
            let L = Self.side, R = W - Self.side
            Color.clear
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { g in
                        if !scrubbing { scrubbing = true; scrub(.began) }
                        scrub(.moved(Double(min(max((g.location.x - L) / (R - L), 0), 1))))
                    }
                    .onEnded { _ in
                        scrubbing = false
                        scrub(.ended)
                    })
                .frame(width: R - L, height: Self.plotBottom - Self.plotTop + 20)
                .position(x: (L + R) / 2, y: (Self.plotTop + Self.plotBottom + 20) / 2)
                .accessibilityLabel("Song position")
        }
    }

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

/// The song's waveform layers, ceiling lines, grid and ruler. Equatable on its inputs, so it is
/// redrawn only when they change, not on every playhead frame.
struct SongWaveCanvas: View, Equatable {
    let columns: SongColumns
    let ceilingDB: Float
    let zoom: MeterZoom
    let width: CGFloat
    let hasData: Bool
    let isPlugin: Bool
    var timelineSeconds: Double = 0

    var body: some View {
        Canvas { g, _ in draw(g) }
    }

    private func draw(_ c: GraphicsContext) {
        typealias S = PlateSongScreen
        let W = width, L = S.side, R = W - S.side
        let top = S.plotTop, bottom = S.plotBottom
        let cy = (top + bottom) / 2, k = (bottom - top) / 2 - 2
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: S.H)), with: .color(Color(hex: 0x0b0c0e)))
        c.fill(Path(CGRect(x: 0, y: 0, width: W, height: S.H)),
               with: .radialGradient(Gradient(colors: [Color(red: 0.627, green: 0.667, blue: 0.725).opacity(0.07),
                                                       Color(red: 0.627, green: 0.667, blue: 0.725).opacity(0)]),
                                     center: CGPoint(x: 90, y: 25), startRadius: 1, endRadius: 260))
        // plot well and centre line
        c.fill(Path(CGRect(x: L, y: top, width: R - L, height: bottom - top)), with: .color(Color(hex: 0x08090a)))
        var mid = Path(); mid.move(to: CGPoint(x: L, y: cy)); mid.addLine(to: CGPoint(x: R, y: cy))
        c.stroke(mid, with: .color(Color(hex: 0x1d1e21)), lineWidth: 1)

        let n = columns.count
        let colW = (R - L) / CGFloat(n)
        @inline(__always) func y(_ v: Float) -> CGFloat { cy - zoom.position(sample: v) * k }
        @inline(__always) func x(_ i: Int) -> CGFloat { L + CGFloat(i) * colW }

        // never-received stretches (plug-in): faint hatching, nothing invented
        var unknown = Path()
        var runStart = -1
        for i in 0...n {
            let isUnknown = i < n && columns.state[i] == .unknown && !(columns.srcHi[i] > 0 || columns.srcLo[i] < 0)
            if isUnknown && runStart < 0 { runStart = i }
            if !isUnknown && runStart >= 0 {
                unknown.addRect(CGRect(x: x(runStart), y: top, width: x(i) - x(runStart), height: bottom - top))
                runStart = -1
            }
        }
        if hasData && isPlugin {
            var hatch = c
            hatch.clip(to: unknown)
            var lines = Path()
            var hx = L - (bottom - top)
            while hx < R {
                lines.move(to: CGPoint(x: hx, y: bottom)); lines.addLine(to: CGPoint(x: hx + (bottom - top), y: top))
                hx += 9
            }
            hatch.stroke(lines, with: .color(Color(hex: 0x1a1b1e)), lineWidth: 1)
        }

        // layers, back to front
        var srcBand = Path(), inBand = Path(), inStale = Path()
        var outBand = Path(), outStale = Path(), cut = Path(), cutStale = Path()
        for i in 0..<n {
            let x0 = x(i), w = colW + 0.35
            switch columns.state[i] {
            case .unknown:
                // app, before the first analysis: the untouched file in grey
                if columns.srcHi[i] > 0 || columns.srcLo[i] < 0 {
                    srcBand.addRect(band(x0, w, y(columns.srcHi[i]), y(columns.srcLo[i]), 1))
                }
            case .current, .stale:
                let stale = columns.state[i] == .stale
                let pHi = columns.preHi[i], pLo = columns.preLo[i]
                let qHi = columns.postHi[i], qLo = columns.postLo[i]
                let r1 = band(x0, w, y(pHi), y(pLo), 1)
                if stale { inStale.addRect(r1) } else { inBand.addRect(r1) }
                let r2 = band(x0, w, y(columns.outHi[i]), y(columns.outLo[i]), 1)
                if stale { outStale.addRect(r2) } else { outBand.addRect(r2) }
                // what the clipper took off: from its output up to its input, for the same samples
                if pHi - qHi > 1e-5 {
                    let r = CGRect(x: x0, y: y(pHi), width: w, height: max(0.6, y(qHi) - y(pHi)))
                    if stale { cutStale.addRect(r) } else { cut.addRect(r) }
                }
                if qLo - pLo > 1e-5 {
                    let r = CGRect(x: x0, y: y(qLo), width: w, height: max(0.6, y(pLo) - y(qLo)))
                    if stale { cutStale.addRect(r) } else { cut.addRect(r) }
                }
            }
        }
        c.fill(srcBand, with: .color(PlateSongScreen.inputColor.opacity(0.75)))
        c.fill(inBand, with: .color(PlateSongScreen.inputColor))
        c.fill(inStale, with: .color(PlateSongScreen.inputColor.opacity(0.45)))
        c.fill(outBand, with: .color(PlateSongScreen.outputColor.opacity(0.92)))
        c.fill(outStale, with: .color(PlateSongScreen.outputColor.opacity(0.35)))
        c.fill(cut, with: .color(PlateSongScreen.clipColor.opacity(0.82)))
        c.fill(cutStale, with: .color(PlateSongScreen.clipColor.opacity(0.32)))

        // ceiling: the clip stage's +/- threshold on the waveform's own scale
        let ceil = zoom.position(ceilingDB) * k
        for yy in [cy - ceil, cy + ceil] {
            var p = Path(); p.move(to: CGPoint(x: L, y: yy)); p.addLine(to: CGPoint(x: R, y: yy))
            c.stroke(p, with: .color(PlateSongScreen.ceilingColor.opacity(0.9)), lineWidth: 1)
        }

        if !hasData {
            c.draw(Text(isPlugin ? "PLAY THE SONG IN THE HOST TO CAPTURE IT" : "READING FILE")
                    .font(.system(size: 11, weight: .medium)).tracking(1).foregroundColor(PlateSongScreen.labelColor),
                   at: CGPoint(x: (L + R) / 2, y: cy), anchor: .center)
        }
        drawRuler(c, L: L, R: R)

        // readout row: a hairline above it and between elapsed / total and MAX CLIP
        var rule = Path()
        rule.move(to: CGPoint(x: 8, y: S.readoutTop)); rule.addLine(to: CGPoint(x: W - 8, y: S.readoutTop))
        rule.move(to: CGPoint(x: W / 2, y: S.readoutTop + 5)); rule.addLine(to: CGPoint(x: W / 2, y: S.H - 4))
        c.stroke(rule, with: .color(Color(hex: 0x232427)), lineWidth: 1)
    }

    private func band(_ x: CGFloat, _ w: CGFloat, _ yTop: CGFloat, _ yBottom: CGFloat, _ thick: CGFloat) -> CGRect {
        let m = (yTop + yBottom) / 2
        let a = min(yTop, m - thick / 2), b = max(yBottom, m + thick / 2)
        return CGRect(x: x, y: a, width: w, height: b - a)
    }

    /// Time ruler under the waveform: labelled steps far enough apart to read (fewer on the
    /// iPhone's narrower glass, more on the iPad's), half steps as plain ticks, and the end time.
    private func drawRuler(_ c: GraphicsContext, L: CGFloat, R: CGFloat) {
        typealias S = PlateSongScreen
        let duration = timelineSeconds
        var base = Path(); base.move(to: CGPoint(x: L, y: S.rulerY)); base.addLine(to: CGPoint(x: R, y: S.rulerY))
        c.stroke(base, with: .color(Color(hex: 0x2a2b2e)), lineWidth: 1)
        guard duration > 0 else { return }
        let step = SongTime.rulerStep(duration: duration, width: Double(R - L), minGap: 62)
        var ticks = Path(), grid = Path()
        let endLabel = SongTime.text(duration)
        var t = 0.0
        while t <= duration + 1e-6 {
            let xx = L + (R - L) * CGFloat(t / duration)
            ticks.move(to: CGPoint(x: xx, y: S.rulerY)); ticks.addLine(to: CGPoint(x: xx, y: S.rulerY + 4))
            grid.move(to: CGPoint(x: xx, y: S.plotTop)); grid.addLine(to: CGPoint(x: xx, y: S.plotBottom))
            // keep clear of the end label
            if R - xx > 40 || t == 0 {
                c.draw(Text(SongTime.text(t)).font(.system(size: 10)).monospacedDigit().foregroundColor(S.labelColor),
                       at: CGPoint(x: xx, y: S.rulerLabelY), anchor: t == 0 ? .leading : .center)
            }
            let half = t + step / 2
            if half < duration {
                let hx = L + (R - L) * CGFloat(half / duration)
                ticks.move(to: CGPoint(x: hx, y: S.rulerY)); ticks.addLine(to: CGPoint(x: hx, y: S.rulerY + 2))
            }
            t += step
        }
        c.stroke(grid, with: .color(Color.white.opacity(0.035)), lineWidth: 1)
        c.stroke(ticks, with: .color(Color(hex: 0x4a4c50)), lineWidth: 1)
        c.draw(Text(endLabel).font(.system(size: 10)).monospacedDigit().foregroundColor(S.labelColor),
               at: CGPoint(x: R, y: S.rulerLabelY), anchor: .trailing)
    }
}
