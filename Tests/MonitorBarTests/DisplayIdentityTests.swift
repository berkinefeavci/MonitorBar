import XCTest
@testable import MonitorBar

final class DisplayIdentityTests: XCTestCase {
    func testMatchesByFullIdentity() {
        let displays = [
            DisplayIdentity(id: 4, name: "A", vendor: 0x598b, product: 0x2700, serial: 1),
            DisplayIdentity(id: 5, name: "B", vendor: 0x598b, product: 0x2700, serial: 2),
        ]
        let services = [
            DDCIdentity(index: 8, vendor: 0x598b, product: 0x2700, serial: 2),
            DDCIdentity(index: 7, vendor: 0x598b, product: 0x2700, serial: 1),
        ]
        XCTAssertEqual(matchDisplays(displays, to: services), [4: 7, 5: 8])
    }

    func testRejectsAmbiguousTwins() {
        let displays = [
            DisplayIdentity(id: 4, name: "A", vendor: 0x598b, product: 0x2700, serial: 0),
            DisplayIdentity(id: 5, name: "B", vendor: 0x598b, product: 0x2700, serial: 0),
        ]
        let services = [
            DDCIdentity(index: 0, vendor: 0x598b, product: 0x2700, serial: 0),
            DDCIdentity(index: 1, vendor: 0x598b, product: 0x2700, serial: 0),
        ]
        XCTAssertTrue(matchDisplays(displays, to: services).isEmpty)
    }

    func testSingleDisplaySingleServiceFallback() {
        let display = DisplayIdentity(id: 4, name: "A", vendor: 0x598b, product: 0x2700, serial: 0)
        let service = DDCIdentity(index: 3, vendor: 0, product: 0, serial: 0)
        XCTAssertEqual(matchDisplays([display], to: [service]), [4: 3])
    }

    func testRejectsInvalidLevelsAndClampsInput() {
        XCTAssertNil(percent(current: 1, maximum: 0))
        XCTAssertNil(percent(current: 101, maximum: 100))
        XCTAssertEqual(percent(current: 58, maximum: 100)!, 58, accuracy: 0.0001)
        XCTAssertNil(rawLevel(percent: 50, maximum: 0))
        XCTAssertEqual(rawLevel(percent: -5, maximum: 100), 0)
        XCTAssertEqual(rawLevel(percent: 140, maximum: 100), 100)
        XCTAssertEqual(rawLevel(percent: 50, maximum: 255), 128)
    }
}
