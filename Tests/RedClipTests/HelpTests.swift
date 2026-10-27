import XCTest
import CoreGraphics

// The "?" help layer finding the control under a finger, and the first-launch tour's steps.

final class HelpTests: XCTestCase {

    func testTopicUnderAPointIsTheSmallestAreaHoldingIt() {
        let areas = HelpAreas([
            .screen: [CGRect(x: 0, y: 0, width: 400, height: 200)],
            .clipReadout: [CGRect(x: 100, y: 50, width: 40, height: 20)],
            .presets: [CGRect(x: 500, y: 0, width: 20, height: 20), CGRect(x: 600, y: 0, width: 20, height: 20)]
        ])
        XCTAssertEqual(areas.topic(at: CGPoint(x: 10, y: 10)), .screen)
        XCTAssertEqual(areas.topic(at: CGPoint(x: 110, y: 60)), .clipReadout, "a small control on top of a panel wins")
        XCTAssertEqual(areas.topic(at: CGPoint(x: 610, y: 10)), .presets, "every area of a topic counts")
        XCTAssertNil(areas.topic(at: CGPoint(x: 550, y: 100)))
        XCTAssertEqual(areas.frame(.presets), CGRect(x: 500, y: 0, width: 120, height: 20))
    }

    func testTourVisitsEveryControlOnceInOrder() {
        XCTAssertEqual(Set(HelpTopic.tourOrder).count, HelpTopic.tourOrder.count, "no topic twice")
        XCTAssertEqual(Set(HelpTopic.tourOrder), Set(HelpTopic.allCases), "every topic has a place in the tour")
        let shown: Set<HelpTopic> = [.output, .power, .input, .bypass]
        XCTAssertEqual(HelpTopic.tourSteps(available: shown), [.power, .input, .output, .bypass])
        XCTAssertEqual(HelpTopic.tourSteps(available: []), [])
    }
}
