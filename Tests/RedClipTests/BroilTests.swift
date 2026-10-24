import XCTest

// Broil: instantaneous compression toward the ceiling. Quiet material comes up, the ceiling
// stays exactly where it is, and nothing depends on what came before (no attack or release).

final class BroilTests: XCTestCase {
    private func db(_ v: Float) -> Float { 20 * log10(v) }

    private func curve(_ x: Float, _ c: Float, amount: Float) -> Float {
        let a = amount * Curves.broilMax
        return Curves.broil(x, ceiling: c, a: a, norm: 1 / tanh(a))
    }

    func testBroilLiftsQuietMaterialAndLeavesTheCeilingAlone() {
        let c: Float = 0.8
        XCTAssertEqual(curve(c, c, amount: 1), c, accuracy: 1e-5, "a peak on the ceiling stays on it")
        XCTAssertEqual(curve(-c, c, amount: 1), -c, accuracy: 1e-5)
        let quiet = c * dbToGain(-40)
        XCTAssertEqual(db(curve(quiet, c, amount: 1) / quiet), db(Curves.broilMax / tanh(Curves.broilMax)), accuracy: 0.05)
        XCTAssertGreaterThan(db(curve(quiet, c, amount: 1) / quiet), 7.5, "quiet material comes up about 8 dB at 100 %")
        // monotonic and never past the ceiling below it, at every amount
        for amount: Float in [0.1, 0.5, 1] {
            var last: Float = 0
            for i in 1...2000 {
                let x = c * Float(i) / 2000
                let y = curve(x, c, amount: amount)
                XCTAssertLessThanOrEqual(y, c + 1e-5)
                XCTAssertGreaterThan(y, last)
                last = y
            }
        }
    }

    @MainActor
    func testBroilRaisesLoudnessButNotThePeak() throws {
        func settled(_ broil: Float) throws -> [Float] {
            let h = try Harness()
            for (p, v) in [Param.driveDB: 6, .ceilingDB: -3, .clipMode: 0, .oversampling: 0, .broil: broil] { h.shared[p] = v }
            for _ in 0..<24 { h.render(1024) }
            return h.render(1024).l
        }
        let off = try settled(0), on = try settled(100)
        func rms(_ a: [Float]) -> Float { (a.map { $0 * $0 }.reduce(0, +) / Float(a.count)).squareRoot() }
        let peakOff = off.map { abs($0) }.max()!, peakOn = on.map { abs($0) }.max()!
        XCTAssertLessThanOrEqual(peakOn, dbToGain(-3) + 1e-4, "the ceiling still holds")
        XCTAssertGreaterThan(db(rms(on) / rms(off)), 1, "denser, louder body")  // about 1.3 dB here
        XCTAssertEqual(peakOn, peakOff, accuracy: 1e-4, "peaks on the ceiling stay put")
    }
}
