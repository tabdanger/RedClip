import XCTest

// Dynamic window resizing: the face that shows biggest wins, for the app and inside a DAW.

final class WindowFitTests: XCTestCase {

    private func plate(_ w: CGFloat, _ h: CGFloat, plugin: Bool = false, _ finish: Faceplate = .face1) -> String {
        PlateLayout.fitting(finish, in: CGSize(width: w, height: h), plugin: plugin).plate
    }

    func testWideWindowsGetTheLandscapeFace() {
        XCTAssertEqual(plate(1366, 1024), "RCPlate", "iPad landscape, full screen")
        XCTAssertEqual(plate(980, 700), "RCPlate", "Stage Manager window")
        XCTAssertEqual(plate(700, 400, plugin: true), "RCPlate", "a short, wide DAW window")
    }

    func testTallWindowsGetThePortraitFace() {
        XCTAssertEqual(plate(1024, 1366), "RCPhonePlate", "iPad portrait")
        XCTAssertEqual(plate(678, 1024), "RCPhonePlate", "iPad Split View, half")
        XCTAssertEqual(plate(320, 1024), "RCPhonePlate", "Slide Over")
        XCTAssertEqual(plate(393, 852), "RCPhonePlate", "iPhone")
        XCTAssertEqual(plate(300, 700, plugin: true), "RCPhonePlate", "a narrow DAW window")
    }

    func testThePlatinumFinishFollowsTheSameRule() {
        XCTAssertEqual(plate(1366, 1024, .face1Platinum), "RCPlate")
        XCTAssertEqual(plate(393, 852, .face1Platinum), "RCPhonePlate")
    }

    func testTheChosenFaceIsNeverSmallerThanTheOther() {
        for (w, h) in [(1366.0, 1024.0), (1024, 1366), (678, 1024), (500, 500), (1200, 900), (900, 1200)] {
            let size = CGSize(width: w, height: h)
            let chosen = PlateLayout.fitting(.face1, in: size).fitScale(in: size)
            XCTAssertGreaterThanOrEqual(chosen, PlateLayout.pad.fitScale(in: size))
            XCTAssertGreaterThanOrEqual(chosen, PlateLayout.phone.fitScale(in: size))
        }
    }
}
