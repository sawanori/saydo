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

    // MARK: 本の並び

    func testDefaultsAreEveryThreeMinutesFortyTimesPerRound() {
        XCTAssertEqual(AlarmPlan.defaultInterval, 180)
        XCTAssertEqual(AlarmPlan.defaultCount, 40)

        let start = date(2026, 10, 6, 13, 0)
        let slots = AlarmPlan.slots(on: start, round: .noon, start: start, calendar: tokyo)

        XCTAssertEqual(slots.count, 40)
        XCTAssertEqual(slots.first?.fireDate, start)
        XCTAssertEqual(slots.last?.fireDate, date(2026, 10, 6, 14, 57))
        for (index, slot) in slots.enumerated() {
            XCTAssertEqual(slot.index, index)
            XCTAssertEqual(slot.round, .noon)
            XCTAssertEqual(slot.fireDate, start.addingTimeInterval(Double(index) * 180))
        }
    }

    func testCustomIntervalAndCount() {
        let start = date(2026, 10, 6, 9, 0)
        let slots = AlarmPlan.slots(on: start, round: .morning, start: start, interval: 60, count: 5, calendar: tokyo)
        XCTAssertEqual(slots.map(\.fireDate), (0..<5).map { start.addingTimeInterval(Double($0) * 60) })
        XCTAssertTrue(AlarmPlan.slots(on: start, round: .morning, start: start, count: 0, calendar: tokyo).isEmpty)
        XCTAssertTrue(AlarmPlan.slots(on: start, round: .morning, start: start, count: -3, calendar: tokyo).isEmpty)
    }

    // MARK: 識別子

    func testIdentifiersOfARoundAreDeterministic() {
        let day = date(2026, 10, 6, 16, 0)
        for round in AlarmRound.allCases {
            let first = AlarmPlan.slots(on: day, round: round, start: day, calendar: tokyo)
            let second = AlarmPlan.slots(on: day, round: round, start: day, calendar: tokyo)
            XCTAssertEqual(first, second)
            XCTAssertEqual(Set(first.map(\.id)).count, 40)
            XCTAssertEqual(first.map(\.id), AlarmPlan.identifiers(on: date(2026, 10, 6, 3, 0), round: round, calendar: tokyo))
        }
    }

    func testStartTimeDoesNotChangeIdentifiersOfTheSameDayAndRound() {
        let day = date(2026, 10, 6, 0, 0)
        let early = AlarmPlan.slots(on: day, round: .evening, start: date(2026, 10, 6, 19, 0), calendar: tokyo)
        let late = AlarmPlan.slots(on: day, round: .evening, start: date(2026, 10, 6, 21, 30), calendar: tokyo)
        XCTAssertEqual(early.map(\.id), late.map(\.id))
    }

    func testDifferentRoundsDoNotShareIdentifiers() {
        let day = date(2026, 10, 6, 12, 0)
        var seen = Set<UUID>()
        for round in AlarmRound.allCases {
            let ids = Set(AlarmPlan.identifiers(on: day, round: round, calendar: tokyo))
            XCTAssertEqual(ids.count, 40)
            XCTAssertTrue(seen.isDisjoint(with: ids), "\(round)")
            seen.formUnion(ids)
        }
    }

    /// 回は朝・昼・晩の 3 つだけ。旧い版の「追加の 1 回」は、取り消しの対象にだけ残る。
    func testAllIdentifiersOfTheDayCoverThreeRoundsAndTheRetiredExtraOne() {
        XCTAssertEqual(AlarmRound.allCases, [.morning, .noon, .evening])
        let day = date(2026, 10, 6, 12, 0)
        let all = AlarmPlan.allIdentifiers(on: day, calendar: tokyo)
        XCTAssertEqual(all.count, 3 * 40 + 40)
        XCTAssertEqual(Set(all).count, all.count)
        for round in AlarmRound.allCases {
            let ids = AlarmPlan.identifiers(on: day, round: round, calendar: tokyo)
            XCTAssertEqual(ids.count, 40)
            XCTAssertTrue(Set(all).isSuperset(of: ids), "\(round)")
        }
        let retired = AlarmPlan.retiredExtraIdentifiers(on: day, calendar: tokyo)
        XCTAssertEqual(retired.count, 40)
        XCTAssertTrue(Set(all).isSuperset(of: retired), "旧い版が登録した追加の 1 回も取り消せる")
        // task_058 の版が追加の 1 回に使っていた値（日付 + 回 4 + 連番 1）。値そのものを固定する。
        XCTAssertEqual(retired[1].uuidString, "0135288E-0001-8004-8053-4159444F414C")
    }

    func testDifferentDaysGiveDifferentIdentifiers() {
        let today = AlarmPlan.allIdentifiers(on: date(2026, 10, 6, 16, 0), calendar: tokyo)
        let tomorrow = AlarmPlan.allIdentifiers(on: date(2026, 10, 7, 16, 0), calendar: tokyo)
        XCTAssertTrue(Set(today).isDisjoint(with: Set(tomorrow)))
    }

    func testDayIsDecidedByTheGivenCalendar() {
        // 東京の 7 日 00:30 は UTC では 6 日 15:30。渡した暦の日付が使われる。
        let start = date(2026, 10, 7, 0, 30)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let inTokyo = AlarmPlan.identifier(on: start, round: .morning, index: 0, calendar: tokyo)
        let inUTC = AlarmPlan.identifier(on: start, round: .morning, index: 0, calendar: utc)
        XCTAssertNotEqual(inTokyo, inUTC)
        XCTAssertEqual(inTokyo, AlarmPlan.identifier(on: date(2026, 10, 7, 23, 0), round: .morning, index: 0, calendar: tokyo))
        XCTAssertEqual(inUTC, AlarmPlan.identifier(on: date(2026, 10, 6, 12, 0), round: .morning, index: 0, calendar: tokyo))
    }

    func testIdentifierIsAFixedValueSoItSurvivesRelaunch() {
        // 識別子の作り方を変えると、前の起動で登録したアラームを取り消せなくなる。値そのものを固定しておく。
        let id = AlarmPlan.identifier(on: date(2026, 10, 6, 16, 0), round: .noon, index: 1, calendar: tokyo)
        XCTAssertEqual(id.uuidString, "0135288E-0001-8002-8053-4159444F414C")
    }

    func testLegacyIdentifiersKeepTheOldValuesAndNeverCollideWithTheNewOnes() {
        let day = date(2026, 10, 6, 16, 0)
        let legacy = AlarmPlan.legacyIdentifiers(on: day, calendar: tokyo)
        XCTAssertEqual(legacy.count, 60)
        // task_053 が固定していた値（日付 + 連番 1）。
        XCTAssertEqual(legacy[1].uuidString, "0135288E-0001-8000-8053-4159444F414C")
        XCTAssertTrue(Set(legacy).isDisjoint(with: Set(AlarmPlan.allIdentifiers(on: day, calendar: tokyo))))
    }

    // MARK: どの回で追うか

    private func rounds(promisedAt: Date) -> [AlarmRoundStart] {
        AlarmPlan.rounds(
            promisedAt: promisedAt,
            morning: date(2026, 10, 6, 10, 0),
            noon: date(2026, 10, 6, 14, 0),
            evening: date(2026, 10, 6, 19, 0)
        )
    }

    func testAPromiseBeforeTheMorningRoundIsChasedThreeTimes() {
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 9, 0)), [
            AlarmRoundStart(round: .morning, start: date(2026, 10, 6, 10, 0)),
            AlarmRoundStart(round: .noon, start: date(2026, 10, 6, 14, 0)),
            AlarmRoundStart(round: .evening, start: date(2026, 10, 6, 19, 0)),
        ])
    }

    func testRoundsBeforeThePromiseAreSkipped() {
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 12, 0)).map(\.round), [.noon, .evening])
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 15, 0)).map(\.round), [.evening])
        // 回の時刻ちょうどの約束は、その回を飛ばす。
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 14, 0)).map(\.round), [.evening])
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 14, 5)).map(\.round), [.evening])
    }

    /// 3 回とも過ぎていたら、その日は追わない（追加の 1 回は無い）。
    func testAPromiseAfterAllThreeRoundsIsNotChasedThatDay() {
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 20, 0)), [])
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 19, 0)), [])
        XCTAssertEqual(rounds(promisedAt: date(2026, 10, 6, 23, 45)), [])
    }
}
