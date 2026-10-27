import XCTest

// The SONG screen's data: the CLIP measurement at the clipper, the whole-file analysis the app
// draws from, the plug-in's capture of what the host plays, and the timeline arithmetic.

final class ClipMeasureTests: XCTestCase {
    private let sr = 48_000.0

    /// One block of `values` through a fresh DSP at 1x (each value reaches the clipper as fed);
    /// returns the CLIP reading for that block.
    private func clip(_ values: [Float], _ settings: [Param: Float]) -> (db: Float, shared: SharedState) {
        let shared = SharedState()
        shared[.oversampling] = 0
        for (p, v) in settings { shared[p] = v }
        let dsp = ClipDSP(sampleRate: sr, shared: shared)
        let n = values.count
        let inL = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let outR = UnsafeMutablePointer<Float>.allocate(capacity: n)
        defer { inL.deallocate(); outL.deallocate(); outR.deallocate() }
        for i in 0..<n { inL[i] = values[i] }
        dsp.process(inL: inL, inR: inL, outL: outL, outR: outR, frames: n)
        return (shared.meters.exchange(Meter.reductionDB.rawValue, 0), shared)
    }

    func testClipIsWhatTheSelectedCurveTakesOff() {
        let ceiling: Float = -6, c = dbToGain(ceiling)
        for mode in 0...2 {
            let knee = Curves.knee(mode)
            for x: Float in [c * 0.8, c * 0.95, c, c * 1.3, c * 3] {
                let expected = 20 * log10(x / Curves.clip(x, ceiling: c, knee: knee))
                let got = clip([0, x, 0, -x * 0.5], [.ceilingDB: ceiling, .clipMode: Float(mode)]).db
                XCTAssertEqual(got, expected, accuracy: 0.01, "mode \(mode), input \(x)")
            }
        }
    }

    func testSoftKneesCountReductionUnderTheCeiling() {
        let c = dbToGain(-6)
        // Classic bends in from 0.65 of the ceiling, so a peak just under the ceiling is already cut
        XCTAssertGreaterThan(clip([c * 0.98], [.ceilingDB: -6, .clipMode: 1]).db, 0.3)
        // under every curve's threshold nothing is cut at all
        for mode in 0...2 { XCTAssertEqual(clip([c * 0.6, -c * 0.6], [.ceilingDB: -6, .clipMode: Float(mode)]).db, 0) }
    }

    func testWetDryAndOutputDontChangeTheMeasurement() {
        let x: [Float] = [0.2, 1.4, -1.1, 0.7]
        let plain = clip(x, [.ceilingDB: -3]).db
        XCTAssertGreaterThan(plain, 1)
        XCTAssertEqual(clip(x, [.ceilingDB: -3, .outputDB: 12]).db, plain, accuracy: 1e-5)
        XCTAssertEqual(clip(x, [.ceilingDB: -3, .mix: 0]).db, plain, accuracy: 1e-5)
        XCTAssertEqual(clip(x, [.ceilingDB: -3, .mixUnlink: 1, .dry: 100, .wet: 20]).db, plain, accuracy: 1e-5)
        XCTAssertEqual(clip(x, [.ceilingDB: -3, .broil: 100, .alchemy: 100]).db, plain, accuracy: 1e-5)
    }

    func testSilenceAndBadInputStayFinite() {
        XCTAssertEqual(clip([Float](repeating: 0, count: 256), [:]).db, 0)
        let bad = clip([.nan, .infinity, -.infinity, 0.5], [:])
        XCTAssertTrue(bad.db.isFinite)
        XCTAssertTrue(bad.shared.clipMaxDB.value.isFinite)
    }

    func testMaxClipHoldsUntilReset() {
        let shared = SharedState()
        shared[.oversampling] = 0
        shared[.ceilingDB] = 0
        shared[.clipMode] = 0
        let dsp = ClipDSP(sampleRate: sr, shared: shared)
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        let out = UnsafeMutablePointer<Float>.allocate(capacity: 8)
        defer { buf.deallocate(); out.deallocate() }
        func feed(_ v: Float) {
            for i in 0..<4 { buf[i] = i == 1 ? v : 0 }
            dsp.process(inL: buf, inR: buf, outL: out, outR: out + 4, frames: 4)
        }
        feed(dbToGain(6))
        XCTAssertEqual(shared.clipMaxDB.value, 6, accuracy: 0.05)
        feed(dbToGain(2))
        XCTAssertEqual(shared.clipMaxDB.value, 6, accuracy: 0.05, "a smaller clip doesn't lower the max")
        shared.resetClipMax()
        XCTAssertEqual(shared.clipMaxDB.value, 0)
        feed(dbToGain(2))
        XCTAssertEqual(shared.clipMaxDB.value, 2, accuracy: 0.05)
    }
}

final class SongOverviewTests: XCTestCase {
    private let sr = 48_000.0

    /// `seconds` of silence with a hot 200 Hz burst from 2 s to 3 s, in a buffer the test owns.
    private final class Song {
        let left: UnsafeMutablePointer<Float>
        let frames: Int
        init(seconds: Double, sr: Double, burst: Float) {
            frames = Int(seconds * sr)
            left = .allocate(capacity: frames)
            for i in 0..<frames {
                let t = Double(i) / sr
                left[i] = t >= 2 && t < 3 ? burst * Float(sin(2 * .pi * 200 * t)) : 0
            }
        }
        deinit { left.deallocate() }
        func audio(_ sr: Double) -> SongAudio {
            SongAudio(left: UnsafePointer(left), right: UnsafePointer(left), frames: frames, sampleRate: sr, owner: self)
        }
    }

    private func settings(_ s: [Param: Float]) -> [Float] {
        let state = SharedState(captureCapacity: 64)
        for (p, v) in s { state[p] = v }
        return Param.allCases.map { state[$0] }
    }

    private func stamp(_ values: [Float]) -> Int {
        let state = SharedState(captureCapacity: 64)
        for (i, v) in values.enumerated() { state.params[i] = v }
        return SongStamp.of(state.params)
    }

    func testPreviewShowsTheClippingWhereItHappens() throws {
        let song = Song(seconds: 5, sr: sr, burst: 0.9)
        let set = settings([.ceilingDB: -6, .oversampling: 1])
        let o = try XCTUnwrap(SongAnalyzer.preview(song.audio(sr), settings: set, stop: { false }))
        let cols = o.columns(100, timeline: song.frames, current: stamp(set))   // 50 ms per column
        let c = dbToGain(-6)
        XCTAssertFalse(cols.state.contains(.unknown), "the whole file is analysed")
        XCTAssertTrue(cols.state.allSatisfy { $0 == .exact }, "drawn from the exact pass")
        for i in 0..<100 {
            let t = Double(i) * 0.05
            if t < 1.9 || t > 3.1 {
                XCTAssertLessThan(cols.preHi[i], 1e-3, "silence at \(t) s")
                XCTAssertLessThan(cols.outHi[i], 1e-3, "silence at \(t) s")
            } else if t > 2.1 && t < 2.9 {
                XCTAssertEqual(cols.preHi[i], 0.9, accuracy: 0.03, "the clipper's input at \(t) s")
                XCTAssertLessThanOrEqual(cols.postHi[i], c * 1.001, "the clipper's output stays under the ceiling")
                XCTAssertLessThan(cols.postHi[i], cols.preHi[i] - 0.2, "clipped at \(t) s")
                XCTAssertLessThan(cols.preLo[i], -0.85)
            }
        }
    }

    func testPreviewLeavesTheLiveEngineAlone() throws {
        let live = SharedState()
        live[.driveDB] = 3
        let before = Param.allCases.map { live[$0] }
        let ring = live.ringTotal.acquire(), written = live.capture.written.acquire()
        let song = Song(seconds: 4, sr: sr, burst: 0.9)
        _ = SongAnalyzer.preview(song.audio(sr), settings: Param.allCases.map { live[$0] }, stop: { false })
        XCTAssertEqual(Param.allCases.map { live[$0] }, before)
        XCTAssertEqual(live.ringTotal.acquire(), ring)
        XCTAssertEqual(live.capture.written.acquire(), written)
    }

    func testANewerJobStopsAnOlderOne() {
        let song = Song(seconds: 4, sr: sr, burst: 0.9)
        var calls = 0
        let made = SongAnalyzer.preview(song.audio(sr), settings: settings([:]), stop: { calls += 1; return calls > 3 })
        XCTAssertNil(made)
        XCTAssertNil(SongAnalyzer.source(song.audio(sr), stop: { true }))
    }

    private func model(_ values: [Float]) -> SongModel {
        let state = SharedState(captureCapacity: 64)
        for (i, v) in values.enumerated() { state.params[i] = v }
        return SongModel(state.params)
    }

    func testAKnobMoveRedrawsLiveWithTheNewSettings() throws {
        let song = Song(seconds: 4, sr: sr, burst: 0.9)
        let a = settings([.ceilingDB: -6]), b = settings([.ceilingDB: -12, .outputDB: -3])
        XCTAssertNotEqual(stamp(a), stamp(b))
        XCTAssertEqual(stamp(a), stamp(settings([.ceilingDB: -6, .link: 1])), "Link alone doesn't change the picture")
        let o = try XCTUnwrap(SongAnalyzer.preview(song.audio(sr), settings: a, stop: { false }))
        // the knobs moved after the exact pass: every column follows them through the model
        let cols = o.columns(80, timeline: song.frames, current: stamp(b), model: model(b))
        XCTAssertTrue(cols.state.allSatisfy { $0 == .live })
        let c = dbToGain(-12)
        for i in 0..<80 where Double(i) * 0.05 > 2.1 && Double(i) * 0.05 < 2.9 {
            XCTAssertEqual(cols.preHi[i], 0.9, accuracy: 0.01)
            XCTAssertLessThanOrEqual(cols.postHi[i], c * 1.0001, "the new ceiling")
            XCTAssertEqual(cols.outHi[i], cols.postHi[i] * dbToGain(-3), accuracy: 1e-4, "the new Output")
        }
    }

    func testTheLiveModelMatchesTheExactPass() throws {
        let song = Song(seconds: 4, sr: sr, burst: 0.9)
        for extra: [Param: Float] in [[:], [.clipMode: 0], [.clipMode: 1, .gold: 60], [.mixUnlink: 1, .dry: 40, .wet: 100],
                                      [.broil: 50, .outputDB: 2]] {
            var s: [Param: Float] = [.ceilingDB: -9, .oversampling: 0]
            for (k, v) in extra { s[k] = v }
            let set = settings(s)
            let o = try XCTUnwrap(SongAnalyzer.preview(song.audio(sr), settings: set, stop: { false }))
            let src = try XCTUnwrap(SongAnalyzer.source(song.audio(sr), stop: { false }))
            o.setSource(hi: src.hi, lo: src.lo)
            let exact = o.columns(40, timeline: song.frames, current: stamp(set))
            let live = o.columns(40, timeline: song.frames, current: SongStamp.mixed, model: model(set))
            for i in 0..<40 where Double(i) * 0.1 > 2.1 && Double(i) * 0.1 < 2.9 {
                XCTAssertEqual(live.preHi[i], exact.preHi[i], accuracy: 0.01, "\(extra) into the clipper")
                XCTAssertEqual(live.postHi[i], exact.postHi[i], accuracy: 0.01, "\(extra) out of the clipper")
                XCTAssertEqual(live.outHi[i], exact.outHi[i], accuracy: 0.02, "\(extra) output")
            }
        }
    }

    func testModelStages() {
        let base = settings([.ceilingDB: -6])
        let c = dbToGain(-6)
        let m = model(base)
        XCTAssertEqual(m.layers(0.1).post, 0.1, accuracy: 1e-6, "quiet material untouched")
        XCTAssertEqual(m.layers(2).post, Curves.clip(2, ceiling: c, knee: Curves.knee(2)), accuracy: 1e-6)
        XCTAssertEqual(m.layers(-2).out, -m.layers(2).out, accuracy: 1e-6)
        XCTAssertEqual(model(settings([.ceilingDB: -6, .bypass: 1])).layers(2).out, 2, "bypass is the input")
        XCTAssertEqual(model(settings([.ceilingDB: -6, .driveDB: 6])).layers(0.3).pre, 0.3 * dbToGain(6), accuracy: 1e-5)
        XCTAssertEqual(m.layers(.nan).out, 0)
    }

    func testSourceOverviewKeepsShortPeaks() throws {
        let song = Song(seconds: 6, sr: sr, burst: 0)
        song.left[Int(4.2 * sr)] = 0.75               // one-sample transient
        song.left[Int(1.1 * sr)] = -0.6
        let src = try XCTUnwrap(SongAnalyzer.source(song.audio(sr), stop: { false }))
        XCTAssertEqual(src.hi.max() ?? 0, 0.75)
        XCTAssertEqual(src.lo.min() ?? 0, -0.6)
        let o = SongOverview(totalFrames: song.frames, sampleRate: sr)
        o.setSource(hi: src.hi, lo: src.lo)
        let cols = o.columns(300, timeline: song.frames, current: 1)       // 20 ms columns
        XCTAssertEqual(cols.srcHi.max() ?? 0, 0.75)
        XCTAssertEqual(cols.srcLo.min() ?? 0, -0.6)
        XCTAssertTrue(cols.state.allSatisfy { $0 == .unknown }, "no processed data yet")
    }

    private func record(_ frame: Int, _ frames: Int = 64, stamp: Int = 5, clipDelay: Int = 0, outDelay: Int = 0,
                        pre: Float = 0.5, post: Float = 0.4, out: Float = 0.3) -> CaptureRecord {
        CaptureRecord(frame: frame, frames: frames, clipDelay: clipDelay, outDelay: outDelay, stamp: stamp,
                      rawHi: pre / 2, rawLo: -pre / 2, preHi: pre, postHi: post, preLo: -pre, postLo: -post, outHi: out, outLo: -out, reductionDB: 1)
    }

    func testLayersLandWhereTheirAudioCameFrom() {
        let o = SongOverview(totalFrames: 4096, sampleRate: sr)          // one frame per bin
        XCTAssertEqual(o.framesPerBin, 1)
        o.add(record(1000, 1, clipDelay: 2, outDelay: 5))
        let cols = o.columns(4096, timeline: 4096, current: 5)
        XCTAssertEqual(cols.preHi[998], 0.5, "the clip stage runs 2 frames behind")
        XCTAssertEqual(cols.outHi[995], 0.3, "the output 5 frames behind")
        XCTAssertEqual(cols.preHi[1000], 0)
    }

    func testUnknownLengthGrowsKeepsPeaksAndLeavesGapsUnknown() {
        let o = SongOverview(totalFrames: 0, sampleRate: sr)
        let first = o.extent
        o.add(record(0, pre: 0.9))
        o.add(record(first * 3 + 100, pre: 0.7))                       // far past the end: grows twice
        XCTAssertGreaterThanOrEqual(o.extent, first * 3 + 164)
        XCTAssertEqual(o.capturedEnd, first * 3 + 164)
        let cols = o.columns(64, timeline: o.extent, current: 5)
        XCTAssertEqual(cols.preHi[0], 0.9)
        XCTAssertEqual(cols.preHi.max() ?? 0, 0.9)
        XCTAssertTrue(cols.preHi.contains(0.7))
        XCTAssertTrue(cols.state.contains(.unknown), "nothing invented between the two")
        XCTAssertEqual(cols.state.filter { $0 == .exact }.count, 2)
    }

    func testNewSettingsReplaceOldAudioInTheirBins() {
        let o = SongOverview(totalFrames: 48_000, sampleRate: sr)
        o.add(record(0, stamp: 5, pre: 0.9))
        o.add(record(0, stamp: 7, pre: 0.4))
        let cols = o.columns(10, timeline: 48_000, current: 7)
        XCTAssertEqual(cols.preHi[0], 0.4)
        XCTAssertEqual(cols.state[0], .exact)
    }

    func testRingReaderDropsWhatItFellBehindOn() {
        let ring = CaptureRing(capacity: 64)
        for i in 0..<200 {
            ring.push(frame: i * 64, frames: 64, delays: 0, stamp: 3, rawHi: 0, rawLo: 0, preHi: 0, postHi: 0, preLo: 0, postLo: 0,
                      outHi: 0, outLo: 0, reductionDB: 0)
        }
        var cursor = 0
        var frames: [Int] = []
        let lost = ring.drain(&cursor) { frames.append($0.frame) }
        XCTAssertEqual(cursor, 200)
        XCTAssertEqual(lost + frames.count, 200)
        XCTAssertEqual(frames.last, 199 * 64)
        XCTAssertEqual(frames, Array((200 - frames.count)..<200).map { $0 * 64 }, "the newest, in order")
        let again = ring.drain(&cursor) { _ in XCTFail("nothing new") }
        XCTAssertEqual(again, 0)
    }

    func testRulerAndTimeText() {
        XCTAssertEqual(SongTime.text(222), "3:42")
        XCTAssertEqual(SongTime.text(3725), "1:02:05")
        XCTAssertEqual(SongTime.text(.nan), "-:--")
        // iPhone glass (~394 units of waveform): a label a minute; iPad (~904): every 30 s
        XCTAssertEqual(SongTime.rulerStep(duration: 222, width: 394, minGap: 62), 60)
        XCTAssertEqual(SongTime.rulerStep(duration: 222, width: 904, minGap: 62), 30)
        XCTAssertEqual(SongTime.roundedLength(100), 120)
        XCTAssertEqual(SongTime.roundedLength(0), 30)
    }
}

/// The plug-in: what the host plays is captured onto the timeline as it arrives.
@MainActor
final class SongCapturePluginTests: XCTestCase {
    func testHostAudioIsCapturedInOrderWithoutGaps() throws {
        let h = try Harness()
        h.shared[.driveDB] = 9
        XCTAssertEqual(h.shared.captureOn.value, 1, "the plug-in captures; the app analyses the file instead")
        var cursor = h.shared.capture.written.acquire()
        for _ in 0..<40 { h.render(512) }
        var records: [CaptureRecord] = []
        let lost = h.shared.capture.drain(&cursor) { records.append($0) }
        XCTAssertEqual(lost, 0)
        XCTAssertGreaterThan(records.count, 40 * 512 / 64 - 2)
        // the test host has no transport: frames since Red Clip started, said so
        XCTAssertEqual(SongClock(rawValue: h.shared.songClock.value), .relative)
        for (a, b) in zip(records, records.dropFirst()) {
            XCTAssertEqual(b.frame, a.frame + a.frames, "contiguous, never joined across a jump")
        }
        let stampNow = SongStamp.of(h.shared.params)
        XCTAssertTrue(records.allSatisfy { $0.stamp == stampNow })
        XCTAssertGreaterThan(records.map(\.reductionDB).max() ?? 0, 1, "Drive 9 dB clips the test tones")
        XCTAssertGreaterThan(records.map(\.rawHi).max() ?? 0, 0.5, "the untouched input rides along for the live view")
        XCTAssertTrue(records.allSatisfy { $0.postHi <= dbToGain(h.shared[.ceilingDB]) + 1e-4 })
    }

    func testBypassedPluginCapturesNothing() throws {
        let h = try Harness()
        h.unit.shouldBypassEffect = true
        var cursor = h.shared.capture.written.acquire()
        for _ in 0..<8 { h.render(512) }
        var count = 0
        h.shared.capture.drain(&cursor) { _ in count += 1 }
        XCTAssertEqual(count, 0)
    }
}
