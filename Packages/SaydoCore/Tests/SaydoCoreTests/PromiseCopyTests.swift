import Foundation
import XCTest

@testable import SaydoCore

final class PromiseCopyTests: XCTestCase {

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    func testEveryLinePassesGuardrails() {
        XCTAssertFalse(PromiseCopy.allLines.isEmpty)
        for line in PromiseCopy.allLines {
            let violations = Guardrails.check(line.text, form: line.form)
            XCTAssertTrue(violations.isEmpty, "「\(line.text)」→ \(violations)")
        }
    }

    func testAllLinesCoverTheChipsAndTheReplies() {
        let texts = Set(PromiseCopy.allLines.map(\.text))
        for chip in PromiseChip.allCases {
            XCTAssertTrue(texts.contains(PromiseCopy.chipLabel(chip)), "\(chip)")
        }
        for outcome in [CommitmentOutcome.done, .partial, .notYet] {
            XCTAssertTrue(texts.contains(PromiseCopy.reply(for: outcome) ?? ""), "\(outcome)")
        }
        XCTAssertNil(PromiseCopy.reply(for: .pending))
    }

    func testTheTwoQuestionsAreFixed() {
        XCTAssertEqual(PromiseCopy.promiseQuestion, "今日の約束は？")
        XCTAssertEqual(PromiseCopy.firstActionQuestion, "そのために、最初にやることは？")
        XCTAssertTrue(Guardrails.isClean(PromiseCopy.promiseQuestion, form: .question))
        XCTAssertTrue(Guardrails.isClean(PromiseCopy.firstActionQuestion, form: .question))
    }

    func testChipLabelsAreDistinct() {
        let labels = PromiseChip.allCases.map(PromiseCopy.chipLabel)
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    func testCompletionLineInsertsTheTime() {
        let four = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 16, minute: 0))!
        let fourThirty = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 16, minute: 30))!
        XCTAssertEqual(PromiseCopy.completion(startingAt: four, calendar: tokyo), "16時から、あなたの声で追いかけます。")
        XCTAssertEqual(PromiseCopy.completion(startingAt: fourThirty, calendar: tokyo), "16時30分から、あなたの声で追いかけます。")
    }

    func testCompletionLinePassesGuardrailsForEveryHour() {
        for hour in 0..<24 {
            for minute in [0, 7, 30, 59] {
                let when = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour, minute: minute))!
                let line = PromiseCopy.completion(startingAt: when, calendar: tokyo)
                XCTAssertTrue(Guardrails.isClean(line, form: .statement), "\(line) → \(Guardrails.check(line, form: .statement))")
            }
        }
    }

    func testCompletionLinesThatDoNotPromiseAnAlarm() {
        // 追えないときは「追いかけます」と言わない。約束は残したことを伝える。
        for line in [PromiseCopy.completionNotAuthorized, PromiseCopy.completionAlarmUnavailable] {
            XCTAssertFalse(line.contains("追いかけます"), line)
            XCTAssertTrue(line.contains("約束は残しました"), line)
        }
    }

    func testCompletionWithoutVoiceDoesNotClaimTheVoice() {
        let four = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 16, minute: 0))!
        let line = PromiseCopy.completionWithoutVoice(startingAt: four, calendar: tokyo)
        XCTAssertEqual(line, "16時から、アラームで追いかけます。")
        XCTAssertFalse(line.contains("あなたの声"))
    }

    // MARK: 朝・昼・晩の 3 回で追う形（task_058）

    func testRoundLinesPassGuardrailsAndAreInAllLines() {
        XCTAssertFalse(PromiseCopy.roundLines.isEmpty)
        let texts = Set(PromiseCopy.allLines.map(\.text))
        for line in PromiseCopy.roundLines {
            let violations = Guardrails.check(line.text, form: line.form)
            XCTAssertTrue(violations.isEmpty, "「\(line.text)」→ \(violations)")
            XCTAssertTrue(texts.contains(line.text), line.text)
        }
    }

    func testCompletionLineNamesTheRoundsStillToCome() {
        let noon = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 13))!
        let evening = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 21))!
        XCTAssertEqual(
            PromiseCopy.completion(roundsAt: [noon, evening], calendar: tokyo),
            "13時と21時に、あなたの声で追いかけます。"
        )
        XCTAssertEqual(PromiseCopy.completion(roundsAt: [evening], calendar: tokyo), "21時に、あなたの声で追いかけます。")
        let withoutVoice = PromiseCopy.completionWithoutVoice(roundsAt: [noon, evening], calendar: tokyo)
        XCTAssertEqual(withoutVoice, "13時と21時に、アラームで追いかけます。")
        XCTAssertFalse(withoutVoice.contains("あなたの声"))
    }

    func testRepliesTellTheNextRoundOnlyWhenThereIsOne() {
        let evening = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 21))!
        for answer in [FollowUpAnswer.partial, .notYet] {
            let withNext = PromiseCopy.reply(for: answer, nextRoundAt: evening, calendar: tokyo)
            XCTAssertTrue(withNext.contains("次は21時に"), withNext)
            XCTAssertFalse(PromiseCopy.reply(for: answer, nextRoundAt: nil, calendar: tokyo).contains("次は"))
        }
        // その日の後追いを終える答えは、次の回を言わない。
        for answer in [FollowUpAnswer.done, .stopToday] {
            XCTAssertFalse(PromiseCopy.reply(for: answer, nextRoundAt: evening, calendar: tokyo).contains("次は"))
        }
        for answer in FollowUpAnswer.allCases {
            for next in [evening, nil] {
                let line = PromiseCopy.reply(for: answer, nextRoundAt: next, calendar: tokyo)
                XCTAssertTrue(Guardrails.isClean(line, form: .statement), line)
            }
        }
    }

    func testAnswersMapToTheSavedOutcome() {
        XCTAssertEqual(FollowUpAnswer.done.outcome, .done)
        XCTAssertEqual(FollowUpAnswer.partial.outcome, .partial)
        XCTAssertEqual(FollowUpAnswer.notYet.outcome, .notYet)
        XCTAssertEqual(FollowUpAnswer.stopToday.outcome, .notYet)
        XCTAssertEqual(FollowUpAnswer.allCases.filter(\.endsTheDay), [.done, .stopToday])
    }

    func testDeclarationTranscriptJoinsPromiseAndAction() {
        XCTAssertEqual(PromiseCopy.declarationTranscript(promise: "企画書を出す", action: "資料を開く"), "企画書を出す。資料を開く")
        XCTAssertEqual(PromiseCopy.declarationTranscript(promise: "企画書を出す。", action: " 資料を開く。 "), "企画書を出す。資料を開く")
    }
}
