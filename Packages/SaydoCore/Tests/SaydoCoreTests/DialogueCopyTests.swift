import Foundation
import XCTest

@testable import SaydoCore

final class DialogueCopyTests: XCTestCase {

    // MARK: - 言い換えの数（retention R5）

    func testEightPrimaryLinesHaveFiveOrMoreVariants() {
        XCTAssertEqual(DialogueCopy.primaryKeys.count, 8)
        for key in DialogueCopy.primaryKeys {
            let variants = DialogueCopy.variants(key)
            XCTAssertGreaterThanOrEqual(
                variants.count,
                DialogueCopy.minimumPrimaryVariants,
                "\(key.rawValue) の言い換えが \(variants.count) 件しかない"
            )
            XCTAssertEqual(Set(variants.map(\.text)).count, variants.count, "\(key.rawValue) に重複した言い換えがある")
        }
    }

    func testEveryCopyKeyHasAtLeastOneLine() {
        for key in CopyKey.allCases {
            XCTAssertFalse(DialogueCopy.variants(key).isEmpty, "\(key.rawValue) の文言が空")
        }
    }

    func testPrimaryKeysCoverTheDailyQuestions() {
        XCTAssertEqual(
            DialogueCopy.primaryKeys,
            [
                .morningAvoidanceQuestion,
                .morningReasonQuestion,
                .morningMicroActionQuestion,
                .morningTimePlaceQuestion,
                .morningDeclarationRequest,
                .noonStatusQuestion,
                .noonBlockerQuestion,
                .nightProgressQuestion,
            ]
        )
    }

    // MARK: - 3 日以内に同じ文言を繰り返さない

    func testSameLineIsNotRepeatedWithinThreeDays() {
        for key in DialogueCopy.primaryKeys {
            var picker = CopyPicker()
            var picks: [(day: Int, text: String)] = []
            for day in 0..<12 {
                picker.day = day
                picks.append((day, DialogueCopy.fill(picker.pick(key))))
            }
            for (index, pick) in picks.enumerated() {
                for earlier in picks[0..<index] where earlier.text == pick.text {
                    XCTAssertGreaterThan(
                        pick.day - earlier.day,
                        DialogueCopy.repeatAvoidanceDays,
                        "\(key.rawValue): 「\(pick.text)」が \(earlier.day) 日目と \(pick.day) 日目で繰り返された"
                    )
                }
            }
        }
    }

    func testFirstThreeDaysUseThreeDifferentLines() {
        var picker = CopyPicker()
        var texts: [String] = []
        for day in 0..<3 {
            picker.day = day
            texts.append(picker.pick(.morningAvoidanceQuestion).text)
        }
        XCTAssertEqual(Set(texts).count, 3)
    }

    func testPickerIsDeterministic() {
        var first = CopyPicker(day: 4)
        var second = CopyPicker(day: 4)
        XCTAssertEqual(first.pick(.noonStatusQuestion), second.pick(.noonStatusQuestion))
    }

    func testPickerFallsBackToTheOldestLineWhenEverythingIsRecent() {
        var picker = CopyPicker()
        let variants = DialogueCopy.variants(.morningReasonQuestion)
        // 同じ日にすべての言い換えを使い切る。
        for _ in variants.indices {
            _ = picker.pick(.morningReasonQuestion)
        }
        let extra = picker.pick(.morningReasonQuestion)
        XCTAssertEqual(extra, variants[0], "使い切ったら、いちばん古く使ったものに戻る")
    }

    func testHistoryIsCarriedThroughTheFlowEntry() {
        var picker = CopyPicker(day: 0)
        _ = picker.pick(.morningAvoidanceQuestion)

        let transition = FlowMachine.start(
            FlowEntry(sessionType: .morning, day: 1, copyHistory: picker.history)
        )
        XCTAssertNotEqual(transition.spoken.first, DialogueCopy.variants(.morningAvoidanceQuestion)[0].text)
        XCTAssertEqual(transition.spoken.first, DialogueCopy.variants(.morningAvoidanceQuestion)[1].text)
    }

    // MARK: - 名詞の差し込み

    func testPlaceholdersAreFilledWithTheUsersOwnWords() {
        let line = DialogueCopy.variants(.morningCarryoverQuestion)[0]
        XCTAssertTrue(line.hasPlaceholder)
        let filled = DialogueCopy.fill(line, topic: "見積書")
        XCTAssertTrue(filled.contains("見積書"))
        XCTAssertFalse(filled.contains(DialogueCopy.topicToken))
    }

    func testTimePlaceholderIsFilled() {
        let line = DialogueCopy.variants(.noonBeforePlannedTime)[0]
        let filled = DialogueCopy.fill(line, time: "14時")
        XCTAssertEqual(filled, "14時の約束、まだ生きてる？")
    }

    func testOnlyPlaceholderBearingLinesDeclareThem() {
        let withPlaceholders = CopyKey.allCases.filter { key in
            DialogueCopy.variants(key).contains(where: \.hasPlaceholder)
        }
        XCTAssertEqual(
            Set(withPlaceholders),
            [.morningCarryoverQuestion, .morningDeclarationReceipt, .noonBeforePlannedTime, .noonShrinkPrompt]
        )
    }

    // MARK: - 企画書の原文が残っていること

    func testConceptDocumentLinesArePresent() {
        let texts = DialogueCopy.allLines.map(\.text)
        XCTAssertTrue(texts.contains("おはよう。今日、いちばん逃げたいことは何？"))
        XCTAssertTrue(texts.contains("じゃあ最後に、自分に約束してください。今日やることを声に出して。"))
        XCTAssertTrue(texts.contains("朝のあなたからです。"))
        XCTAssertTrue(texts.contains("どうだった？"))
        XCTAssertTrue(texts.contains("何が止めてる？"))
        XCTAssertTrue(texts.contains("今日、少しでも前に進めたことは？"))
        XCTAssertTrue(texts.contains("それを今日の前進として残します。"))
        XCTAssertTrue(texts.contains("長く考えなくていい。10秒で答えて。"))
        XCTAssertTrue(texts.contains("おかえり。今日から、また一つだけ。"))
        XCTAssertTrue(texts.contains("それは良い日。10秒で終わるね。"))
        XCTAssertTrue(texts.contains("今日はそういう日。明日、もっと小さくしよう。"))
    }

    // MARK: - 選択肢の集合

    func testSixOptionsMatchTheConceptDocument() {
        XCTAssertEqual(
            DialogueCopy.sixOptionIDs.map(DialogueCopy.label),
            ["もっと小さくする", "今日は捨てる", "明日に回す", "誰かに頼る", "期限を決める", "別の方法を考える"]
        )
    }

    func testGeneralExampleChipsAreDomainIndependent() {
        XCTAssertEqual(
            DialogueCopy.exampleActionIDs.map(DialogueCopy.label),
            ["開くだけ", "1行だけ書く", "必要なものを机に置く", "相手の名前を検索する"]
        )
        for label in DialogueCopy.exampleActionIDs.map(DialogueCopy.label) {
            XCTAssertFalse(label.contains("メール"), "分野に依存しない一般形にする: \(label)")
            XCTAssertFalse(label.contains("返信"), "分野に依存しない一般形にする: \(label)")
        }
    }

    func testNoTaskManagementVocabulary() {
        // 企画原則 §22-8: タスク管理アプリの語彙を使わない。
        let banned = ["進捗", "達成率", "完了率", "タスク管理", "未完了"]
        for line in DialogueCopy.allLines {
            for word in banned {
                XCTAssertFalse(line.text.contains(word), "「\(line.text)」に \(word) が入っている")
            }
        }
    }
}
