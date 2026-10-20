import XCTest

// The live scope: drives audio through the real plug-in render path, then reads the screen's
// data with the same ScopeReader the faceplate draws from, and checks that each control changes
// both what you hear (the rendered output) and what the screen shows.

@MainActor
final class ScopeTests: XCTestCase {

    /// A plug-in with these settings, run for half a second so the smoothers have settled.
    private func settled(_ settings: [Param: Float]) throws -> Harness {
        let h = try Harness()
        for (p, v) in settings { h.shared[p] = v }
        for _ in 0..<24 { h.render(1024) }
        return h
    }

    /// The screen's columns. columns = the whole window gives one sample per column.
    private func screen(_ h: Harness, columns: Int = 400) -> ScopeReader {
        let r = ScopeReader()
        r.update(h.shared, columns: columns)
        return r
    }

    private var oneSamplePerColumn: Int { Int(48_000 * ScopeReader.window) }

    private func peak(_ r: ScopeReader) -> Float { max(r.outMax.max()!, -r.outMin.min()!) }
    private func inPeak(_ r: ScopeReader) -> Float { max(r.inMax.max()!, -r.inMin.min()!) }

    // MARK: Gray = original input, red = final output, lined up (latency compensated)

    func testTracesAreLinedUpAtEveryOversampling() throws {
        // Mix 0 % makes the output the dry signal after the same filters, so red must sit on grey
        for (os, tolerance) in [(Float(0), Float(1e-6)), (1, 0.012), (2, 0.06)] {
            let h = try settled([.mix: 0, .oversampling: os])
            let r = screen(h, columns: oneSamplePerColumn)
            XCTAssertEqual(r.samplesPerColumn, 1)
            var worst: Float = 0
            for c in 0..<r.columns { worst = max(worst, abs(r.outMax[c] - r.inMax[c])) }
            XCTAssertLessThan(worst, tolerance, "oversampling \(os): red and grey are \(worst) apart")
        }
    }

    func testWindowIsAbout120msOnOneScale() throws {
        let h = try settled([:])
        let r = screen(h, columns: 834)
        let ms = Double(r.samplesPerColumn * r.columns) / 48.0
        XCTAssertEqual(ms, 120, accuracy: 1)
        // fixed scale: the grey trace is the input's real level (its L+R mid peaks just under
        // 0.6 for this signal), not stretched to fill the glass
        XCTAssertGreaterThan(inPeak(r), 0.5); XCTAssertLessThan(inPeak(r), 0.66)
    }

    // MARK: Clipping, read from the clipper's own input and output

    func testHardClippingFlattensPeaksAtTheCeiling() throws {
        let ceiling: Float = -6, c = pow(10, ceiling / 20)
        let h = try settled([.oversampling: 0, .clipMode: 0, .driveDB: 9, .ceilingDB: ceiling])
        let r = screen(h, columns: oneSamplePerColumn)
        var flat = 0, cut = 0
        for i in 0..<r.columns {
            XCTAssertLessThanOrEqual(r.outMax[i], c + 1e-5, "output above the ceiling at column \(i)")
            if abs(r.outMax[i] - c) < 1e-5 { flat += 1 }
            if r.removed(i).top > 0.01 { cut += 1 }
        }
        XCTAssertGreaterThan(flat, r.columns / 20, "hard clipping should leave flat tops on the ceiling")
        XCTAssertGreaterThan(cut, r.columns / 20, "the screen should see the peaks the clipper removed")
    }

    func testSoftModesShowTheirCurve() throws {
        let ceiling: Float = -6, c = pow(10, ceiling / 20)
        func atCeiling(_ mode: Float) throws -> (onCeiling: Int, bent: Int) {
            let h = try settled([.oversampling: 0, .clipMode: mode, .driveDB: 9, .ceilingDB: ceiling])
            let r = screen(h, columns: oneSamplePerColumn)
            var on = 0, bent = 0
            for i in 0..<r.columns {
                if r.clipOutMax[i] > c - 1e-4 { on += 1 }
                // inside the knee: the clipper changed the sample but left it under the ceiling
                if r.removed(i).top > 1e-4 && r.clipOutMax[i] < c - 1e-3 { bent += 1 }
            }
            return (on, bent)
        }
        let hard = try atCeiling(0), classic = try atCeiling(1), modern = try atCeiling(2)
        XCTAssertEqual(hard.bent, 0, "hard has no knee")
        XCTAssertGreaterThan(classic.bent, 0); XCTAssertGreaterThan(modern.bent, 0)
        XCTAssertGreaterThan(classic.bent, modern.bent, "classic's knee is softer (wider) than modern's")
        XCTAssertGreaterThan(hard.onCeiling, classic.onCeiling)
    }

    // MARK: Each control changes the sound and the picture

    func testControlsChangeOutputAndScreen() throws {
        let base = try settled([.oversampling: 0])
        let baseOut = base.render(512).l
        let baseScreen = screen(base)

        // Output -6 dB: red halves, grey stays put
        let quieter = try settled([.oversampling: 0, .outputDB: -6])
        XCTAssertNotEqual(quieter.render(512).l, baseOut)
        let q = screen(quieter)
        XCTAssertEqual(peak(q) / peak(baseScreen), pow(10, -6 / 20), accuracy: 0.01)
        XCTAssertEqual(inPeak(q), inPeak(baseScreen), accuracy: 1e-6)

        // Input +6 dB into a -3 dB ceiling: red grows and flattens at the ceiling, grey unchanged
        let hotter = try settled([.oversampling: 0, .inputDB: 6, .ceilingDB: -3, .clipMode: 0])
        XCTAssertNotEqual(hotter.render(512).l, baseOut)
        let hs = screen(hotter)
        XCTAssertEqual(peak(hs), pow(10, -3 / 20), accuracy: 1e-4)
        XCTAssertEqual(inPeak(hs), inPeak(baseScreen), accuracy: 1e-6)

        // Drive pushes harder into the same ceiling: more of the wave is cut
        func cutColumns(_ r: ScopeReader) -> Int { (0..<r.columns).filter { r.removed($0).top > 0.01 }.count }
        let driven = try settled([.oversampling: 0, .inputDB: 6, .ceilingDB: -3, .clipMode: 0, .driveDB: 6])
        XCTAssertNotEqual(driven.render(512).l, hotter.render(512).l)
        XCTAssertGreaterThan(cutColumns(screen(driven)), cutColumns(hs))

        // Ceiling lower: the output peak follows it
        let lower = try settled([.oversampling: 0, .inputDB: 6, .ceilingDB: -9, .clipMode: 0])
        XCTAssertEqual(peak(screen(lower)), pow(10, -9 / 20), accuracy: 1e-4)

        // Mix 50 %: some of the dry peak comes back over the ceiling (guides are clip-stage only)
        let mixed = try settled([.oversampling: 0, .inputDB: 6, .ceilingDB: -9, .clipMode: 0, .mix: 50])
        XCTAssertGreaterThan(peak(screen(mixed)), pow(10, -9 / 20) + 0.05)

        // Bypass: red is the input itself
        let bypassed = try settled([.oversampling: 1, .inputDB: 6, .driveDB: 6, .bypass: 1])
        let b = screen(bypassed, columns: oneSamplePerColumn)
        for i in 0..<b.columns { XCTAssertEqual(b.outMax[i], b.inMax[i], accuracy: 1e-4, "bypass column \(i)") }
    }

    func testRedAndFireChangeTheSignal() throws {
        let plain = try settled([.oversampling: 0, .ceilingDB: -3])
        let red = try settled([.oversampling: 0, .ceilingDB: -3, .gold: 100, .goldMode: 1])
        let fire = try settled([.oversampling: 0, .ceilingDB: -3, .gold: 100, .goldMode: 1, .alchemy: 100])
        let a = screen(plain, columns: oneSamplePerColumn)
        let b = screen(red, columns: oneSamplePerColumn)
        let f = screen(fire, columns: oneSamplePerColumn)
        // Red (Classic, 100 %) saturates the peaks and adds 6 dB of make-up: the clipper's input
        // and the output get denser (louder on average), not just a little higher
        func meanAbs(_ v: [Float]) -> Float { v.reduce(0) { $0 + abs($1) } / Float(v.count) }
        XCTAssertGreaterThan(meanAbs(b.clipInMax), meanAbs(a.clipInMax) * 1.2)
        XCTAssertGreaterThan(meanAbs(b.outMax), meanAbs(a.outMax) * 1.2)
        XCTAssertNotEqual(red.render(256).l, plain.render(256).l)
        // Fire reshapes the clipped tone: the output differs from Red alone
        var diff: Float = 0
        for i in 0..<f.columns { diff = max(diff, abs(f.outMax[i] - b.outMax[i])) }
        XCTAssertGreaterThan(diff, 1e-3)
    }

    // MARK: Freeze, clear, silence

    func testPausedFreezesStoppedClearsSilenceIsFlat() throws {
        let h = try settled([:])
        let r = ScopeReader()
        XCTAssertTrue(r.update(h.shared, columns: 300))
        let before = r.outMax
        // no audio arriving (paused): nothing changes
        XCTAssertFalse(r.update(h.shared, columns: 300))
        XCTAssertEqual(r.outMax, before)

        // stopped: the screen starts from a flat line
        h.shared.scopeClearedAt.value = h.shared.ringTotal.acquire()
        r.update(h.shared, columns: 300)
        XCTAssertEqual(r.outMax.max()!, 0); XCTAssertEqual(r.outMin.min()!, 0)
        XCTAssertEqual(r.inMax.max()!, 0)

        // silence in, after the filters have rung out: flat
        h.mute.value = 1
        for _ in 0..<12 { h.render(1024) }
        r.update(h.shared, columns: 300)
        XCTAssertLessThan(peak(r), 1e-5)
        XCTAssertLessThan(inPeak(r), 1e-9)
    }
}
