import XCTest

// The WAVEFORM screen: what the two taps carry, that the layers line up in time, the MAX CLIP
// position and its marker, when MAX CLIP starts over, and the reduction to display columns.

final class WaveTapTests: XCTestCase {
    private let sr = 48_000.0

    /// Runs `x` (both channels) through `dsp` as one call (or 128-frame blocks).
    private func run(_ dsp: ClipDSP, _ x: [Float], block: Int? = nil) {
        let n = x.count
        let out = UnsafeMutablePointer<Float>.allocate(capacity: 2 * n)
        defer { out.deallocate() }
        x.withUnsafeBufferPointer { b in
            let size = block ?? n
            var i = 0
            while i < n {
                let m = min(size, n - i)
                dsp.process(inL: b.baseAddress! + i, inR: b.baseAddress! + i, outL: out + i, outR: out + n + i, frames: m)
                i += m
            }
        }
    }

    private func make(_ settings: [Param: Float], waveOn: Bool = true) -> (SharedState, ClipDSP) {
        let shared = SharedState()
        for (p, v) in settings { shared[p] = v }
        shared.wave.on.value = waveOn ? 1 : 0
        return (shared, ClipDSP(sampleRate: sr, shared: shared))
    }

    func testNothingIsGatheredWhileTheScreenIsHidden() {
        let (shared, dsp) = make([:], waveOn: false)
        run(dsp, [Float](repeating: 0.5, count: 4096))
        XCTAssertEqual(shared.wave.written.acquire(), 0)
    }

    func testTicksCarryInputAfterDriveAndOutputBeforeTheMix() {
        let (shared, dsp) = make([.oversampling: 0, .inputDB: 6, .driveDB: 6, .ceilingDB: 0, .mix: 30, .outputDB: -12])
        let x = (0..<(64 * 200)).map { 0.01 * Float(sin(Double($0) * 0.3)) }
        run(dsp, x, block: 128)
        let f = shared.wave
        XCTAssertEqual(f.written.acquire(), 200)
        let last = 199 & WaveFeed.mask
        let g = dbToGain(12)
        XCTAssertEqual(f.frames[last], WaveFeed.tickFrames)
        XCTAssertEqual(f.inPeak[last], 0.01 * g, accuracy: 0.002, "input tap = input x Input x Drive")
        XCTAssertEqual(f.outPeak[last], 0.01 * g, accuracy: 0.002, "output tap is before Wet / Dry and Output")
        XCTAssertEqual(f.clip[last], 0, accuracy: 1e-6, "nothing clipped")
    }

    func testInputAndOutputLineUpWhenOversampled() {
        for os: Float in [1, 2] {
            let (shared, dsp) = make([.oversampling: os, .ceilingDB: 0])
            // a step three frames before the end of tick 50: the output only leaves the
            // oversampling filters in tick 51, and the input copy has to wait for it
            var x = [Float](repeating: 0, count: 64 * 60)
            for i in (64 * 50 + 61)..<x.count { x[i] = 0.1 }
            run(dsp, x, block: 128)
            let f = shared.wave
            let firstIn = (0..<60).first { f.inPeak[$0] > 0.05 }
            let firstOut = (0..<60).first { f.outPeak[$0] > 0.05 }
            XCTAssertEqual(firstIn, 51, "oversampling \(os)")
            XCTAssertEqual(firstOut, 51, "oversampling \(os)")
        }
    }

    func testMaxClipIsTheHardestClippedSampleAndWhereItWas() {
        let (shared, dsp) = make([.oversampling: 0, .ceilingDB: -6, .clipMode: 0])
        var x = [Float](repeating: 0.1, count: 2048)
        x[500] = 0.7
        x[1000] = 1.0
        dsp.timelineFrame = 48_000
        dsp.timelineClock = SongClock.file.rawValue
        run(dsp, x)
        let m = shared.clipMax()!
        XCTAssertEqual(m.db, gainToDB(1.0 / dbToGain(-6)), accuracy: 0.01)
        XCTAssertEqual(m.frame, 48_000 + 1000)
        XCTAssertEqual(m.clock, .file)
    }

    func testWithoutATimelineMaxClipUsesTheAnalysisClock() {
        let (shared, dsp) = make([.oversampling: 0, .ceilingDB: -6, .clipMode: 0])
        var x = [Float](repeating: 0, count: 4096)
        x[3000] = 1.0
        dsp.timelineFrame = -1                      // a DAW with its transport stopped
        run(dsp, x, block: 128)
        let m = shared.clipMax()!
        XCTAssertEqual(m.frame, 3000)
        XCTAssertEqual(m.clock, .relative)
    }

    func testMaxClipStartsOverWhenTheClipperIsSetDifferently() {
        let (shared, dsp) = make([.oversampling: 0, .ceilingDB: -6, .clipMode: 0])
        var x = [Float](repeating: 0, count: 1024)
        x[100] = 1.0
        run(dsp, x)
        XCTAssertGreaterThan(shared.clipMaxDB.value, 5)
        let silence = [Float](repeating: 0, count: 256)

        // Output and Wet / Dry come after the clipper: the figure stays
        shared[.outputDB] = -3
        shared[.mix] = 50
        run(dsp, silence)
        XCTAssertGreaterThan(shared.clipMaxDB.value, 5)

        // Drive changes what reaches it: the old figure is not shown as current
        shared[.driveDB] = 3
        run(dsp, silence)
        XCTAssertEqual(shared.clipMaxDB.value, 0)
        XCTAssertEqual(shared.clipMax()?.frame, -1)

        // and the reset button
        run(dsp, x)
        XCTAssertGreaterThan(shared.clipMaxDB.value, 5)
        shared.resetClipMax()
        XCTAssertEqual(shared.clipMaxDB.value, 0)
        run(dsp, silence)
        XCTAssertEqual(shared.clipMax()?.frame, -1)
    }

    func testTheMaxMarkerLandsOnTheTickTheClipCameOutIn() {
        let (shared, dsp) = make([.oversampling: 1, .ceilingDB: -6, .clipMode: 0])
        var x = [Float](repeating: 0, count: 64 * 40)
        x[64 * 20 + 10] = 1.0
        dsp.timelineFrame = 0
        run(dsp, x)
        let m = shared.clipMax()!
        XCTAssertLessThanOrEqual(abs(m.frame - (64 * 20 + 10)), 2, "the source position of the clipped sample")
        let marked = (0..<40).filter { shared.wave.mark[$0] == m.serial }
        XCTAssertEqual(marked, [20])
        XCTAssertEqual(shared.wave.frame[20], 64 * 20 - 4, "tick 20's output started 4 frames back in the file (2x)")
    }
}

final class WaveColumnTests: XCTestCase {
    private func ticks(_ n: Int, _ fill: (Int, inout WaveTicks) -> Void) -> WaveTicks {
        var t = WaveTicks(written: n, count: n)
        for j in 0..<n { t.frames[j] = WaveFeed.tickFrames; fill(j, &t) }
        return t
    }

    func testAOneTickTransientSurvivesTheReduction() {
        let t = ticks(1000) { j, t in t.inPeak[j] = j == 537 ? 1 : 0.01; t.outPeak[j] = 0.01 }
        let cols = WaveColumns.make(t, count: 100, window: 1000)
        XCTAssertEqual(cols.map(\.inPeak).max(), 1)
        XCTAssertEqual(cols[53].inPeak, 1)
    }

    func testAShortHistoryFillsFromTheRight() {
        let t = ticks(10) { j, t in t.inPeak[j] = 0.5; t.frame[j] = j * 64 }
        let cols = WaveColumns.make(t, count: 100, window: 100)
        XCTAssertTrue(cols[0..<90].allSatisfy { !$0.has })
        XCTAssertTrue(cols[90..<100].allSatisfy { $0.has })
        XCTAssertEqual(cols[90].frame, 0)
    }

    func testPeakAndRMSOfAFullScaleSine() {
        // a full-scale sine: peak 1, mean square 1/2 on both channels
        let t = ticks(100) { j, t in t.outPeak[j] = 1; t.outSquares[j] = Float(WaveFeed.tickFrames) * 0.5 }
        let l = WaveColumns.peakAndRMS(t)
        XCTAssertEqual(l.peak, 0, accuracy: 1e-5)
        XCTAssertEqual(l.rms, -3.01, accuracy: 0.01)
    }

    func testScaleMarksForEveryZoom() {
        XCTAssertEqual(PlateWaveScreen.scaleMarks(.full), [6, 0, -6, -12, -18, -24, -30, -36])
        XCTAssertEqual(PlateWaveScreen.scaleMarks(.zoom1), [4, 0, -6, -12, -18, -24])
        XCTAssertEqual(PlateWaveScreen.scaleMarks(.zoom2), [2, 0, -3, -6, -9, -12])
    }

    func testCeilingMapsOntoEachScale() {
        let r = PlateWaveScreen.Rows(W: 932)
        for z in MeterZoom.allCases {
            XCTAssertEqual(PlateWaveScreen.y(z.topDB, r, z), r.top, accuracy: 1e-6)
            XCTAssertEqual(PlateWaveScreen.y(z.floorDB, r, z), r.bottom, accuracy: 1e-6)
            // -9.6 dBFS sits (top + 9.6) / (top - floor) of the way down
            let expected = r.top + (r.bottom - r.top) * CGFloat((z.topDB + 9.6) / (z.topDB - z.floorDB))
            XCTAssertEqual(PlateWaveScreen.y(-9.6, r, z), expected, accuracy: 1e-4)
        }
    }

    func testTimestamps() {
        XCTAssertEqual(WaveTime.tenths(44.25), "0:44.2")
        XCTAssertEqual(WaveTime.tenths(127), "2:07.0")
        XCTAssertEqual(WaveTime.dBFS(-9.6), "\u{2212}9.6")
    }
}
