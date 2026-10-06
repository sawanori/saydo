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
}
