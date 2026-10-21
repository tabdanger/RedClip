import XCTest

// The LED meters: drives audio through the real plug-in render path in 1024-frame blocks (longer
// than a 60 fps frame, as many hosts use), steps the meters on a simulated display clock, and
// checks the readings against the audio actually rendered.

@MainActor
final class MeterTests: XCTestCase {

    private enum Strip: Int { case inL, inR, outL, outR }

    /// Plays `seconds` on a display clock at 60 fps. The display clock and the audio clock both
    /// count from the start of rendering; a block is rendered whenever the host would need the
    /// next one. Returns the left output rendered.
    @discardableResult
    private func play(_ h: Harness, _ meters: StereoMeterState, _ clock: inout Date,
                      seconds: Double, audio: Bool = true) -> [Float] {
        var out: [Float] = []
        let end = clock.addingTimeInterval(seconds)
        while clock < end {
            clock = clock.addingTimeInterval(1.0 / 60)
            while audio && h.time / 48_000 < clock.timeIntervalSinceReferenceDate { out += h.render(1024).l }
            meters.update(h.shared, now: clock)
        }
        return out
    }

    private func settled(_ settings: [Param: Float]) throws -> (Harness, StereoMeterState, Date) {
        let h = try Harness()
        for (p, v) in settings { h.shared[p] = v }
        for _ in 0..<24 { h.render(1024) }
        let meters = StereoMeterState()
        var clock = Date(timeIntervalSinceReferenceDate: h.time / 48_000)
        meters.update(h.shared, now: clock)
        play(h, meters, &clock, seconds: 1)
        return (h, meters, clock)
    }

    private func db(_ v: Double) -> Double { 20 * log10(max(v, 1e-9)) }
    private func rms(_ x: [Float]) -> Double { (x.reduce(0) { $0 + Double($1) * Double($1) } / Double(x.count)).squareRoot() }

    // MARK: The strips read the real level, steady between audio blocks

    func testOutputStripMatchesTheRenderedRMS() throws {
        let (h, meters, start) = try settled([:])
        var clock = start
        var lowest = Double.infinity, highest = -Double.infinity
        var all: [Float] = []
        for _ in 0..<60 {
            all += play(h, meters, &clock, seconds: 1.0 / 60)
            lowest = min(lowest, meters.levels[Strip.outL.rawValue])
            highest = max(highest, meters.levels[Strip.outL.rawValue])
        }
        let truth = db(rms(all))
        XCTAssertEqual(db(meters.levels[Strip.outL.rawValue]), truth, accuracy: 0.5,
                       "the output strip should sit on the RMS of what was rendered")
        XCTAssertLessThan(db(highest) - db(lowest), 0.5,
                          "a steady tone should hold the strip steady, not dip on frames between audio blocks")
    }

    // MARK: Input is metered before the clipper, output after Mix and Output, uncapped

    func testInputStripReadsBeforeDriveAndTheClipper() throws {
        let (_, clean, _) = try settled([.driveDB: 0])
        let (_, driven, _) = try settled([.driveDB: 12])
        for s in [Strip.inL, .inR] {
            XCTAssertEqual(db(driven.levels[s.rawValue]), db(clean.levels[s.rawValue]), accuracy: 0.1,
                           "Drive pushes into the clipper only; the input strip must not move with it")
        }
    }

    func testOutputPeakIsNotCappedAtTheCeiling() throws {
        let (_, meters, _) = try settled([.driveDB: 12, .ceilingDB: -6, .outputDB: 6])
        // Clipped at -6 dB, then +6 dB of output gain: final peaks reach about 0 dBFS, 6 dB over the ceiling.
        XCTAssertGreaterThan(meters.hold[Strip.outL.rawValue], -1.5,
                             "the output peak must follow the final samples, not stop at the ceiling")
    }

    func testBypassMetersTheDrySignalOnTheOutput() throws {
        let (_, meters, _) = try settled([.driveDB: 12, .ceilingDB: -6, .bypass: 1])
        XCTAssertEqual(db(meters.levels[Strip.outL.rawValue]), db(meters.levels[Strip.inL.rawValue]), accuracy: 0.3,
                       "bypassed, the output strip shows the untouched input")
    }

    // MARK: Ballistics

    func testStripsFallToSilenceWhenTheAudioStops() throws {
        let (h, meters, start) = try settled([:])
        var clock = start
        let playing = meters.levels.map(db)
        let hold = meters.hold[Strip.outL.rawValue]
        play(h, meters, &clock, seconds: 0.5, audio: false)
        XCTAssertEqual(meters.hold[Strip.outL.rawValue], hold, accuracy: 0.01, "the peak marker holds for 600 ms")
        play(h, meters, &clock, seconds: 0.5, audio: false)
        XCTAssertEqual(meters.hold[Strip.outL.rawValue], hold - 20 * 0.4, accuracy: 1, "then falls at 20 dB/s")
        play(h, meters, &clock, seconds: 0.5, audio: false)
        for n in 0..<4 {
            XCTAssertLessThan(db(meters.levels[n]), playing[n] - 20, "strip \(n) should have fallen once the audio stopped")
        }
    }
}
