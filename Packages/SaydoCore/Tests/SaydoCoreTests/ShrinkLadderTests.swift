import Foundation
import XCTest

@testable import SaydoCore

final class ShrinkLadderTests: XCTestCase {

    func testLadderIsTheGeneralFourStepForm() {
        XCTAssertEqual(ShrinkLadder.rungs.map(\.name), ["開く", "一部だけ", "1行だけ", "置くだけ"])
        XCTAssertEqual(ShrinkLadder.rungs.count, 4)
    }

    func testLadderDoesNotDependOnAnyDomain() {
        // メール専用の段階表にしない（企画メモ §6 の例をそのまま使わない）。
        let domainWords = ["メール", "返信", "PC", "件名", "相手", "アプリ", "見積", "請求"]
        for rung in ShrinkLadder.rungs {
            for word in domainWords {
                XCTAssertFalse(rung.name.contains(word), "段の名前が分野に依存している: \(rung.name)")
                XCTAssertFalse(rung.actionText.contains(word), "行動文が分野に依存している: \(rung.actionText)")
            }
        }
    }

    func testEveryRungActionSatisfiesTheActionRule() {
        for rung in ShrinkLadder.rungs {
            XCTAssertTrue(
                Guardrails.isClean(rung.actionText, form: .action),
                "\(rung.actionText) → \(Guardrails.check(rung.actionText, form: .action))"
            )
            XCTAssertLessThanOrEqual(rung.estimatedMinutes, 5)
            XCTAssertGreaterThan(rung.estimatedMinutes, 0)
        }
    }

    func testEachRungIsSmallerThanTheOneAbove() {
        let minutes = ShrinkLadder.rungs.map(\.estimatedMinutes)
        XCTAssertEqual(minutes, minutes.sorted(by: >))
    }

    func testStartsAtTheTopRung() {
        let start = ShrinkLadder.start()
        XCTAssertEqual(start.text, "開く")
        XCTAssertEqual(start.shrinkCount, 0)
        XCTAssertTrue(start.isFiveMinutesOrLess)
    }

    func testGoesDownOneRungAtATime() {
        var action = ShrinkLadder.start()
        XCTAssertEqual(action.text, "開く")

        action = ShrinkLadder.next(after: action)
        XCTAssertEqual(action.text, "一部だけ見る")
        XCTAssertEqual(action.shrinkCount, 1)

        action = ShrinkLadder.next(after: action)
        XCTAssertEqual(action.text, "1行だけ書く")
        XCTAssertEqual(action.shrinkCount, 2)

        action = ShrinkLadder.next(after: action)
        XCTAssertEqual(action.text, "必要なものを机に置く")
        XCTAssertEqual(action.shrinkCount, 3)
    }

    func testStopsAtTheBottomRung() {
        var action = MicroAction(text: "必要なものを机に置く", estimatedMinutes: 1, shrinkCount: ShrinkLadder.lastIndex)
        XCTAssertFalse(ShrinkLadder.canShrink(action))

        action = ShrinkLadder.next(after: action)
        XCTAssertEqual(action.shrinkCount, ShrinkLadder.lastIndex)
        XCTAssertEqual(action.text, "必要なものを机に置く")
    }

    func testShrinkingWorksTheSameForAnyStartingAction() {
        // 分野の違う 3 つの行動が、同じ段階表を同じ順で下る。
        let starts = ["見積書を開く", "確定申告の書類を開く", "クライアントへの返信を開く"]
        for text in starts {
            let action = MicroAction(text: text, estimatedMinutes: 5, shrinkCount: 0)
            XCTAssertEqual(ShrinkLadder.next(after: action).text, "一部だけ見る")
        }
    }

    func testRungIndexIsClamped() {
        XCTAssertEqual(ShrinkLadder.rung(at: -5).name, "開く")
        XCTAssertEqual(ShrinkLadder.rung(at: 99).name, "置くだけ")
    }
}
