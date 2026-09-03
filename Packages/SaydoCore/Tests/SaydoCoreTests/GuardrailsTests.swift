import Foundation
import XCTest

@testable import SaydoCore

final class GuardrailsTests: XCTestCase {

    // MARK: - 禁止句（句パターン）

    func testBannedPhrasesAreRejected() {
        let blaming = [
            "3日連続で未達成です。",
            "また逃げましたね。",
            "サボらないで。",
            "怠けていませんか。",
            "それは言い訳です。",
            "甘えないで。",
            "なぜやらないのですか。",
            "今日は失敗です。",
            "これはダメです。",
        ]
        for line in blaming {
            XCTAssertFalse(Guardrails.isClean(line, form: .statement), "弾かれるべき: \(line)")
        }
    }

    func testStreakPhraseNeedsANumberBeforeIt() {
        XCTAssertTrue(Guardrails.containsStreakPhrase("3日連続です"))
        XCTAssertTrue(Guardrails.containsStreakPhrase("３日連続です"))
        XCTAssertTrue(Guardrails.containsStreakPhrase("三日連続です"))
        XCTAssertFalse(Guardrails.containsStreakPhrase("連続して5分だけやる"))
        XCTAssertFalse(Guardrails.containsStreakPhrase("日連続"))
    }

    func testHarmlessSentencesWithPartialMatchesPass() {
        // 単語の部分一致で弾くと落ちてしまう無害な文。
        let harmless = [
            "連続して5分だけやってみよう。",
            "失敗を恐れなくていい。",
            "ダメかもしれないと思っても大丈夫。",
            "逃げたいことをひとつ教えて？",
        ]
        for line in harmless {
            XCTAssertTrue(Guardrails.isClean(line, form: .statement), "通るべき: \(line) → \(Guardrails.check(line, form: .statement))")
        }
    }

    func testAssertiveFormsOnlyForFailureWords() {
        XCTAssertTrue(Guardrails.isClean("失敗しても平気。", form: .statement))
        XCTAssertFalse(Guardrails.isClean("失敗した。", form: .statement))
        XCTAssertFalse(Guardrails.isClean("ダメだったとしても、明日がある。", form: .statement))
    }

    // MARK: - 形式規則

    func testQuestionMustBeShortAndEndWithAQuestionMark() {
        XCTAssertTrue(Guardrails.isClean("どうだった？", form: .question))
        XCTAssertFalse(Guardrails.isClean("どうだった。", form: .question))
        XCTAssertEqual(Guardrails.check("どうだった。", form: .question), [.notQuestion])

        let long = String(repeating: "あ", count: Guardrails.questionLimit) + "？"
        XCTAssertEqual(
            Guardrails.check(long, form: .question),
            [.tooLong(limit: Guardrails.questionLimit, actual: Guardrails.questionLimit + 1)]
        )
    }

    func testActionMustBeShortAndEndWithAVerb() {
        XCTAssertTrue(Guardrails.isClean("メールを開く", form: .action))
        XCTAssertTrue(Guardrails.isClean("1行だけ書く", form: .action))
        XCTAssertTrue(Guardrails.isClean("相手の名前を検索する", form: .action))
        XCTAssertTrue(Guardrails.isClean("必要なものを机に置く", form: .action))
        XCTAssertTrue(Guardrails.isClean("見積書を5分だけ見ます", form: .action))

        XCTAssertFalse(Guardrails.isClean("開くだけ", form: .action))
        XCTAssertEqual(Guardrails.check("開くだけ", form: .action), [.notVerbEnding])
        XCTAssertFalse(Guardrails.isClean("クライアントへの返信", form: .action))

        let long = String(repeating: "あ", count: Guardrails.actionLimit) + "く"
        XCTAssertEqual(
            Guardrails.check(long, form: .action),
            [.tooLong(limit: Guardrails.actionLimit, actual: Guardrails.actionLimit + 1)]
        )
    }

    func testStatementHasNoLengthOrEndingRule() {
        XCTAssertTrue(Guardrails.isClean("じゃあ最後に、自分に約束してください。今日やることを声に出して。", form: .statement))
    }

    func testEmptyUrlAndEnglishOnlyAreRejected() {
        XCTAssertEqual(Guardrails.check("   ", form: .statement), [.empty])
        XCTAssertTrue(Guardrails.check("詳しくは https://example.com を見て。", form: .statement).contains(.containsLink))
        XCTAssertTrue(Guardrails.check("What are you avoiding today?", form: .statement).contains(.noJapanese))
    }

    // MARK: - 置換

    func testSanitizeReplacesViolatingOutputWithTheTemplate() {
        let (clean, replaced) = Guardrails.sanitize("どうだった？", form: .question, fallback: "どう？")
        XCTAssertEqual(clean, "どうだった？")
        XCTAssertFalse(replaced)

        let (fixed, wasReplaced) = Guardrails.sanitize("3日連続で未達成です。", form: .statement, fallback: "どう？")
        XCTAssertEqual(fixed, "どう？")
        XCTAssertTrue(wasReplaced)
    }

    // MARK: - 全文言が通ること

    func testEveryDialogueCopyLinePassesGuardrails() {
        for key in CopyKey.allCases {
            for line in DialogueCopy.variants(key) {
                let filled = DialogueCopy.fill(line, topic: "クライアントへの返信", time: "14時")
                let violations = Guardrails.check(filled, form: line.form)
                XCTAssertTrue(violations.isEmpty, "\(key.rawValue): 「\(filled)」→ \(violations)")
            }
        }
    }

    func testEveryChoiceLabelPassesGuardrails() {
        let ids: [ChoiceID] =
            DialogueCopy.sixOptionIDs
            + DialogueCopy.exampleActionIDs
            + DialogueCopy.timeExampleIDs
            + [.carryoverKeep, .carryoverChange, .differentThing, .declareNow, .declareLater,
               .cannotDecide, .retryInOneHour, .promiseAlive, .changeTime]
            + ReasonCategory.allCases.map { ChoiceID.reason($0) }
            + [CommitmentOutcome.done, .partial, .notYet].map { ChoiceID.status($0) }

        for id in ids {
            let label = DialogueCopy.label(id)
            let violations = Guardrails.check(label, form: .statement)
            XCTAssertTrue(violations.isEmpty, "チップ「\(label)」→ \(violations)")
        }
    }

    func testExampleActionTextsSatisfyTheActionRule() {
        for id in DialogueCopy.exampleActionIDs {
            let action = DialogueCopy.actionText(id)
            XCTAssertNotNil(action, "\(id) に行動文が無い")
            XCTAssertTrue(Guardrails.isClean(action ?? "", form: .action), "行動文「\(action ?? "")」")
        }
    }

    // MARK: - 適用範囲

    func testGuardrailsHaveNoEntryPointForUserTranscripts() {
        // 本人が自分を責める言葉は弾かない。生成文と同じ文でも保存はそのまま通る。
        let blunt = "またサボった"
        XCTAssertFalse(Guardrails.isClean(blunt, form: .statement))

        var transition = FlowMachine.start(FlowEntry(sessionType: .night, hasCommitmentToday: true))
        transition = FlowMachine.handle(.transcript(blunt), in: transition.state)
        XCTAssertEqual(transition.saves.first?.text, blunt, "文字起こしには Guardrails をかけない")
    }
}
