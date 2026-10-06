import Foundation
import XCTest

@testable import SaydoCore

final class PromiseFollowUpCopyTests: XCTestCase {

    func testEveryFollowUpLinePassesGuardrails() {
        XCTAssertFalse(PromiseCopy.followUpLines.isEmpty)
        for line in PromiseCopy.followUpLines {
            let violations = Guardrails.check(line.text, form: line.form)
            XCTAssertTrue(violations.isEmpty, "「\(line.text)」→ \(violations)")
        }
    }

    /// `PromiseCopyTests.testEveryLinePassesGuardrails` が見る `allLines` に入っていること。
    func testAllLinesIncludeTheFollowUpLines() {
        let texts = Set(PromiseCopy.allLines.map(\.text))
        for line in PromiseCopy.followUpLines {
            XCTAssertTrue(texts.contains(line.text), line.text)
        }
    }

    func testFollowUpLinesCoverEveryConstant() {
        let texts = Set(PromiseCopy.followUpLines.map(\.text))
        let constants = [
            PromiseCopy.alarmOpenButton,
            PromiseCopy.alarmStopButton,
            PromiseCopy.followUpPromiseLabel,
            PromiseCopy.followUpActionLabel,
            PromiseCopy.followUpPlayVoice,
            PromiseCopy.followUpStopVoice,
            PromiseCopy.followUpClose,
            PromiseCopy.followUpSaveFailed,
        ]
        for text in constants {
            XCTAssertTrue(texts.contains(text), text)
        }
        XCTAssertEqual(Set(constants).count, constants.count)
    }
}
