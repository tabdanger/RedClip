import Accelerate
import Foundation

// MARK: - SPECTRUM analyser
//
// The screen shows two spectra of the real audio, measured at two taps in ClipDSP.process:
//
//   INPUT   the base-rate sample after the Input and Drive gains (x * sIn * sDrive), the last
//           point before the oversampled clip stage. Red, the clipper, Broil and Alchemy all run
//           inside that stage, after this tap.
//   OUTPUT  the wet branch after the clip stage, the down-sampling filter, Box Tone and the
//           anti-overshoot clamp: the clipped signal before the Wet / Dry blend, Output gain,
//           Unity and Bypass.
//
// The output comes out of the oversampling filters a few samples late (0 / 4 / 5 frames at
// 1x / 2x / 4x, the same figure the scope rings use), so the input copy is written that many
// slots ahead in its ring: slot k of every ring holds one matched moment. Nothing is delayed
// in the audio itself and no DSP stage moves; the taps only copy values that already exist.
//
// Threads:
//   - audio thread: while the screen is showing (SpectrumFeed.on), stores four floats per frame
//     into preallocated rings and publishes the frame count once per block. No FFT, allocation,
//     lock, log or dispatch;
//   - analysis worker (SpectrumAnalyzer, its own serial queue, 30 ticks a second): copies whole
//     4096-frame windows out of the rings (50 % overlap), runs the FFTs (Accelerate), applies
//     the ballistics and leaves a finished frame for the screen;
//   - main thread: the screen reads the newest finished frame (SpectrumAnalyzer.latest).
// If the worker falls behind, it skips to the newest audio; the audio thread never waits.

/// Sample copies from the audio thread to the analyser. Allocated once, never resized.
final class SpectrumFeed: @unchecked Sendable {
    static let size = 32768                          // power of two (~680 ms at 48 kHz)
    static let mask = size - 1

    let on = AtomicInt(0)            // 1 = the screen is showing; the audio thread fills the rings
    let inL = AtomicFloats(count: SpectrumFeed.size)
    let inR = AtomicFloats(count: SpectrumFeed.size)
    let outL = AtomicFloats(count: SpectrumFeed.size)
    let outR = AtomicFloats(count: SpectrumFeed.size)
    let written = AtomicInt(0)       // frames written so far (never wraps), published per block

    deinit {
        on.deallocate(); written.deallocate()
        for r in [inL, inR, outL, outR] { r.deallocate() }
    }
}

/// One finished analyser frame, ready to draw.
struct SpectrumFrame {
    /// Display points, log-spaced from 20 Hz to `topHz`; dBFS (0 = a full-scale sine).
    var input: [Float]
    var output: [Float]
    var topHz: Double
    /// Audio has arrived recently (false: the source is paused, so the frame is held).
    var live: Bool

    static let empty = SpectrumFrame(input: [], output: [], topHz: 20_000, live: false)
}

/// The spectrum maths, independent of threads and rings (tested directly).
final class SpectrumEngine {
    static let fftSize = 4096
    static let hop = fftSize / 2                  // 50 % overlap
    static let points = 384                       // display points across 20 Hz ... top
    static let lowHz = 20.0
    static let floorDB: Float = -100              // silence decays to here (the plot ends at -72)
    static let attack = 0.010                     // seconds (one-pole time constants)
    static let release = 0.200

    let sampleRate: Double
    let topHz: Double
    private let n = SpectrumEngine.fftSize
    private let setup: vDSP_DFT_Setup
    private var window: [Float]
    private let scale: Float                      // |X|^2 -> peak amplitude^2 of a sine
    private var re: [Float], im: [Float], outRe: [Float], outIm: [Float], power: [Float]
    private var powL: [Float], powR: [Float]
    /// Per display point: the FFT bins it covers (lo...hi), or, where the bins are wider than
    /// the point's band, the two bins around it and how far between them it sits.
    private var spans: [Span] = []

    struct Span {
        var lo: Int, hi: Int
        var frac: Float = 0           // between lo and hi = lo + 1, when `between`
        var between = false
    }

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        topHz = min(20_000, sampleRate / 2)
        setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(SpectrumEngine.fftSize), .FORWARD)!
        // periodic Hann; its sum is the window's coherent gain times N
        let N = SpectrumEngine.fftSize
        let w = (0..<N).map { 0.5 - 0.5 * Float(cos(2 * Double.pi * Double($0) / Double(N))) }
        let sum = w.reduce(0, +)
        window = w
        // a sine of amplitude A centred on bin k gives |X[k]| = A * sum / 2 (the unscaled complex
        // DFT), so A^2 = |X[k]|^2 * (2 / sum)^2
        scale = (2 / sum) * (2 / sum)
        let zeros = [Float](repeating: 0, count: N)
        re = zeros; im = zeros; outRe = zeros; outIm = zeros; power = zeros
        let bins = [Float](repeating: 0, count: N / 2 + 1)
        powL = bins; powR = bins
        spans = Self.makeSpans(sampleRate: sampleRate, topHz: topHz)
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    /// Frequency of display point i.
    static func frequency(_ i: Int, topHz: Double) -> Double {
        lowHz * pow(topHz / lowHz, Double(i) / Double(points - 1))
    }

    private static func makeSpans(sampleRate: Double, topHz: Double) -> [Span] {
        let binHz = sampleRate / Double(fftSize)
        let last = fftSize / 2
        return (0..<points).map { i in
            let f = frequency(i, topHz: topHz)
            let ratio = pow(topHz / lowHz, 0.5 / Double(points - 1))     // half a point either side
            let lo = Int((f / ratio / binHz).rounded(.up)), hi = Int((f * ratio / binHz).rounded(.down))
            if hi >= lo { return Span(lo: min(max(lo, 1), last), hi: min(max(hi, 1), last)) }
            let k = f / binHz
            let k0 = min(max(Int(k.rounded(.down)), 1), last - 1)
            return Span(lo: k0, hi: k0 + 1, frac: Float(min(max(k - Double(k0), 0), 1)), between: true)
        }
    }

    /// Power spectrum of one channel (amplitude^2 per bin, 1 = a full-scale sine).
    private func spectrum(_ x: UnsafePointer<Float>, into dest: inout [Float]) {
        let N = vDSP_Length(n)
        window.withUnsafeBufferPointer { w in
            re.withUnsafeMutableBufferPointer { r in vDSP_vmul(x, 1, w.baseAddress!, 1, r.baseAddress!, 1, N) }
        }
        vDSP_vclr(&im, 1, N)
        vDSP_DFT_Execute(setup, re, im, &outRe, &outIm)
        outRe.withUnsafeMutableBufferPointer { r in
            outIm.withUnsafeMutableBufferPointer { i in
                var z = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_zvmags(&z, 1, &power, 1, N)
            }
        }
        var s = scale
        dest.withUnsafeMutableBufferPointer { d in
            vDSP_vsmul(power, 1, &s, d.baseAddress!, 1, vDSP_Length(n / 2 + 1))
        }
    }

    /// dBFS per display point for one stereo signal. The two channels are analysed separately and
    /// their powers averaged before the dB conversion (never L + R first, which would hide audio
    /// that is out of phase between the channels): a full-scale sine on both reads 0 dBFS.
    func analyse(left: UnsafePointer<Float>, right: UnsafePointer<Float>) -> [Float] {
        spectrum(left, into: &powL)
        spectrum(right, into: &powR)
        var out = [Float](repeating: SpectrumEngine.floorDB, count: SpectrumEngine.points)
        for (i, s) in spans.enumerated() {
            let p: Float
            if s.between {
                let a = (powL[s.lo] + powR[s.lo]) * 0.5, b = (powL[s.hi] + powR[s.hi]) * 0.5
                p = a + (b - a) * s.frac
            } else {
                var top: Float = 0
                for k in s.lo...s.hi { top = max(top, (powL[k] + powR[k]) * 0.5) }  // the band's strongest bin
                p = top
            }
            out[i] = max(10 * log10(max(p, 1e-12)), SpectrumEngine.floorDB)
        }
        return out
    }

    /// One step of the ballistics (both traces use the same): rise fast, fall with a ~200 ms
    /// release, in dB.
    static func ballistics(_ current: inout [Float], toward target: [Float], dt: Double) {
        let up = Float(1 - exp(-dt / attack)), down = Float(1 - exp(-dt / release))
        for i in current.indices where i < target.count {
            let d = target[i] - current[i]
            current[i] += d * (d > 0 ? up : down)
        }
    }
}

/// The background worker behind the SPECTRUM screen, one per faceplate (so every plug-in
/// instance has its own). Runs only while the screen is showing.
final class SpectrumAnalyzer: @unchecked Sendable {
    private let shared: SharedState
    private var feed: SpectrumFeed { shared.spectrum }
    private let queue = DispatchQueue(label: "RedClip.spectrum", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    // worker state (queue only)
    private var engine: SpectrumEngine?
    private var cursor = 0                        // start of the next window in the rings
    private var seen = 0                          // `written` at the previous tick
    private var lastTick = DispatchTime.now()
    private var lastAudio = DispatchTime(uptimeNanoseconds: 0)
    private var target: (input: [Float], output: [Float])?
    private var shown: (input: [Float], output: [Float]) = ([], [])
    private var bufL = [Float](repeating: 0, count: SpectrumEngine.fftSize)
    private var bufR = [Float](repeating: 0, count: SpectrumEngine.fftSize)
    private var bufOL = [Float](repeating: 0, count: SpectrumEngine.fftSize)
    private var bufOR = [Float](repeating: 0, count: SpectrumEngine.fftSize)

    // the finished frame, handed to the main thread (never touched by the audio thread)
    private let lock = NSLock()
    private var finished = SpectrumFrame.empty

    init(shared: SharedState) { self.shared = shared }

    deinit {
        timer?.cancel()
        feed.on.value = 0
    }

    /// The newest finished frame (main thread).
    var latest: SpectrumFrame {
        lock.lock(); defer { lock.unlock() }
        return finished
    }

    /// The screen appeared (or the app came back): start filling the rings and analysing.
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            restart()
            feed.on.value = 1
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(4))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    /// The screen went away: the audio thread stops copying and the worker sleeps. Audio
    /// processing carries on untouched.
    func stop() {
        feed.on.value = 0
        queue.async { [self] in
            feed.on.value = 0          // in case a start() queued just before this undid it
            timer?.cancel()
            timer = nil
        }
    }

    /// Fresh start: newest audio only, curves from the floor.
    private func restart() {
        engine = nil
        target = nil
        shown = ([], [])
        cursor = feed.written.acquire()
        seen = cursor
        lastTick = .now()
        publish(live: false)
    }

    private func tick() {
        let rate = Double(max(shared.sampleRate.value, 8_000))
        if engine?.sampleRate != rate {
            // new or changed sample rate: new bins, new mapping, newest audio only
            restart()
            engine = SpectrumEngine(sampleRate: rate)
            shown = ([Float](repeating: SpectrumEngine.floorDB, count: SpectrumEngine.points),
                     [Float](repeating: SpectrumEngine.floorDB, count: SpectrumEngine.points))
        }
        guard let engine else { return }
        let now = DispatchTime.now()
        let dt = Double(now.uptimeNanoseconds - lastTick.uptimeNanoseconds) / 1e9
        lastTick = now

        let written = feed.written.acquire()
        let moving = written != seen
        seen = written
        if moving { lastAudio = now }

        let N = SpectrumEngine.fftSize, hop = SpectrumEngine.hop
        // fallen too far behind (or the rings restarted): skip to the newest whole window
        if written - cursor > SpectrumFeed.size / 2 || written < cursor {
            cursor = max(0, written - N)
        }
        // more than a few windows waiting: only the newest matter on screen
        let waiting = (written - cursor - N) / hop + 1
        if waiting > 3 { cursor += (waiting - 1) * hop }

        while written - cursor >= N {
            if let frame = analyseWindow(at: cursor, engine) { target = frame }
            cursor += hop
        }

        // the curves only move while audio flows; a paused source holds the last frame
        if moving, let target {
            SpectrumEngine.ballistics(&shown.input, toward: target.input, dt: min(dt, 0.1))
            SpectrumEngine.ballistics(&shown.output, toward: target.output, dt: min(dt, 0.1))
        }
        let live = Double(now.uptimeNanoseconds - lastAudio.uptimeNanoseconds) / 1e9 < 0.25
        publish(live: live)
    }

    /// Copies one window of all four rings and analyses it; nil if the audio thread overwrote
    /// part of it while it was being copied (the window is dropped).
    private func analyseWindow(at start: Int, _ engine: SpectrumEngine) -> (input: [Float], output: [Float])? {
        let N = SpectrumEngine.fftSize, m = SpectrumFeed.mask
        let f = feed
        for i in 0..<N {
            let slot = (start + i) & m
            bufL[i] = f.inL[slot]; bufR[i] = f.inR[slot]
            bufOL[i] = f.outL[slot]; bufOR[i] = f.outR[slot]
        }
        // the input is written up to 5 slots ahead of `written`; keep well clear of a lap
        guard f.written.acquire() + 64 - start <= SpectrumFeed.size else { return nil }
        let input = bufL.withUnsafeBufferPointer { l in
            bufR.withUnsafeBufferPointer { r in engine.analyse(left: l.baseAddress!, right: r.baseAddress!) }
        }
        let output = bufOL.withUnsafeBufferPointer { l in
            bufOR.withUnsafeBufferPointer { r in engine.analyse(left: l.baseAddress!, right: r.baseAddress!) }
        }
        return (input, output)
    }

    private func publish(live: Bool) {
        let frame = SpectrumFrame(input: shown.input, output: shown.output,
                                  topHz: engine?.topHz ?? 20_000, live: live)
        lock.lock()
        finished = frame
        lock.unlock()
    }
}
