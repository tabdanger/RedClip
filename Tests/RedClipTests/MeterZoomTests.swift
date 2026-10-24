import XCTest

// The screen's Gold Clip-style zoom tiers.

final class MeterZoomTests: XCTestCase {

    func testTiersMatchGoldClip() {
        XCTAssertEqual(MeterZoom.allCases.map { $0.topDB }, [6, 4, 2])
        XCTAssertEqual(MeterZoom.allCases.map { $0.floorDB }, [-36, -24, -12])
        XCTAssertEqual(MeterZoom.full.next, .zoom1)
        XCTAssertEqual(MeterZoom.zoom1.next, .zoom2)
        XCTAssertEqual(MeterZoom.zoom2.next, .full, "a double-tap on the last tier goes back to the full range")
    }

    func testScaleIsLinearInDBAndMirrored() {
        for z in MeterZoom.allCases {
            XCTAssertEqual(z.position(z.topDB), 1)
            XCTAssertEqual(z.position(z.floorDB), 0)
            XCTAssertEqual(z.position(z.topDB + 10), 1, "hotter than the range pins to the edge")
            XCTAssertEqual(z.position(-120), 0, "quieter than the range sits on the centre line")
            XCTAssertEqual(z.position((z.topDB + z.floorDB) / 2), 0.5, accuracy: 1e-6)
            XCTAssertEqual(z.position(sample: 0), 0)
            XCTAssertEqual(z.position(sample: -0.5), -z.position(sample: 0.5), accuracy: 1e-6)
            for db in z.marks { XCTAssertGreaterThan(z.position(db), 0) }
        }
        // zooming in spreads out the top of the scale: -6 dB moves away from 0 dB, toward the centre
        XCTAssertGreaterThan(MeterZoom.full.position(-6), MeterZoom.zoom1.position(-6))
        XCTAssertGreaterThan(MeterZoom.zoom1.position(-6), MeterZoom.zoom2.position(-6))
    }
}
