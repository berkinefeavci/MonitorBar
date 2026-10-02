import XCTest
@testable import MonitorBar

final class BrightnessScheduleTests: XCTestCase {
    func testOvernightWindowAndBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let schedule = BrightnessSchedule(nightStart: 22 * 60, nightEnd: 7 * 60)
        func date(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: hour, minute: minute))!
        }
        XCTAssertFalse(schedule.isNight(at: date(21, 59), calendar: calendar))
        XCTAssertTrue(schedule.isNight(at: date(22), calendar: calendar))
        XCTAssertTrue(schedule.isNight(at: date(6, 59), calendar: calendar))
        XCTAssertFalse(schedule.isNight(at: date(7), calendar: calendar))
    }
}
