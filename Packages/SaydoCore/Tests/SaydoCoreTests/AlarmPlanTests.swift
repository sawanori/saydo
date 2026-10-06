import Foundation
import XCTest

@testable import SaydoCore

final class AlarmPlanTests: XCTestCase {

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testDefaultsAreEveryThreeMinutesSixtyTimes() {
        XCTAssertEqual(AlarmPlan.defaultInterval, 180)
        XCTAssertEqual(AlarmPlan.defaultCount, 60)

        let start = date(2026, 10, 6, 16, 0)
        let slots = AlarmPlan.slots(start: start, calendar: tokyo)

        XCTAssertEqual(slots.count, 60)
        XCTAssertEqual(slots.first?.fireDate, start)
        XCTAssertEqual(slots.last?.fireDate, date(2026, 10, 6, 18, 57))
        for (index, slot) in slots.enumerated() {
            XCTAssertEqual(slot.index, index)
            XCTAssertEqual(slot.fireDate, start.addingTimeInterval(Double(index) * 180))
        }
        XCTAssertEqual(slots.map(\.fireDate), slots.map(\.fireDate).sorted())
    }

    func testCustomIntervalAndCount() {
        let start = date(2026, 10, 6, 9, 0)
        let slots = AlarmPlan.slots(start: start, interval: 60, count: 5, calendar: tokyo)
        XCTAssertEqual(slots.map(\.fireDate), (0..<5).map { start.addingTimeInterval(Double($0) * 60) })
        XCTAssertTrue(AlarmPlan.slots(start: start, count: 0, calendar: tokyo).isEmpty)
        XCTAssertTrue(AlarmPlan.slots(start: start, count: -3, calendar: tokyo).isEmpty)
    }

    func testSameInputGivesSameIdentifiers() {
        let start = date(2026, 10, 6, 16, 0)
        let first = AlarmPlan.slots(start: start, calendar: tokyo)
        let second = AlarmPlan.slots(start: start, calendar: tokyo)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testIdentifiersAreUniqueWithinADay() {
        let slots = AlarmPlan.slots(start: date(2026, 10, 6, 16, 0), calendar: tokyo)
        XCTAssertEqual(Set(slots.map(\.id)).count, 60)
    }

    func testStartTimeDoesNotChangeIdentifiersOfTheSameDay() {
        let early = AlarmPlan.slots(start: date(2026, 10, 6, 9, 0), calendar: tokyo)
        let late = AlarmPlan.slots(start: date(2026, 10, 6, 21, 30), calendar: tokyo)
        XCTAssertEqual(early.map(\.id), late.map(\.id))
    }

    func testDifferentDaysGiveDifferentIdentifiers() {
        let today = AlarmPlan.slots(start: date(2026, 10, 6, 16, 0), calendar: tokyo)
        let tomorrow = AlarmPlan.slots(start: date(2026, 10, 7, 16, 0), calendar: tokyo)
        XCTAssertTrue(Set(today.map(\.id)).isDisjoint(with: Set(tomorrow.map(\.id))))
    }

    func testDayIsDecidedByTheGivenCalendar() {
        // 東京の 7 日 00:30 は UTC では 6 日 15:30。渡した暦の日付が使われる。
        let start = date(2026, 10, 7, 0, 30)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let inTokyo = AlarmPlan.identifier(on: start, index: 0, calendar: tokyo)
        let inUTC = AlarmPlan.identifier(on: start, index: 0, calendar: utc)
        XCTAssertNotEqual(inTokyo, inUTC)
        XCTAssertEqual(inTokyo, AlarmPlan.identifier(on: date(2026, 10, 7, 23, 0), index: 0, calendar: tokyo))
        XCTAssertEqual(inUTC, AlarmPlan.identifier(on: date(2026, 10, 6, 12, 0), index: 0, calendar: tokyo))
    }

    func testAllIdentifiersOfTheDayMatchThePlan() {
        let start = date(2026, 10, 6, 16, 0)
        let planned = AlarmPlan.slots(start: start, calendar: tokyo).map(\.id)
        XCTAssertEqual(AlarmPlan.identifiers(on: date(2026, 10, 6, 3, 0), calendar: tokyo), planned)
        XCTAssertEqual(AlarmPlan.identifiers(on: start, calendar: tokyo), planned)
        XCTAssertEqual(AlarmPlan.identifiers(on: start, count: 10, calendar: tokyo), Array(planned.prefix(10)))
        XCTAssertTrue(AlarmPlan.identifiers(on: start, count: 0, calendar: tokyo).isEmpty)
    }

    func testIdentifierIsAFixedValueSoItSurvivesRelaunch() {
        // 識別子の作り方を変えると、前の起動で登録したアラームを取り消せなくなる。値そのものを固定しておく。
        let id = AlarmPlan.identifier(on: date(2026, 10, 6, 16, 0), index: 1, calendar: tokyo)
        XCTAssertEqual(id.uuidString, "0135288E-0001-8000-8053-4159444F414C")
    }
}
