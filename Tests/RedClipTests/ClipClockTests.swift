import XCTest

// The Clip Clock: feeds the real ClipDSP blocks with a song position, as the app's playhead and
// the plug-in's host transport do, and checks MAX CLIP and MIN:SEC against where the loudest
// clip was put.

final class ClipClockTests: XCTestCase {
    private let sr = 48_000.0
    private let block = 512

    /// Plays `seconds` of a quiet tone with single-sample spikes at `spikes` (seconds -> level),
    /// with the song position starting at `startAt` (negative = transport stopped).
    private func play(_ dsp: ClipDSP, seconds: Double, startAt: Double = 0, spikes: [Double: Float]) {
        let total = Int(seconds * sr)
        let spikeAt = Dictionary(uniqueKeysWithValues: spikes.map { (Int(($0.key * sr).rounded()), $0.value) })
        let inL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let outL = UnsafeMutablePointer<Float>.allocate(capacity: block)
        let outR = UnsafeMutablePointer<Float>.allocate(capacity: block)
        defer { inL.deallocate(); outL.deallocate(); outR.deallocate() }
        var pos = 0
        while pos < total {
            let n = min(block, total - pos)
            for i in 0..<n { inL[i] = spikeAt[pos + i] ?? Float(0.3 * sin(2 * .pi * 220 * Double(pos + i) / sr)) }
            dsp.songTime = startAt < 0 ? -1 : startAt + Double(pos) / sr
            dsp.process(inL: inL, inR: inL, outL: outL, outR: outR, frames: n)
            pos += n
        }
    }

    private func make() -> (SharedState, ClipDSP) {
        let shared = SharedState()
        shared[.oversampling] = 0          // 1x: the spike reaches the clipper exactly as fed
        shared[.ceilingDB] = 0
        return (shared, ClipDSP(sampleRate: sr, shared: shared))
    }

    func testFindsTheBiggestClipAndWhenItHappened() {
        let (shared, dsp) = make()
        XCTAssertEqual(shared.clipClock.maxDB.value, 0)
        XCTAssertEqual(shared.clipClock.seconds.value, -1)

        // 2 dB over at 1.25 s, 6 dB over at 3.5 s, 3 dB over at 4.1 s
        play(dsp, seconds: 5, spikes: [1.25: dbToGain(2), 3.5: dbToGain(6), 4.1: dbToGain(3)])
        XCTAssertEqual(shared.clipClock.maxDB.value, 6, accuracy: 0.05)
        XCTAssertEqual(shared.clipClock.seconds.value, 3.5, accuracy: 0.001)
        XCTAssertEqual(ClipClockState.timeText(shared.clipClock.seconds.value), "0:03:50")
    }

    func testSongPositionCarriesThroughLaterInTheSong() {
        let (shared, dsp) = make()
        // the host starts playback at 3:12.00; the clip is 1.04 s in
        play(dsp, seconds: 2, startAt: 192, spikes: [1.04: dbToGain(3)])
        XCTAssertEqual(shared.clipClock.maxDB.value, 3, accuracy: 0.05)
        XCTAssertEqual(ClipClockState.timeText(shared.clipClock.seconds.value), "3:13:04")
    }

    func testStoppedTransportRecordsNothing() {
        let (shared, dsp) = make()
        play(dsp, seconds: 1, startAt: -1, spikes: [0.5: dbToGain(6)])
        XCTAssertEqual(shared.clipClock.maxDB.value, 0)
        XCTAssertEqual(shared.clipClock.seconds.value, -1)
    }

    func testResetStartsANewPass() {
        let (shared, dsp) = make()
        play(dsp, seconds: 2, spikes: [1: dbToGain(6)])
        XCTAssertEqual(shared.clipClock.maxDB.value, 6, accuracy: 0.05)

        shared.clipClock.requestReset()
        XCTAssertEqual(ClipClockState.dbText(shared.clipClock.maxDB.value), "-- dB")
        // a smaller clip now counts, since the 6 dB one belongs to the old pass
        play(dsp, seconds: 2, spikes: [0.75: dbToGain(1.5)])
        XCTAssertEqual(shared.clipClock.maxDB.value, 1.5, accuracy: 0.05)
        XCTAssertEqual(shared.clipClock.seconds.value, 0.75, accuracy: 0.001)
    }

    func testReadoutText() {
        XCTAssertEqual(ClipClockState.timeText(-1), "-:--:--")
        XCTAssertEqual(ClipClockState.timeText(193), "3:13:00")
        XCTAssertEqual(ClipClockState.timeText(59.994), "0:59:99")
        XCTAssertEqual(ClipClockState.timeText(59.999), "1:00:00")
        XCTAssertEqual(ClipClockState.dbText(0), "-- dB")
        XCTAssertEqual(ClipClockState.dbText(3), "3.0 dB")
    }
}

/// The plug-in's render path: a host without a transport gets the time since Red Clip started.
@MainActor
final class ClipClockPluginTests: XCTestCase {
    func testPluginWithoutHostTransportCountsFromTheStart() throws {
        let h = try Harness()
        h.shared[.driveDB] = 12
        for _ in 0..<48 { h.render(1024) }
        let clock = h.shared.clipClock
        XCTAssertGreaterThan(clock.maxDB.value, 1)
        XCTAssertGreaterThanOrEqual(clock.seconds.value, 0)
        XCTAssertLessThan(clock.seconds.value, Float(48 * 1024) / 48_000)
    }
}
