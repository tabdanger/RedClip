import SwiftUI

/// Pulls meter values from the audio thread at display rate and applies ballistics.
/// The audio thread only ever writes "max since last read"; the UI reads and clears.
final class MeterReader {
    let shared: SharedState
    private(set) var inL: Float = 0, inR: Float = 0, outL: Float = 0, outR: Float = 0
    private(set) var inHold: Float = 0, outHold: Float = 0
    private(set) var inLUFS: Float = -70, outLUFS: Float = -70
    private(set) var reduction: Float = 0
    private(set) var clipLit = false
    private var clipUntil = Date.distantPast
    private var holdUntilIn = Date.distantPast, holdUntilOut = Date.distantPast
    private var last = Date.distantPast

    init(shared: SharedState) { self.shared = shared }

    /// Safe to call from several views in the same frame; only the first call per frame reads.
    func update(_ now: Date) {
        guard now.timeIntervalSince(last) > 0.008 else { return }
        let dt = Float(min(now.timeIntervalSince(last), 0.1))
        last = now
        let m = shared.meters
        func take(_ i: Meter) -> Float { let v = m[i.rawValue]; m[i.rawValue] = 0; return v }

        let fall = pow(10, -24 * dt / 20)   // 24 dB/s release
        inL = max(take(.inPeakL), inL * fall); inR = max(take(.inPeakR), inR * fall)
        outL = max(take(.outPeakL), outL * fall); outR = max(take(.outPeakR), outR * fall)

        // peak-hold markers: sit for 1.5 s, then glide down at 12 dB/s
        let holdFall = pow(10, -12 * dt / 20)
        let ip = max(inL, inR), op = max(outL, outR)
        if ip >= inHold { inHold = ip; holdUntilIn = now.addingTimeInterval(1.5) }
        else if now > holdUntilIn { inHold = max(ip, inHold * holdFall) }
        if op >= outHold { outHold = op; holdUntilOut = now.addingTimeInterval(1.5) }
        else if now > holdUntilOut { outHold = max(op, outHold * holdFall) }

        if take(.clip) > 0 { clipUntil = now.addingTimeInterval(0.4) }
        clipLit = now < clipUntil

        let r = take(.reductionDB)
        reduction = max(r, reduction - 12 * dt)

        inLUFS = m[Meter.inLUFS.rawValue]
        outLUFS = m[Meter.outLUFS.rawValue]
    }
}

/// The face's dB scale: 0, -6, -12, -18, -24, -36, -60 evenly spaced, linear in dB between marks.
enum FaceScale {
    static let marks: [Float] = [0, -6, -12, -18, -24, -36, -60]

    /// 0 at the top mark (0 dB) … 1 at the bottom mark (-60 dB).
    static func position(_ db: Float) -> CGFloat {
        if db >= 0 { return 0 }
        if db <= -60 { return 1 }
        for i in 0..<(marks.count - 1) where db <= marks[i] && db >= marks[i + 1] {
            let f = (marks[i] - db) / (marks[i] - marks[i + 1])
            return CGFloat((Float(i) + f) / Float(marks.count - 1))
        }
        return 1
    }
}

/// Animated segmented LED meter (L/R) with the face's scale on the right.
/// Redraws at display rate: instant attack, 24 dB/s release, the top lit segment fades in
/// proportionally so movement is smooth, a peak-hold segment floats above and glides down,
/// and the top segments flash when the signal hits the ceiling / clips.
struct LEDMeter: View {
    let title: String
    let reader: MeterReader
    let isInput: Bool
    private let segments = 26

    var body: some View {
        VStack(spacing: 14) {
            Theme.label(title, size: 19)
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 10) {
                    TimelineView(.animation) { ctx in
                        let _ = reader.update(ctx.date)
                        let l = isInput ? reader.inL : reader.outL
                        let r = isInput ? reader.inR : reader.outR
                        let hold = isInput ? reader.inHold : reader.outHold
                        let over = isInput ? reader.clipLit : hold >= 0.999
                        HStack(spacing: 12) {
                            bar(l, hold: hold, over: over)
                            bar(r, hold: hold, over: over)
                        }
                    }
                    HStack(spacing: 12) {
                        Text("L").frame(width: 32)
                        Text("R").frame(width: 32)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.text)
                }
                GeometryReader { geo in
                    let h = geo.size.height - 30
                    ForEach(FaceScale.marks.indices, id: \.self) { i in
                        HStack(spacing: 6) {
                            Rectangle().fill(Theme.text.opacity(0.7)).frame(width: 8, height: 1.5)
                            Text(i == 0 ? "-0" : "\(Int(FaceScale.marks[i]))")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.text)
                        }
                        .position(x: 24, y: CGFloat(i) / 6 * h + 10)
                    }
                }
                .frame(width: 48)
            }
        }
    }

    private func bar(_ g: Float, hold: Float, over: Bool) -> some View {
        let level = 1 - FaceScale.position(gainToDB(g))          // 0 … 1 from the bottom
        let holdLevel = 1 - FaceScale.position(gainToDB(hold))
        return Canvas { ctx, size in
            let pad: CGFloat = 4, gap: CGFloat = 2.5
            let n = CGFloat(segments)
            let segH = (size.height - 2 * pad - gap * (n - 1)) / n
            let holdIdx = Int((holdLevel * n).rounded(.up)) - 1
            for idx in 0..<segments {                             // 0 = bottom segment
                let lo = CGFloat(idx) / n
                // fractional fill of the segment currently being crossed -> smooth motion
                let fill = min(max((level - lo) * n, 0), 1)
                let top = idx >= segments - 3
                let y = size.height - pad - CGFloat(idx + 1) * segH - CGFloat(idx) * gap
                let rect = CGRect(x: pad, y: y, width: size.width - 2 * pad, height: segH)
                let shape = Path(roundedRect: rect, cornerRadius: 1.5)

                ctx.fill(shape, with: .color(Color(red: 0.25, green: 0.03, blue: 0.04)))
                var lit = fill
                if idx == holdIdx && holdLevel > 0.02 { lit = max(lit, 0.9) }
                if top && over { lit = 1 }
                if lit > 0 {
                    var glow = ctx
                    glow.addFilter(.shadow(color: Theme.glow.opacity(Double(0.75 * lit)), radius: 4))
                    let c = top ? (over ? Color.white : Theme.glowSoft) : Theme.glow
                    glow.fill(shape, with: .color(c.opacity(Double(0.25 + 0.75 * lit))))
                }
            }
        }
        .frame(width: 32)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 2))
    }
}

/// The main screen. The top edge of the trace reads against the face's dB scale; the lower half mirrors it.
/// Dim trace = signal going into the clipper (after Input + Drive), bright trace = output,
/// white-hot tips = what got clipped off.
struct WaveformView: View {
    let shared: SharedState
    let ceilingDB: Float
    let reader: MeterReader

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let _ = reader.update(ctx.date)
            GeometryReader { geo in
                let labelW: CGFloat = 62
                let plot = CGRect(x: labelW, y: 46, width: geo.size.width - labelW - 18, height: geo.size.height - 70)
                ZStack(alignment: .topLeading) {
                    // scale labels
                    ForEach(FaceScale.marks.indices, id: \.self) { i in
                        Text(i == 0 ? "0 dB" : "\(Int(FaceScale.marks[i]))")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .frame(width: labelW - 8, alignment: .trailing)
                            .position(x: (labelW - 8) / 2 + 4, y: plot.minY + CGFloat(i) / 6 * plot.height)
                    }
                    Canvas { g, _ in draw(g, plot) }
                    Text(String(format: "CEILING  %.1f dB", ceilingDB))
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(1.5)
                        .underline(color: Theme.glow)
                        .foregroundStyle(Theme.glow)
                        .shadow(color: Theme.glow.opacity(0.8), radius: 4)
                        .position(x: plot.maxX - 72, y: plot.minY + FaceScale.position(ceilingDB) * plot.height - 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Theme.screen)
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 6))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.glow.opacity(0.25), lineWidth: 1).padding(3))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func draw(_ g: GraphicsContext, _ plot: CGRect) {
        let n = SharedState.waveColumns
        let start = shared.waveWrite.pointee
        let colW = plot.width / CGFloat(n)
        let mid = plot.minY + FaceScale.position(-18) * plot.height    // mirror line (the -18 mark)
        let ceilY = plot.minY + FaceScale.position(ceilingDB) * plot.height

        // baseline
        var base = Path(); base.move(to: .init(x: plot.minX, y: plot.maxY)); base.addLine(to: .init(x: plot.maxX, y: plot.maxY))
        g.stroke(base, with: .color(Theme.text.opacity(0.18)), lineWidth: 1)

        func topY(_ level: Float) -> CGFloat {
            let y = plot.minY + FaceScale.position(gainToDB(level)) * plot.height
            return min(y, mid - 1)
        }

        var inPath = Path(), outPath = Path(), hot = Path()
        for i in 0..<n {
            let idx = (start + i) % n
            let x = plot.minX + CGFloat(i) * colW
            let ti = max(topY(shared.waveIn[idx]), plot.minY - 8)
            let to = topY(shared.waveOut[idx])
            inPath.addRect(CGRect(x: x, y: ti, width: colW + 0.4, height: 2 * (mid - ti)))
            outPath.addRect(CGRect(x: x, y: to, width: colW + 0.4, height: 2 * (mid - to)))
            if ti < ceilY - 0.5 {
                hot.addRect(CGRect(x: x, y: ti, width: colW + 0.4, height: ceilY - ti))
                hot.addRect(CGRect(x: x, y: 2 * mid - ceilY, width: colW + 0.4, height: ceilY - ti))
            }
        }
        g.fill(inPath, with: .color(Theme.glow.opacity(0.22)))
        var glow = g
        glow.addFilter(.shadow(color: Theme.glow.opacity(0.7), radius: 5))
        glow.fill(outPath, with: .linearGradient(Gradient(colors: [Theme.glowSoft, Theme.glow, Color(red: 0.75, green: 0.1, blue: 0.12), Theme.glow, Theme.glowSoft]),
                                                 startPoint: .init(x: 0, y: plot.minY), endPoint: .init(x: 0, y: 2 * mid - plot.minY)))
        g.fill(hot, with: .color(Color(red: 1, green: 0.86, blue: 0.84).opacity(0.9)))

        // ceiling (dashed)
        var p = Path(); p.move(to: .init(x: plot.minX, y: ceilY)); p.addLine(to: .init(x: plot.maxX, y: ceilY))
        g.stroke(p, with: .color(Theme.glow.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [9, 6]))
    }
}

/// "CLIP 2.7 dB" readout under the screen.
struct ClipReadout: View {
    let reader: MeterReader

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { ctx in
            let _ = reader.update(ctx.date)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                Text("CLIP").font(.system(size: 18, weight: .semibold)).tracking(3)
                Text(String(format: "%.1f", reader.reduction))
                    .font(.system(size: 40, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 70)
                Text("dB").font(.system(size: 18, weight: .semibold)).tracking(2)
            }
            .foregroundStyle(Theme.glow)
            .shadow(color: Theme.glow.opacity(0.8), radius: 6)
            .frame(width: 280, height: 56)
            .well(radius: 10)
        }
    }
}
