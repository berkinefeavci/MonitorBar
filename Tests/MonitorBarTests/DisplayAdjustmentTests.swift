import XCTest
@testable import MonitorBar

final class DisplayAdjustmentTests: XCTestCase {
    func testContrastUsesNeutralMidpointAndPreservesChannelValues() {
        let original: [Float] = [0, 0.25, 0.5, 0.75, 1]
        XCTAssertEqual(adjustedContrastTable(original, percent: 50), original)
        XCTAssertEqual(adjustedContrastTable(original, percent: 0), [0.25, 0.375, 0.5, 0.625, 0.75])
        XCTAssertEqual(adjustedContrastTable(original, percent: 100), [0, 0.125, 0.5, 0.875, 1])
    }
}
