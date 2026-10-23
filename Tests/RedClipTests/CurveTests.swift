import XCTest

// The static shaping curves: Red (Gold processing) and the Hard (Fruity Soft Clipper) clipper.

final class CurveTests: XCTestCase {
    private func db(_ v: Float) -> Float { 20 * log10(v) }

    func testRedAddsFullGainLowAndNoneAtTheCeiling() {
        let c: Float = 0.9
        let shape = Curves.redShape(6)
        func gainDB(_ inDB: Float) -> Float {
            let x = c * dbToGain(inDB)
            return db(Curves.red(x, ceiling: c, g: shape.g, k: shape.k) / x)
        }
        XCTAssertEqual(gainDB(-60), 6, accuracy: 0.05, "quiet material gets the full 6 dB")
        XCTAssertEqual(gainDB(-0.001), 0, accuracy: 0.01, "no gain at the ceiling")
        XCTAssertEqual(gainDB(3), 0, accuracy: 1e-5, "above the ceiling Red leaves it to the clipper")
        // never pushes a sub-ceiling peak past the ceiling, and never folds back (monotonic)
        var last: Float = 0
        for i in 1...2000 {
            let x = c * Float(i) / 2000
            let y = Curves.red(x, ceiling: c, g: shape.g, k: shape.k)
            XCTAssertLessThanOrEqual(y, c + 1e-5)
            XCTAssertGreaterThan(y, last)
            last = y
        }
    }

    func testUnityTakesTheGainBackOff() {
        let c: Float = 1
        let loud = Curves.gold(c, ceiling: c, amount: 1, classic: true, unity: true)
        XCTAssertEqual(db(loud), -6, accuracy: 0.01, "peaks come down by the 6 dB Red added")
        let quiet: Float = 0.001
        XCTAssertEqual(Curves.gold(quiet, ceiling: c, amount: 1, classic: true, unity: true), quiet, accuracy: quiet * 0.01,
                       "low-level material keeps its level")
    }

    func testHardIsASmoothCeilingedCurve() {
        let c: Float = 0.5, t = c * Curves.hardThreshold
        XCTAssertEqual(Curves.clip(t * 0.99, ceiling: c, knee: 0), t * 0.99, "untouched under the threshold")
        XCTAssertEqual(Curves.clip(c * 2, ceiling: c, knee: 0), c, "held on the ceiling")
        XCTAssertEqual(Curves.clip(-c * 2, ceiling: c, knee: 0), -c)
        var last: Float = 0, lastSlope: Float = 1
        let step: Float = c / 4000
        for i in 1...12000 {
            let y = Curves.clip(Float(i) * step, ceiling: c, knee: 0)
            XCTAssertLessThanOrEqual(y, c)
            XCTAssertGreaterThanOrEqual(y, last)
            let slope = (y - last) / step
            XCTAssertLessThan(abs(slope - lastSlope), 0.01, "no corners: the slope changes smoothly")
            last = y; lastSlope = slope
        }
    }
}
