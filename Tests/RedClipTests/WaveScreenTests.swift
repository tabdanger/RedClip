import XCTest

// The WAVEFORM screen: what the two taps carry (the original input, the final output), that the layers line up in time, the MAX CLIP
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

    func testTicksCarryTheOriginalInputAndTheFinalOutput() {
        let (shared, dsp) = make([.oversampling: 0, .inputDB: 6, .driveDB: 6, .ceilingDB: 0, .mix: 30, .outputDB: -12])
        let x = (0..<(64 * 200)).map { 0.01 * Float(sin(Double($0) * 0.3)) }
        run(dsp, x, block: 128)
        let f = shared.wave
        XCTAssertEqual(f.written.acquire(), 200)
        let last = 199 & WaveFeed.mask
        XCTAssertEqual(f.frames[last], WaveFeed.tickFrames)
        XCTAssertEqual(f.inPeak[last], 0.01, accuracy: 0.0005, "grey = the original audio, before Input and Drive")
        // white = what you hear: 30 % wet (after Input and Drive) + 70 % dry (after Input), then Output
        let heard = 0.01 * (0.3 * dbToGain(12) + 0.7 * dbToGain(6)) * dbToGain(-12)
        XCTAssertEqual(f.outPeak[last], heard, accuracy: 0.0005, "white = the final output, after Wet / Dry and Output")
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

    func testClipClockIsTheLoudestOriginalSampleAndWhereItWas() {
        // Input and Drive come after the measurement: the figure is the source's own level
        let (shared, dsp) = make([.oversampling: 0, .ceilingDB: -6, .inputDB: 6, .driveDB: 9])
        var x = [Float](repeating: 0.1, count: 2048)
        x[500] = 0.7
        x[1000] = -0.9
        dsp.timelineFrame = 48_000
        dsp.timelineClock = SongClock.file.rawValue
        run(dsp, x)
        let m = shared.clipMax()!
        XCTAssertEqual(m.db, gainToDB(0.9), accuracy: 0.01)
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

    func testKnobsNeverRestartTheClipClockOnlyTheResetDoes() {
        let (shared, dsp) = make([.oversampling: 0, .ceilingDB: -6, .clipMode: 0])
        var x = [Float](repeating: 0, count: 1024)
        x[100] = 0.8
        run(dsp, x)
        XCTAssertEqual(shared.clipMax()?.frame, 100)
        let silence = [Float](repeating: 0, count: 256)

        for (p, v) in [(Param.inputDB, 6), (.driveDB, 9), (.ceilingDB, -3), (.clipMode, 1), (.oversampling, 2),
                       (.gold, 100), (.goldMode, 1), (.outputDB, -3), (.mix, 50)] as [(Param, Float)] {
            shared[p] = v
            run(dsp, silence)
            XCTAssertEqual(shared.clipMax()?.frame, 100, "\(p) must not restart it")
            XCTAssertEqual(shared.clipMaxDB.value, gainToDB(0.8), accuracy: 0.01)
        }

        shared.resetClipMax()
        XCTAssertEqual(shared.clipMax()?.frame, -1)
        run(dsp, silence)
        XCTAssertEqual(shared.clipMax()?.frame, -1)
    }

    func testTheAppsWholeFilePeakIsKeptAndMarked() {
        var x = [Float](repeating: 0.1, count: 64 * 40)
        x[64 * 30 + 5] = -0.95                      // the file's loudest sample, not yet played
        let peak = x.withUnsafeBufferPointer { SharedState.filePeak(left: $0.baseAddress!, right: $0.baseAddress!, frames: x.count) }
        XCTAssertEqual(peak.frame, 64 * 30 + 5)

        let (shared, dsp) = make([.oversampling: 1, .driveDB: 12])
        shared.setFileClipMax(peak: peak.peak, frame: peak.frame)
        let set = shared.clipMax()!
        XCTAssertEqual(set.db, gainToDB(0.95), accuracy: 0.01)
        XCTAssertEqual(set.clock, .file)

        // playing the start of the file (quieter) leaves it alone
        dsp.timelineFrame = 0
        run(dsp, Array(x[0..<(64 * 20)]))
        XCTAssertEqual(shared.clipMax()?.frame, 64 * 30 + 5)
        XCTAssertEqual(shared.clipMax()?.serial, set.serial)

        // and when playback reaches it, its tick gets the marker
        dsp.timelineFrame = 64 * 20
        run(dsp, Array(x[(64 * 20)...]))
        XCTAssertEqual((0..<40).filter { shared.wave.mark[$0] == set.serial }, [30])
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

final class ScrubTests: XCTestCase {
    func testLoudestMomentsComeLoudestFirstAndSpacedApart() {
        let sr = 1000.0
        var x = [Float](repeating: 0.1, count: 10_000)
        x[2000] = 0.5
        x[2300] = 0.9                               // the file's peak
        x[2600] = 0.8                               // too close to it to count separately
        x[7000] = -0.7
        let pts = x.withUnsafeBufferPointer {
            ClipPoint.loudest(left: $0.baseAddress!, right: $0.baseAddress!, frames: x.count, sampleRate: sr, count: 3)
        }
        XCTAssertEqual(pts.map(\.frame), [2300, 7000, 0])
        XCTAssertEqual(pts.map(\.rank), [0, 1, 2])
        XCTAssertEqual(pts[0].fraction, 0.23, accuracy: 1e-9)
        XCTAssertEqual(pts[0].db, gainToDB(0.9), accuracy: 0.01)
        let peak = x.withUnsafeBufferPointer { SharedState.filePeak(left: $0.baseAddress!, right: $0.baseAddress!, frames: x.count) }
        XCTAssertEqual(pts[0].frame, peak.frame, "the tallest mark is the CLIP CLOCK sample")
    }

    func testEmptyFileHasNoMarks() {
        let x: [Float] = [0]
        let pts = x.withUnsafeBufferPointer {
            ClipPoint.loudest(left: $0.baseAddress!, right: $0.baseAddress!, frames: 0, sampleRate: 48_000)
        }
        XCTAssertTrue(pts.isEmpty)
    }

    func testFingerFurtherFromTheBarScrubsFiner() {
        XCTAssertEqual(ScrubMath.speed(distance: 10), 1)
        XCTAssertEqual(ScrubMath.speed(distance: 60), 0.5)
        XCTAssertEqual(ScrubMath.speed(distance: 100), 0.25)
        XCTAssertEqual(ScrubMath.speed(distance: 300), 0.1)
        XCTAssertEqual(ScrubMath.speedName(1), "")
        XCTAssertEqual(ScrubMath.speedName(0.1), "FINE")
    }

    func testTheDotSnapsOntoANearbyMarkOnly() {
        let pts = [ClipPoint(frame: 500, fraction: 0.5, db: -1, rank: 0)]
        XCTAssertEqual(ScrubMath.snap(0.505, to: pts, reach: 0.01), 0.5)
        XCTAssertEqual(ScrubMath.snap(0.52, to: pts, reach: 0.01), 0.52)
        XCTAssertEqual(ScrubMath.snap(0.3, to: [], reach: 0.01), 0.3)
    }
}
