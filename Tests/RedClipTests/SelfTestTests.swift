import XCTest

// The on-device Self-Test (REDCLIP MENU › Settings › Self-Test) must pass on a good build, so a
// change that breaks one of its checks shows up here too.

@MainActor
final class SelfTestTests: XCTestCase {
    func testSelfTestPassesOnThisBuild() {
        var tally = RedClipSelfTest.settingsChecks()
        RedClipSelfTest.engineChecks(&tally)
        XCTAssertGreaterThan(tally.count, 100)
        XCTAssertEqual(tally.failures, [], tally.failures.joined(separator: "\n"))
    }
}
