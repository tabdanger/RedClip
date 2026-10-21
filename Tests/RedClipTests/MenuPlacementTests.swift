import XCTest
import SwiftUI

// The REDCLIP MENU panel is placed from the host container's own size and safe area. These check
// that it always stays inside the safe rectangle (12 pt margin), keeps the iPad / iPhone widths,
// and hangs under its trigger when there is room.

final class MenuPlacementTests: XCTestCase {

    private struct Case {
        let name: String
        let size: CGSize
        let safe: EdgeInsets
        let trigger: CGRect
    }

    private let cases: [Case] = [
        Case(name: "iPad landscape", size: CGSize(width: 1366, height: 1024),
             safe: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
             trigger: CGRect(x: 520, y: 40, width: 360, height: 40)),
        Case(name: "iPad portrait", size: CGSize(width: 1024, height: 1366),
             safe: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
             trigger: CGRect(x: 380, y: 300, width: 280, height: 30)),
        Case(name: "narrow iPad window", size: CGSize(width: 320, height: 1024),
             safe: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
             trigger: CGRect(x: 120, y: 420, width: 90, height: 12)),
        Case(name: "iPhone portrait", size: CGSize(width: 393, height: 852),
             safe: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
             trigger: CGRect(x: 120, y: 90, width: 160, height: 34)),
        Case(name: "iPhone landscape 667x375", size: CGSize(width: 667, height: 375),
             safe: EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 0),
             trigger: CGRect(x: 250, y: 18, width: 160, height: 24)),
        Case(name: "iPhone landscape 852x393", size: CGSize(width: 852, height: 393),
             safe: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
             trigger: CGRect(x: 340, y: 18, width: 170, height: 24)),
        Case(name: "compact AUv3 view", size: CGSize(width: 480, height: 300),
             safe: EdgeInsets(),
             trigger: CGRect(x: 180, y: 12, width: 120, height: 20)),
    ]

    func testPanelStaysInsideTheSafeRectangle() {
        for c in cases {
            for largeText in [false, true] {
                let f = RCMenuPlacement.frame(size: c.size, safe: c.safe, anchor: c.trigger, largeText: largeText)
                let m = RCMenuPlacement.margin
                XCTAssertGreaterThanOrEqual(f.minX, c.safe.leading + m - 0.001, c.name)
                XCTAssertGreaterThanOrEqual(f.minY, c.safe.top + m - 0.001, c.name)
                XCTAssertLessThanOrEqual(f.maxX, c.size.width - c.safe.trailing - m + 0.001, c.name)
                XCTAssertLessThanOrEqual(f.maxY, c.size.height - c.safe.bottom - m + 0.001, c.name)
                XCTAssertGreaterThan(f.height, 200, c.name)
            }
        }
    }

    func testWidthsMatchTheDesign() {
        for c in cases {
            let f = RCMenuPlacement.frame(size: c.size, safe: c.safe, anchor: c.trigger)
            let available = c.size.width - c.safe.leading - c.safe.trailing - 2 * RCMenuPlacement.margin
            if RCMenuPlacement.isCompact(c.size) {
                XCTAssertEqual(f.width, min(320, available), accuracy: 0.001, c.name)
            } else {
                XCTAssertEqual(f.width, 364, accuracy: 0.001, c.name)
                XCTAssertLessThanOrEqual(f.height, 680, c.name)
            }
        }
    }

    func testPanelHangsUnderItsTriggerWhenThereIsRoom() {
        for c in cases where c.size.height - c.safe.bottom - RCMenuPlacement.margin - c.trigger.maxY - 8 >= 320 {
            let f = RCMenuPlacement.frame(size: c.size, safe: c.safe, anchor: c.trigger)
            XCTAssertEqual(f.minY, c.trigger.maxY + 8, accuracy: 0.001, c.name)
            XCTAssertFalse(f.intersects(c.trigger), c.name)
        }
    }
}
