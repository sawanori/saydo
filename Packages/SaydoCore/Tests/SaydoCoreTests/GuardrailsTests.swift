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

    // MARK: - 適用範囲

    func testGuardrailsHaveNoEntryPointForUserTranscripts() {
        // 本人が自分を責める言葉は、生成文なら弾く。本人の文字起こしを通す入口は `Guardrails` に無い
        // （検査するのは `*Copy` の文言と生成文だけ。本人の言葉はそのまま保存する）。
        let blunt = "またサボった"
        XCTAssertFalse(Guardrails.isClean(blunt, form: .statement))
    }
}
