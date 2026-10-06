import Foundation
import XCTest

@testable import SaydoCore

final class PromiseTimeTests: XCTestCase {

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 6) -> Date {
        tokyo.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testMorningNineGivesAllFourChips() {
        let now = date(9, 0)
        let options = PromiseTime.options(now: now, calendar: tokyo)

        XCTAssertEqual(options.map(\.chip), [.inThirtyMinutes, .inOneHour, .noon, .evening])
        XCTAssertEqual(options.map(\.date), [date(9, 30), date(10, 0), date(12, 0), date(18, 0)])
    }

    func testAtOnePMNoonIsGone() {
        let options = PromiseTime.options(now: date(13, 0), calendar: tokyo)
        XCTAssertEqual(options.map(\.chip), [.inThirtyMinutes, .inOneHour, .evening])
        XCTAssertEqual(options.map(\.date), [date(13, 30), date(14, 0), date(18, 0)])
    }

    func testAtSevenPMNoonAndEveningAreGone() {
        let options = PromiseTime.options(now: date(19, 0), calendar: tokyo)
        XCTAssertEqual(options.map(\.chip), [.inThirtyMinutes, .inOneHour])
        XCTAssertEqual(options.map(\.date), [date(19, 30), date(20, 0)])
    }

    func testAChipAtExactlyNowCountsAsPast() {
        XCTAssertNil(PromiseTime.date(for: .noon, now: date(12, 0), calendar: tokyo))
        XCTAssertEqual(PromiseTime.date(for: .noon, now: date(11, 59), calendar: tokyo), date(12, 0))
        XCTAssertNil(PromiseTime.date(for: .evening, now: date(18, 0), calendar: tokyo))
    }

    func testDefaultIsOneHourLater() {
        XCTAssertEqual(PromiseTime.defaultChip, .inOneHour)
        let now = date(9, 7)
        XCTAssertEqual(PromiseTime.defaultDate(now: now, calendar: tokyo), date(10, 7))
        XCTAssertEqual(PromiseTime.date(for: PromiseTime.defaultChip, now: now, calendar: tokyo), date(10, 7))
    }

    func testDefaultChipIsAlwaysAvailable() {
        for hour in [0, 6, 12, 18, 23] {
            let options = PromiseTime.options(now: date(hour, 45), calendar: tokyo)
            XCTAssertTrue(options.contains { $0.chip == PromiseTime.defaultChip }, "\(hour) 時台")
        }
    }

    func testRelativeChipsKeepTheSecondsOfNow() {
        let now = date(9, 0).addingTimeInterval(25)
        XCTAssertEqual(PromiseTime.date(for: .inThirtyMinutes, now: now, calendar: tokyo), date(9, 30).addingTimeInterval(25))
    }

    func testNoonIsTodayEvenWhenNowIsNearMidnight() {
        // 23:50 の 1 時間後は翌日だが、昼・夕方は当日のものしか返さない（すでに過ぎている）。
        let now = date(23, 50)
        let options = PromiseTime.options(now: now, calendar: tokyo)
        XCTAssertEqual(options.map(\.chip), [.inThirtyMinutes, .inOneHour])
        XCTAssertEqual(options.last?.date, date(0, 50, day: 7))
    }

    func testOptionLabelsComeFromPromiseCopy() {
        for option in PromiseTime.options(now: date(9, 0), calendar: tokyo) {
            XCTAssertEqual(option.label, PromiseCopy.chipLabel(option.chip))
        }
    }
}
