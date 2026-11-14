import XCTest

// Every knob, at every 1 % of its travel: the readout is exactly what the engine does, the %
// knobs are even (n % of the knob = n % of the full effect, no dead zone), and the sound follows
// a move within 5 ms. Measured on real audio through ClipDSP (KnobAudit).

final class KnobTaperTests: XCTestCase {

    func testEveryReadoutIsWhatTheEngineDoes() {
        for p in KnobAudit.knobs {
            let r = KnobAudit.audit(p)
            XCTAssertLessThanOrEqual(r.worstError, p.isDecibels ? 0.01 : 0.1,
                                     "\(KnobAudit.name(p)) at \(r.worstAt) %: shows \(r.worstText), engine \(r.worstMeasured)")
            if !p.isDecibels {
                XCTAssertLessThanOrEqual(r.worstEvenness, 0.1, "\(KnobAudit.name(p)) is uneven")
                XCTAssertEqual(r.at10, 10, accuracy: 0.1, "\(KnobAudit.name(p)) at 10 %")
                XCTAssertEqual(r.at20, 20, accuracy: 0.1, "\(KnobAudit.name(p)) at 20 %")
            }
        }
    }

    func testTheSoundFollowsWithin5ms() {
        XCTAssertLessThanOrEqual(KnobAudit.responseMS(.outputDB, from: 0, to: -12), 5)
        XCTAssertLessThanOrEqual(KnobAudit.responseMS(.inputDB, from: 6, to: 0), 5)
        XCTAssertLessThanOrEqual(KnobAudit.responseMS(.driveDB, from: 0, to: 12), 5)
        XCTAssertLessThanOrEqual(KnobAudit.responseMS(.ceilingDB, from: -12, to: 0), 5)
        XCTAssertLessThanOrEqual(KnobAudit.responseMS(.wet, from: 100, to: 0), 5)
    }

    func testBroilTaperRoundTripsAndKeepsOldValues() {
        for k in stride(from: Float(0), through: 100, by: 1) {
            XCTAssertEqual(BroilTaper.percent(BroilTaper.raw(percent: k)), k, accuracy: 1e-3)
        }
        // the stored value keeps its meaning: old presets and automation sound the same
        XCTAssertEqual(BroilTaper.percent(100), 100, accuracy: 1e-4)
        XCTAssertEqual(BroilTaper.percent(0), 0)
        XCTAssertEqual(BroilTaper.percent(50), 41.68, accuracy: 0.01)
    }

    func testReadouts() {
        XCTAssertEqual(Param.inputDB.readout(0), "0.0 dB")
        XCTAssertEqual(Param.inputDB.readout(-11.8), "-11.8 dB")
        XCTAssertEqual(Param.outputDB.readout(7.4), "+7.4 dB")
        XCTAssertEqual(Param.outputDB.readout(7.44), "+7.44 dB", "between steps (host automation): one more decimal")
        XCTAssertEqual(Param.ceilingDB.readout(-0.3), "-0.3 dB")
        XCTAssertEqual(Param.driveDB.readout(0), "0.0 dB")
        XCTAssertEqual(Param.gold.readout(23), "23 %")
        XCTAssertEqual(Param.wet.readout(23.4), "23.4 %")
        XCTAssertEqual(Param.broil.readout(BroilTaper.raw(percent: 23)), "23 %")
    }
}
