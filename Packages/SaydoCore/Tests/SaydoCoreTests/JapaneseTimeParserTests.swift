import Foundation
import XCTest

@testable import SaydoCore

final class JapaneseTimeParserTests: XCTestCase {

    private let parser = JapaneseTimeParser()

    /// 2026-09-04（金）08:00 の東京を基準にする。
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }

    private func now(hour: Int = 8, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: hour, minute: minute))!
    }

    private func components(_ date: Date?) -> (day: Int, hour: Int, minute: Int)? {
        guard let date else { return nil }
        let parts = calendar.dateComponents([.day, .hour, .minute], from: date)
        guard let day = parts.day, let hour = parts.hour, let minute = parts.minute else { return nil }
        return (day, hour, minute)
    }

    private func parse(_ text: String, at hour: Int = 8) -> JapaneseTimeParser.Result {
        parser.parse(text, now: now(hour: hour), calendar: calendar)
    }

    // MARK: - 10 パターン

    func test01AbsoluteHour() {
        let result = parse("14時")
        XCTAssertEqual(components(result.date)?.hour, 14)
        XCTAssertEqual(components(result.date)?.minute, 0)
        XCTAssertEqual(components(result.date)?.day, 4)
        XCTAssertEqual(result.matchedPhrase, "14時")
    }

    func test02BareHourPicksTheNextOneToCome() {
        // 朝 8 時に「2 時」と言えば、2 時ではなく 14 時。
        let result = parse("2時")
        XCTAssertEqual(components(result.date)?.hour, 14)
        XCTAssertEqual(components(result.date)?.day, 4)
    }

    func test03Meridiem() {
        XCTAssertEqual(components(parse("午後2時").date)?.hour, 14)
        XCTAssertEqual(components(parse("午前9時").date)?.hour, 9)
        XCTAssertEqual(components(parse("午前0時").date)?.hour, 0)
        XCTAssertEqual(components(parse("午後12時").date)?.hour, 12)
    }

    func test04HourAndMinute() {
        let result = parse("14時30分")
        XCTAssertEqual(components(result.date)?.hour, 14)
        XCTAssertEqual(components(result.date)?.minute, 30)
    }

    func test05HalfPast() {
        let result = parse("2時半")
        XCTAssertEqual(components(result.date)?.hour, 14)
        XCTAssertEqual(components(result.date)?.minute, 30)
    }

    func test06RelativeHours() {
        let result = parse("1時間後")
        XCTAssertEqual(result.date, now().addingTimeInterval(3600))
        XCTAssertEqual(result.matchedPhrase, "1時間後")
    }

    func test07RelativeMinutes() {
        XCTAssertEqual(parse("30分後").date, now().addingTimeInterval(1800))
        XCTAssertEqual(parse("2時間半後").date, now().addingTimeInterval(2 * 3600 + 1800))
    }

    func test08AfterNoon() {
        let result = parse("昼過ぎ")
        XCTAssertEqual(components(result.date)?.hour, 13)
        XCTAssertEqual(result.matchedPhrase, "昼過ぎ")
    }

    func test09NamedTimesOfDay() {
        XCTAssertEqual(components(parse("夕方").date)?.hour, 17)
        XCTAssertEqual(components(parse("午前中").date)?.hour, 10)
        XCTAssertEqual(components(parse("午後").date)?.hour, 14)
        XCTAssertEqual(components(parse("夜").date)?.hour, 20)
    }

    func test10FullWidthDigits() {
        let result = parse("１４時")
        XCTAssertEqual(components(result.date)?.hour, 14)
    }

    // MARK: - 今日に来ないとき

    func testBareHourRollsOverToTomorrowWhenBothCandidatesArePast() {
        // 22 時に「2 時」と言えば、翌日の 2 時。
        let result = parse("2時", at: 22)
        XCTAssertEqual(components(result.date)?.hour, 2)
        XCTAssertEqual(components(result.date)?.day, 5)
    }

    // MARK: - 場所（本人の言葉のまま持つ）

    func testPlaceIsKeptAsTheUserSaidIt() {
        XCTAssertEqual(parse("14時に自宅で").place, "自宅")
        XCTAssertEqual(parse("1時間後にカフェで").place, "カフェ")
        XCTAssertEqual(parse("会社で午後2時").place, "会社")
        XCTAssertEqual(parse("14時").place, "")
    }

    func testPlaceIsNotRewritten() {
        // 助詞だけを落とし、語そのものは書き換えない。
        XCTAssertEqual(parse("15時に近所のドトールでやります").place, "近所のドトール")
    }

    // MARK: - 読み取れないとき

    func testUnparseableAnswerKeepsThePlaceAndReturnsNoDate() {
        let result = parse("そのうち会社で")
        XCTAssertNil(result.date)
        XCTAssertNil(result.matchedPhrase)
        XCTAssertEqual(result.place, "そのうち会社")
    }

    func testInvalidHourIsRejected() {
        XCTAssertNil(JapaneseTimeParser.resolve(hour: 25, minute: 0, isPM: nil, now: now(), calendar: calendar))
        XCTAssertNil(JapaneseTimeParser.resolve(hour: 10, minute: 99, isPM: nil, now: now(), calendar: calendar))
    }

    // MARK: - M3 の答えをそのまま渡せること

    func testParsesTheAnswerTheFlowMachineStores() {
        var transition = FlowMachine.start(FlowEntry(sessionType: .morning))
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.awkward)), in: transition.state)
        transition = FlowMachine.handle(.transcript("メールを開く"), in: transition.state)
        transition = FlowMachine.handle(.transcript("14時に自宅で"), in: transition.state)

        let answer = transition.state.plannedAnswer ?? ""
        let result = parser.parse(answer, now: now(), calendar: calendar)
        XCTAssertEqual(components(result.date)?.hour, 14)
        XCTAssertEqual(result.place, "自宅")
    }
}
