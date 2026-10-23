import XCTest

// The parallel mixer: Mix (linked) or separate Dry and Wet levels (unlinked), driven through
// the real plug-in render path. The dry signal runs through the same oversampling filters as
// the clipped one, so the two add up sample for sample, with no comb filtering.

@MainActor
final class MixerTests: XCTestCase {

    /// A plug-in with these settings, run for half a second so the smoothers have settled.
    private func settled(_ settings: [Param: Float]) throws -> Harness {
        let h = try Harness()
        for (p, v) in settings { h.shared[p] = v }
        for _ in 0..<24 { h.render(1024) }
        return h
    }

    private func output(_ settings: [Param: Float]) throws -> [Float] { try settled(settings).render(1024).l }

    private func worst(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).map { abs($0 - $1) }.max() ?? 0 }

    private let crush: [Param: Float] = [.driveDB: 12, .ceilingDB: -6, .clipMode: 0, .gold: 80]

    func testUnlinkedDryAndWetThatAddUpTo100MatchTheMixKnob() throws {
        for os: Float in [0, 1, 2] {
            let linked = try output(crush.merging([.oversampling: os, .mix: 40]) { $1 })
            let unlinked = try output(crush.merging([.oversampling: os, .mixUnlink: 1, .dry: 60, .wet: 40]) { $1 })
            XCTAssertLessThan(worst(linked, unlinked), 1e-5, "oversampling \(os)")
        }
    }

    func testDryAndWetAddUpSampleForSample() throws {
        for os: Float in [0, 1, 2] {
            let base = crush.merging([.oversampling: os, .mixUnlink: 1]) { $1 }
            let both = try output(base.merging([.dry: 100, .wet: 100]) { $1 })
            let dry = try output(base.merging([.dry: 100, .wet: 0]) { $1 })
            let wet = try output(base.merging([.dry: 0, .wet: 100]) { $1 })
            XCTAssertLessThan(worst(both, zip(dry, wet).map { $0 + $1 }), 1e-5, "oversampling \(os)")
            // 100 % dry under the clipped signal: louder than either alone (bottom-up)
            XCTAssertGreaterThan(both.map { abs($0) }.max()!, wet.map { abs($0) }.max()! + 0.1)
        }
    }

    func testDryAndWetAreInPhaseAtEveryOversampling() throws {
        // Nothing clips (peaks ~0.65, under the knee), so wet is the dry signal: if the two paths
        // were a sample apart, adding them would comb-filter instead of doubling exactly
        for os: Float in [0, 1, 2] {
            let base: [Param: Float] = [.oversampling: os, .mixUnlink: 1, .ceilingDB: 0]
            let dry = try output(base.merging([.dry: 100, .wet: 0]) { $1 })
            let both = try output(base.merging([.dry: 100, .wet: 100]) { $1 })
            XCTAssertLessThan(worst(both, dry.map { $0 * 2 }), 1e-4, "oversampling \(os)")
        }
    }

    func testFullDryIsTheUntouchedInputAt1x() throws {
        let h = try settled(crush.merging([.oversampling: 0, .mixUnlink: 1, .dry: 100, .wet: 0]) { $1 })
        let t0 = Int(h.time)
        let out = h.render(1024).l
        for i in 0..<out.count { XCTAssertEqual(out[i], Harness.signal(t0 + i, channel: 0), accuracy: 1e-6) }
    }

    func testUnlinkingKeepsTheSoundAndRelinkingKeepsTheBalance() {
        let store = ParamStore(shared: SharedState())
        store[.mix] = 30
        store[.mixUnlink] = 1
        XCTAssertEqual(store[.wet], 30)
        XCTAssertEqual(store[.dry], 70)

        store[.dry] = 100
        store[.wet] = 50
        store[.mixUnlink] = 0
        XCTAssertEqual(store[.mix], 33)              // 50 / (100 + 50), rounded

        // linked, the mixer's Dry side moves Mix the other way
        store.mixerBinding(wet: false).wrappedValue = 80
        XCTAssertEqual(store[.mix], 20)
    }

    func testOlderProjectsOpenWithTheMixerLinked() throws {
        let h = try Harness()
        h.shared[.mix] = 40
        var state = h.unit.fullState ?? [:]
        var values = state["redclip.params"] as? [String: Float] ?? [:]
        for p in [Param.mixUnlink, .dry, .wet] { values.removeValue(forKey: p.id) }
        state["redclip.params"] = values
        h.unit.fullState = state
        XCTAssertEqual(h.shared[.mixUnlink], 0)
        XCTAssertEqual(h.shared[.mix], 40)
    }
}
