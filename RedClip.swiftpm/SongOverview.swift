import Foundation

// MARK: - SONG view data
//
// The SONG screen shows the whole song on one fixed timeline. Its layers come from the real audio
// at two points in ClipDSP, both measured on the same samples:
//   - the clip stage: what goes INTO the clipper (after Input, Drive and Red) and what the
//     clipper made of that very sample, at the oversampled rate, with the selected curve. Their
//     difference is the CLIPPED layer; the INPUT layer is the clipper's input;
//   - the final output (after Broil, Fire, Wet / Dry, Output, Unity and Bypass): the OUTPUT
//     layer. Wet / Dry and Output can carry it past the ceiling lines, which mark the clip stage.
// The output leaves the oversampling filters a few samples after the clip stage, so each summary
// carries both delays and every layer is filed under the frame its audio came from.
//
// Where the audio comes from:
//   - app: the loaded file. SongAnalyzer runs it through a private ClipDSP (its own SharedState,
//     never the live one) with the current settings, in the background; a settings change marks
//     the result stale and analyses again once the controls settle; a newer job stops an older one;
//   - plug-in: the host owns the song, so Red Clip only knows the audio it has been handed. The
//     audio thread writes 64-frame summaries into CaptureRing, stamped with the host's sample
//     position; the UI folds them into the overview. Places never played stay unknown, and
//     audio captured under other settings is drawn as such.

/// Where SharedState.songFrame comes from.
enum SongClock: Int {
    case none = 0       // nothing loaded / no render yet
    case file = 1       // the app's player: frames into the loaded file
    case host = 2       // a DAW's transport: its sample position
    case relative = 3   // a host without a transport: frames processed since Red Clip started
}

/// A fingerprint of every setting that changes what the SONG layers show (all of them except
/// Link, which only couples two knobs on the face). The audio thread stamps each summary with it;
/// the UI compares it with the current one, so audio captured under other settings shows as such.
/// Allocation-free; never 0 (= nothing captured) or -1 (= mixed).
enum SongStamp {
    static let none = 0
    static let mixed = -1

    @inline(__always) static func of(_ p: AtomicFloats) -> Int {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for i in 0..<p.count where i != Param.link.rawValue {
            h = (h ^ UInt64(p[i].bitPattern)) &* 0x0000_0100_0000_01b3
        }
        return Int(truncatingIfNeeded: h >> 2) | 1
    }
}

/// One summary of up to 64 frames (never across two process() calls, so never across a jump in
/// the timeline).
struct CaptureRecord {
    var frame: Int          // timeline frame of the first sample
    var frames: Int
    var clipDelay: Int      // how many frames the clip stage runs behind the input
    var outDelay: Int       // and the output
    var stamp: Int          // SongStamp of the settings it was processed with
    var preHi: Float, postHi: Float     // most positive sample into the clipper, and the clipper's output for it
    var preLo: Float, postLo: Float     // most negative, likewise
    var outHi: Float, outLo: Float      // final output extremes (either channel)
    var reductionDB: Float              // most gain the clipper took off one sample
}

/// Audio thread -> UI: fixed ring of CaptureRecords. Every field is atomic and the count is
/// published with release ordering after the record is written, so the reader never waits and
/// the writer never allocates. A reader that falls a whole ring behind loses the oldest records
/// (that stretch of the timeline simply stays unknown).
final class CaptureRing: @unchecked Sendable {
    static let defaultCapacity = 8192           // ~11 s of 48 kHz audio in 64-frame summaries
    static let tickFrames = 64

    let capacity: Int
    private let mask: Int
    private let frame, frames, delays, stamp: AtomicInts
    private let preHi, postHi, preLo, postLo, outHi, outLo, reduction: AtomicFloats
    let written = AtomicInt(0)                  // records written so far (never wraps), published

    init(capacity wanted: Int) {
        var c = 64
        while c < wanted { c <<= 1 }
        capacity = c
        mask = c - 1
        frame = AtomicInts(count: c); frames = AtomicInts(count: c)
        delays = AtomicInts(count: c); stamp = AtomicInts(count: c)
        preHi = AtomicFloats(count: c); postHi = AtomicFloats(count: c)
        preLo = AtomicFloats(count: c); postLo = AtomicFloats(count: c)
        outHi = AtomicFloats(count: c); outLo = AtomicFloats(count: c)
        reduction = AtomicFloats(count: c)
    }

    deinit {
        for a in [frame, frames, delays, stamp] { a.deallocate() }
        for a in [preHi, postHi, preLo, postLo, outHi, outLo, reduction] { a.deallocate() }
        written.deallocate()
    }

    /// Audio thread (the only writer).
    @inline(__always) func push(frame f: Int, frames n: Int, delays d: Int, stamp s: Int,
                                preHi a: Float, postHi b: Float, preLo c: Float, postLo e: Float,
                                outHi g: Float, outLo h: Float, reductionDB r: Float) {
        let w = written.value
        let i = w & mask
        frame[i] = f; frames[i] = n; delays[i] = d; stamp[i] = s
        preHi[i] = a; postHi[i] = b; preLo[i] = c; postLo[i] = e
        outHi[i] = g; outLo[i] = h; reduction[i] = r
        written.publish(w &+ 1)
    }

    /// Reader: every record after `cursor`, oldest first; moves the cursor on. Returns how many
    /// records were lost because the reader fell behind (or were being overwritten while read).
    @discardableResult
    func drain(_ cursor: inout Int, _ body: (CaptureRecord) -> Void) -> Int {
        let w = written.acquire()
        var start = cursor
        var lost = 0
        if w - start > capacity { lost = w - start - capacity; start = w - capacity }
        if w < start { start = w }                      // a ring that started again
        var batch: [CaptureRecord] = []
        batch.reserveCapacity(w - start)
        for k in start..<w {
            let i = k & mask
            let d = delays[i]
            batch.append(CaptureRecord(frame: frame[i], frames: frames[i], clipDelay: d & 0xff, outDelay: (d >> 8) & 0xff,
                                       stamp: stamp[i], preHi: preHi[i], postHi: postHi[i], preLo: preLo[i], postLo: postLo[i],
                                       outHi: outHi[i], outLo: outLo[i], reductionDB: reduction[i]))
        }
        // anything the writer may have started overwriting while it was copied is dropped
        let safeFrom = written.acquire() - capacity + 1
        let skip = min(batch.count, max(0, safeFrom - start))
        lost += skip
        for r in batch.dropFirst(skip) { body(r) }
        cursor = w
        return lost
    }
}

// MARK: - The overview

/// The whole song, summarised into a fixed number of bins (so a long song costs no more memory
/// than a short one). Each bin keeps the extremes of its audio, so short transients survive any
/// amount of reduction. Owned by one thread at a time (a background analysis builds one, then
/// hands it to the main thread).
final class SongOverview: @unchecked Sendable {
    static let binCount = 4096

    let sampleRate: Double
    /// Frames in the song, when known (a loaded file). 0: unknown (a DAW), the timeline grows to fit.
    let totalFrames: Int
    private(set) var framesPerBin: Int
    private(set) var capturedEnd = 0            // one past the last frame holding data

    // clip stage: extremes into the clipper and the clipper's output for those same samples
    private(set) var preHi: [Float], postHi: [Float], preLo: [Float], postLo: [Float]
    private(set) var outHi: [Float], outLo: [Float]          // final output
    private(set) var reduction: [Float]                      // most gain reduction (dB)
    private(set) var stamp: [Int]                            // SongStamp; 0 = never received
    // the untouched source (app only, before any control): drawn while the first analysis runs
    private(set) var srcHi: [Float] = [], srcLo: [Float] = []

    init(totalFrames: Int, sampleRate: Double) {
        self.totalFrames = max(0, totalFrames)
        self.sampleRate = sampleRate
        let n = Self.binCount
        framesPerBin = totalFrames > 0 ? max(1, (totalFrames + n - 1) / n) : 512   // unknown: ~44 s at 48 kHz, then doubles
        let z = [Float](repeating: 0, count: n)
        preHi = z; postHi = z; preLo = z; postLo = z; outHi = z; outLo = z; reduction = z
        stamp = [Int](repeating: SongStamp.none, count: n)
    }

    /// Frames the bins cover now.
    var extent: Int { framesPerBin * Self.binCount }
    var hasSource: Bool { !srcHi.isEmpty }

    // MARK: Filling

    func add(_ r: CaptureRecord) {
        guard r.frame >= 0, r.frames > 0 else { return }
        let end = r.frame + r.frames
        if totalFrames > 0 {
            guard r.frame < totalFrames else { return }
        } else {
            while end > extent && framesPerBin < Int.max / (4 * Self.binCount) { grow() }
        }
        capturedEnd = max(capturedEnd, min(end, totalFrames > 0 ? totalFrames : end))
        for b in bins(from: r.frame - r.clipDelay, count: r.frames) {
            claim(b, r.stamp)
            if r.preHi > preHi[b] { preHi[b] = r.preHi; postHi[b] = r.postHi }
            if r.preLo < preLo[b] { preLo[b] = r.preLo; postLo[b] = r.postLo }
            reduction[b] = max(reduction[b], r.reductionDB)
        }
        for b in bins(from: r.frame - r.outDelay, count: r.frames) {
            claim(b, r.stamp)
            outHi[b] = max(outHi[b], r.outHi)
            outLo[b] = min(outLo[b], r.outLo)
        }
    }

    /// The untouched source, both channels (app).
    func setSource(hi: [Float], lo: [Float]) {
        guard hi.count == Self.binCount, lo.count == Self.binCount else { return }
        srcHi = hi; srcLo = lo
    }

    /// Bins holding frames [from, from + count), clamped to the timeline.
    private func bins(from: Int, count: Int) -> ClosedRange<Int> {
        let last = Self.binCount - 1
        let a = min(max(from, 0) / framesPerBin, last)
        let b = min(max(from + count - 1, 0) / framesPerBin, last)
        return a...max(a, b)
    }

    /// A bin about to take audio stamped `s`: audio processed with other settings is replaced,
    /// so playing a passage again after a change shows the change there.
    private func claim(_ b: Int, _ s: Int) {
        if stamp[b] == s { return }
        if stamp[b] != SongStamp.none { clear(b) }
        stamp[b] = s
    }

    private func clear(_ b: Int) {
        preHi[b] = 0; postHi[b] = 0; preLo[b] = 0; postLo[b] = 0
        outHi[b] = 0; outLo[b] = 0; reduction[b] = 0
        stamp[b] = SongStamp.none
    }

    /// Unknown length: twice as many frames per bin, pairs merged (extremes kept exactly).
    private func grow() {
        let half = Self.binCount / 2
        for i in 0..<half {
            let a = 2 * i, b = 2 * i + 1
            let pick = preHi[b] > preHi[a] ? b : a
            let pickLo = preLo[b] < preLo[a] ? b : a
            let sa = stamp[a], sb = stamp[b]
            let s = sa == SongStamp.none ? sb : (sb == SongStamp.none || sb == sa ? sa : SongStamp.mixed)
            let v = (preHi[pick], postHi[pick], preLo[pickLo], postLo[pickLo],
                     max(outHi[a], outHi[b]), min(outLo[a], outLo[b]), max(reduction[a], reduction[b]))
            preHi[i] = v.0; postHi[i] = v.1; preLo[i] = v.2; postLo[i] = v.3
            outHi[i] = v.4; outLo[i] = v.5; reduction[i] = v.6
            stamp[i] = s
        }
        for i in half..<Self.binCount { clear(i) }
        framesPerBin *= 2
    }

    // MARK: Reading for the screen

    /// The timeline cut into `count` columns over [0, timeline) frames, each holding the extremes
    /// of every bin it covers (transients kept). O(bins + columns), so it costs the same for a
    /// 10-second loop as for an hour; the screen calls it only when the data or its width changes.
    func columns(_ count: Int, timeline: Int, current: Int) -> SongColumns {
        var out = SongColumns(count: max(1, count))
        let n = out.count
        let span = max(1, timeline)
        for c in 0..<n {
            let f0 = Int(Double(span) * Double(c) / Double(n))
            let f1 = max(f0 + 1, Int(Double(span) * Double(c + 1) / Double(n)))
            let b0 = f0 / framesPerBin
            if b0 >= Self.binCount { break }
            let b1 = min((f1 - 1) / framesPerBin, Self.binCount - 1)
            var known = false, stale = false
            var pHi: Float = 0, qHi: Float = 0, pLo: Float = 0, qLo: Float = 0
            var oHi: Float = 0, oLo: Float = 0, sHi: Float = 0, sLo: Float = 0
            for b in b0...b1 {
                if hasSource { sHi = max(sHi, srcHi[b]); sLo = min(sLo, srcLo[b]) }
                let s = stamp[b]
                if s == SongStamp.none { continue }
                known = true
                if s != current { stale = true }
                if preHi[b] > pHi { pHi = preHi[b]; qHi = postHi[b] }
                if preLo[b] < pLo { pLo = preLo[b]; qLo = postLo[b] }
                oHi = max(oHi, outHi[b]); oLo = min(oLo, outLo[b])
            }
            out.state[c] = known ? (stale ? .stale : .current) : .unknown
            out.preHi[c] = pHi; out.postHi[c] = qHi; out.preLo[c] = pLo; out.postLo[c] = qLo
            out.outHi[c] = oHi; out.outLo[c] = oLo
            out.srcHi[c] = sHi; out.srcLo[c] = sLo
        }
        return out
    }
}

/// What the SONG screen draws: one entry per display column. A value type, so the waveform is
/// redrawn only when these change, never just because the playhead moved.
struct SongColumns: Equatable {
    enum State: UInt8 { case unknown, current, stale }
    var count: Int
    var preHi: [Float], postHi: [Float], preLo: [Float], postLo: [Float]
    var outHi: [Float], outLo: [Float]
    var srcHi: [Float], srcLo: [Float]
    var state: [State]

    init(count: Int) {
        self.count = count
        let z = [Float](repeating: 0, count: count)
        preHi = z; postHi = z; preLo = z; postLo = z; outHi = z; outLo = z; srcHi = z; srcLo = z
        state = [State](repeating: .unknown, count: count)
    }

    static let empty = SongColumns(count: 1)
}

// MARK: - Whole-file analysis (app)

/// A loaded file, by pointer: the player's buffer is read-only once loaded, and `owner` keeps it
/// alive for as long as an analysis holds this.
struct SongAudio: @unchecked Sendable {
    let left: UnsafePointer<Float>
    let right: UnsafePointer<Float>
    let frames: Int
    let sampleRate: Double
    let owner: AnyObject
}

enum SongAnalyzer {
    /// The untouched file per bin (max and min over both channels). nil if stopped.
    static func source(_ a: SongAudio, stop: () -> Bool) -> (hi: [Float], lo: [Float])? {
        let n = SongOverview.binCount
        let per = max(1, (a.frames + n - 1) / n)
        var hi = [Float](repeating: 0, count: n), lo = [Float](repeating: 0, count: n)
        var b = 0
        while b < n {
            if b % 256 == 0 && stop() { return nil }
            let from = b * per
            if from >= a.frames { break }
            let to = min(a.frames, from + per)
            var h: Float = 0, l: Float = 0
            for i in from..<to {
                let x = a.left[i], y = a.right[i]
                h = max(h, x, y); l = min(l, x, y)
            }
            hi[b] = h.isFinite ? h : 0; lo[b] = l.isFinite ? l : 0
            b += 1
        }
        return (hi, lo)
    }

    /// The whole file through a private ClipDSP with `settings` (one value per Param), filed into
    /// a new overview exactly as the plug-in files what it hears. Nothing here touches the live
    /// engine's state. nil if `stop` says a newer job took over.
    static func preview(_ a: SongAudio, settings: [Float], stop: () -> Bool,
                        progress: (Double) -> Void = { _ in }) -> SongOverview? {
        let state = SharedState(captureCapacity: 256)
        for (i, v) in settings.enumerated() where i < state.params.count { state.params[i] = v }
        state.captureOn.value = 1
        let dsp = ClipDSP(sampleRate: a.sampleRate, shared: state)
        let overview = SongOverview(totalFrames: a.frames, sampleRate: a.sampleRate)
        let chunk = 4096
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        let outR = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        let quiet = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
        quiet.initialize(repeating: 0, count: chunk)
        defer { outL.deallocate(); outR.deallocate(); quiet.deallocate() }

        // settle the control smoothers on 100 ms of silence (off the timeline, nothing filed),
        // so the song starts with the settings already in place and the filters empty
        dsp.timelineFrame = -1
        var settle = Int(a.sampleRate / 10)
        while settle > 0 {
            let n = min(chunk, settle)
            dsp.process(inL: quiet, inR: quiet, outL: outL, outR: outR, frames: n)
            settle -= n
        }
        var cursor = state.capture.written.acquire()
        var pos = 0
        var lastReport = 0
        while pos < a.frames {
            if stop() { return nil }
            let n = min(chunk, a.frames - pos)
            dsp.timelineFrame = pos
            dsp.process(inL: a.left + pos, inR: a.right + pos, outL: outL, outR: outR, frames: n)
            state.capture.drain(&cursor) { overview.add($0) }
            pos += n
            if pos - lastReport >= a.frames / 50 + 1 { lastReport = pos; progress(Double(pos) / Double(a.frames)) }
        }
        return overview
    }
}

/// "3:42"; "1:02:05" past an hour.
enum SongTime {
    static func text(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "-:--" }
        let s = Int(seconds)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Seconds between ruler labels: the smallest step that keeps `minGap` units between labels.
    static func rulerStep(duration: Double, width: Double, minGap: Double) -> Double {
        let steps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
        guard duration > 0, width > 0 else { return 60 }
        for s in steps where width * s / duration >= minGap { return s }
        return steps[steps.count - 1]
    }

    /// A plug-in timeline whose length isn't known: a round length that holds `frames`, so the
    /// picture stays put and only rescales when playback passes the end.
    static func roundedLength(_ seconds: Double) -> Double {
        let lengths: [Double] = [30, 60, 90, 120, 180, 240, 300, 360, 480, 600, 900, 1200, 1800, 2700, 3600]
        for l in lengths where seconds <= l { return l }
        return (seconds / 3600).rounded(.up) * 3600
    }
}
