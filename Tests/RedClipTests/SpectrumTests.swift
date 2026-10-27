import XCTest

// The SPECTRUM screen: calibration of the FFT maths, stereo handling, ballistics, the two taps
// in ClipDSP (what they carry, that they line up, that clipping shows as harmonics) and the
// background analyser end to end.

final class SpectrumEngineTests: XCTestCase {
    private let sr = 48_000.0
    private let N = SpectrumEngine.fftSize

    private func sine(_ hz: Double, _ amp: Float, phase: Double = 0) -> [Float] {
        (0..<N).map { amp * Float(sin(2 * Double.pi * hz * Double($0) / sr + phase)) }
    }

    private func analyse(_ e: SpectrumEngine, _ l: [Float], _ r: [Float]) -> [Float] {
        l.withUnsafeBufferPointer { a in r.withUnsafeBufferPointer { b in e.analyse(left: a.baseAddress!, right: b.baseAddress!) } }
    }

    /// Display point closest to `hz`.
    private func point(_ hz: Double, _ e: SpectrumEngine) -> Int {
        (0..<SpectrumEngine.points).min { abs(log(SpectrumEngine.frequency($0, topHz: e.topHz) / hz)) <
                                          abs(log(SpectrumEngine.frequency($1, topHz: e.topHz) / hz)) }!
    }

    func testAFullScaleSineReadsZeroDBFS() {
        let e = SpectrumEngine(sampleRate: sr)
        let hz = 85 * sr / Double(N)                         // centred on bin 85 (~996 Hz)
        for amp: Float in [1, 0.1, 0.01] {
            let s = sine(hz, amp)
            let peak = analyse(e, s, s).max()!
            XCTAssertEqual(peak, 20 * log10(amp), accuracy: 0.05, "a \(amp) sine on both channels")
        }
        // off a bin centre the Hann window's scalloping costs at most about 1.4 dB
        let off = sine(1000, 1)
        XCTAssertEqual(analyse(e, off, off).max()!, 0, accuracy: 1.5)
    }

    func testOppositePhaseStereoIsNotCancelled() {
        let e = SpectrumEngine(sampleRate: sr)
        let hz = 85 * sr / Double(N)
        let l = sine(hz, 1), r = l.map { -$0 }
        // L + R would be silence; averaging the channels' powers keeps it at 0 dBFS
        XCTAssertEqual(analyse(e, l, r).max()!, 0, accuracy: 0.05)
        // one channel only: half the power, -3 dB
        XCTAssertEqual(analyse(e, l, [Float](repeating: 0, count: N)).max()!, -3.01, accuracy: 0.05)
    }

    func testSilenceSitsOnTheFloor() {
        let e = SpectrumEngine(sampleRate: sr)
        let z = [Float](repeating: 0, count: N)
        XCTAssertTrue(analyse(e, z, z).allSatisfy { $0 == SpectrumEngine.floorDB })
    }

    func testFrequencyAxisStopsAtNyquist() {
        XCTAssertEqual(SpectrumEngine(sampleRate: 48_000).topHz, 20_000)
        XCTAssertEqual(SpectrumEngine(sampleRate: 44_100).topHz, 20_000)
        XCTAssertEqual(SpectrumEngine(sampleRate: 32_000).topHz, 16_000)
        let e = SpectrumEngine(sampleRate: 32_000)
        XCTAssertEqual(SpectrumEngine.frequency(0, topHz: e.topHz), 20, accuracy: 1e-9)
        XCTAssertEqual(SpectrumEngine.frequency(SpectrumEngine.points - 1, topHz: e.topHz), 16_000, accuracy: 1e-6)
    }

    func testATonePeaksAtItsOwnFrequency() {
        let e = SpectrumEngine(sampleRate: sr)
        for hz in [60.0, 440, 5_000, 15_000] {
            let s = sine(hz, 0.5)
            let v = analyse(e, s, s)
            let top = v.indices.max { v[$0] < v[$1] }!
            XCTAssertEqual(log2(SpectrumEngine.frequency(top, topHz: e.topHz) / hz), 0, accuracy: 0.05, "\(hz) Hz")
            if hz * 4 < e.topHz { XCTAssertLessThan(v[point(hz * 4, e)], -60, "nothing two octaves up") }
        }
    }

    func testBallisticsRiseFastAndFallInAboutTwoHundredMilliseconds() {
        var v = [Float](repeating: SpectrumEngine.floorDB, count: 1)
        let dt = 1.0 / 30
        // attack: within 1 dB of a new peak in two frames
        for _ in 0..<2 { SpectrumEngine.ballistics(&v, toward: [0], dt: dt) }
        XCTAssertGreaterThan(v[0], -1)
        // release: about 63 % of the way down after 200 ms, off the plot (-72) within a second
        v = [0]
        for _ in 0..<6 { SpectrumEngine.ballistics(&v, toward: [SpectrumEngine.floorDB], dt: dt) }
        XCTAssertEqual(v[0], SpectrumEngine.floorDB * 0.632, accuracy: 4)
        for _ in 0..<24 { SpectrumEngine.ballistics(&v, toward: [SpectrumEngine.floorDB], dt: dt) }
        XCTAssertLessThan(v[0], -72)
    }
}

final class SpectrumTapTests: XCTestCase {
    private let sr = 48_000.0

    /// Runs `input` (both channels) through a DSP with the taps on, in 128-frame blocks.
    private func run(_ input: [Float], _ settings: [Param: Float], tapsOn: Bool = true) -> SharedState {
        let shared = SharedState()
        for (p, v) in settings { shared[p] = v }
        shared.spectrum.on.value = tapsOn ? 1 : 0
        let dsp = ClipDSP(sampleRate: sr, shared: shared)
        let block = 128
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let outR = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { outL.deallocate(); outR.deallocate() }
        input.withUnsafeBufferPointer { b in
            var i = 0
            while i < input.count {
                let n = min(block, input.count - i)
                dsp.process(inL: b.baseAddress! + i, inR: b.baseAddress! + i, outL: outL, outR: outR, frames: n)
                i += n
            }
        }
        return shared
    }

    /// The newest `count` frames of one ring.
    private func newest(_ ring: AtomicFloats, _ shared: SharedState, _ count: Int) -> [Float] {
        let end = shared.spectrum.written.acquire()
        return (end - count..<end).map { ring[$0 & SpectrumFeed.mask] }
    }

    func testTapsStayOffWhileTheScreenIsHidden() {
        let shared = run([Float](repeating: 0.5, count: 4096), [:], tapsOn: false)
        XCTAssertEqual(shared.spectrum.written.acquire(), 0)
    }

    func testInputTapIsAfterInputAndDriveAndOutputTapIsBeforeTheMix() {
        // 1x, so nothing is delayed; quiet enough that nothing clips
        let x = (0..<2048).map { 0.01 * Float(sin(Double($0) * 0.05)) }
        let shared = run(x, [.oversampling: 0, .inputDB: 6, .driveDB: 6, .ceilingDB: 0,
                             .mix: 30, .outputDB: -12])
        let f = shared.spectrum
        XCTAssertEqual(f.written.acquire(), 2048)
        let g = dbToGain(12)
        for i in stride(from: 1500, to: 2048, by: 37) {
            XCTAssertEqual(f.inL[i], x[i] * g, accuracy: 1e-4, "input tap = input x Input x Drive")
            // wet branch at 1x below the ceiling is the same signal (Mix 30 % and Output -12 dB
            // are applied after the tap, so they don't show)
            XCTAssertEqual(f.outL[i], x[i] * g, accuracy: 1e-4, "output tap is before Wet / Dry and Output")
        }
    }

    func testOversampledTapsLineUp() {
        // broadband noise below the clipper: the output tap is the input through the
        // oversampling filters, so the two copies should match best with no offset
        var seed: UInt32 = 1
        let x: [Float] = (0..<16384).map { _ in
            seed = seed &* 1664525 &+ 1013904223
            return 0.05 * Float(Int32(bitPattern: seed)) / Float(Int32.max)
        }
        for os: Float in [1, 2] {
            let shared = run(x, [.oversampling: os, .ceilingDB: 0])
            let a = newest(shared.spectrum.inL, shared, 8192), b = newest(shared.spectrum.outL, shared, 8192)
            func corr(_ lag: Int) -> Float {
                var s: Float = 0
                for i in 16..<(a.count - 16) { s += a[i] * b[i + lag] }
                return s
            }
            let best = (-8...8).max { corr($0) < corr($1) }!
            XCTAssertLessThanOrEqual(abs(best), 1, "oversampling \(os): input and output copies line up")
        }
    }

    func testClippingShowsAsHarmonicsInTheOutputOnly() {
        let hz = 85 * sr / Double(SpectrumEngine.fftSize)
        let x = (0..<16384).map { 0.5 * Float(sin(2 * Double.pi * hz * Double($0) / sr)) }
        let shared = run(x, [.oversampling: 1, .driveDB: 12, .ceilingDB: -12, .clipMode: 0])
        let e = SpectrumEngine(sampleRate: sr)
        let N = SpectrumEngine.fftSize
        let inL = newest(shared.spectrum.inL, shared, N), inR = newest(shared.spectrum.inR, shared, N)
        let outL = newest(shared.spectrum.outL, shared, N), outR = newest(shared.spectrum.outR, shared, N)
        func an(_ l: [Float], _ r: [Float]) -> [Float] {
            l.withUnsafeBufferPointer { a in r.withUnsafeBufferPointer { b in e.analyse(left: a.baseAddress!, right: b.baseAddress!) } }
        }
        let vin = an(inL, inR), vout = an(outL, outR)
        let third = (0..<SpectrumEngine.points).min { abs(log(SpectrumEngine.frequency($0, topHz: e.topHz) / (3 * hz))) <
                                                      abs(log(SpectrumEngine.frequency($1, topHz: e.topHz) / (3 * hz))) }!
        XCTAssertLessThan(vin[third], -80, "a pure sine into the clipper has no third harmonic")
        XCTAssertGreaterThan(vout[third], -40, "hard clipping adds a strong third harmonic")
        // the input (0.5 x 12 dB of Drive) reads about +6 dBFS: over the plot, never clamped
        XCTAssertGreaterThan(vin.max()!, 5)
        // the output's spectrum is not held to the ceiling line: its harmonics are measured,
        // and the fundamental of a squared-off wave sits above the -12 dBFS ceiling
        XCTAssertGreaterThan(vout.max()!, -12)
    }
}

final class SpectrumAnalyzerTests: XCTestCase {
    func testAnalyserFollowsAudioAndHoldsWhenItStops() {
        let shared = SharedState()
        let dsp = ClipDSP(sampleRate: 48_000, shared: shared)
        let analyzer = SpectrumAnalyzer(shared: shared)
        analyzer.start()
        defer { analyzer.stop() }
        let deadline = Date().addingTimeInterval(2)
        while shared.spectrum.on.value == 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(shared.spectrum.on.value, 1)

        let block = 128
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: block * 2)
        defer { buf.deallocate(); out.deallocate() }
        var phase = 0.0
        // about half a second of a 1 kHz sine, in real time-ish
        for _ in 0..<190 {
            for i in 0..<block { buf[i] = 0.5 * Float(sin(phase)); phase += 2 * Double.pi * 1000 / 48_000 }
            dsp.process(inL: buf, inR: buf, outL: out, outR: out + block, frames: block)
            Thread.sleep(forTimeInterval: 0.0027)
        }
        Thread.sleep(forTimeInterval: 0.1)
        let playing = analyzer.latest
        XCTAssertEqual(playing.input.count, SpectrumEngine.points)
        XCTAssertTrue(playing.live)
        XCTAssertEqual(playing.input.max()!, -6, accuracy: 2, "the 0.5 sine's peak, through the ballistics")

        // the source stops: the frame is held, not decayed
        Thread.sleep(forTimeInterval: 0.5)
        let held = analyzer.latest
        XCTAssertFalse(held.live)
        XCTAssertEqual(held.input.max()!, playing.input.max()!, accuracy: 0.5)

        analyzer.stop()
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(shared.spectrum.on.value, 0, "hidden: the audio thread stops copying")
    }
}
