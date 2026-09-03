import Foundation
import XCTest

@testable import SaydoCore

final class TemplateDialogueEngineTests: XCTestCase {

    private let engine = TemplateDialogueEngine()

    // MARK: - 本人の言葉をそのまま行動文にする

    func testNounUtterancesBecomeVerbEndingActionsWithoutNounExtraction() throws {
        let cases = ["クライアントへの返信", "確定申告", "見積書"]
        for utterance in cases {
            let action = try XCTUnwrap(engine.microAction(fromUtterance: utterance))
            XCTAssertTrue(action.text.hasPrefix(utterance), "本人の言葉が丸ごと残っていない: \(action.text)")
            XCTAssertLessThanOrEqual(action.text.count, Guardrails.actionLimit)
            XCTAssertTrue(Guardrails.endsWithVerb(action.text), action.text)
            XCTAssertTrue(
                Guardrails.isClean(action.text, form: .action),
                "\(action.text) → \(Guardrails.check(action.text, form: .action))"
            )
            XCTAssertTrue(action.isFiveMinutesOrLess)
        }
    }

    func testVerbEndingUtterancesAreKeptExactlyAsSpoken() throws {
        for utterance in ["メールを開く", "資料を1行だけ書く", "必要なものを机に置く", "相手の名前を検索する"] {
            let action = try XCTUnwrap(engine.microAction(fromUtterance: utterance))
            XCTAssertEqual(action.text, utterance)
        }
    }

    func testLongUtteranceIsTrimmedButStillEndsWithAVerb() throws {
        let long = String(repeating: "長い話", count: 20)
        let action = try XCTUnwrap(engine.microAction(fromUtterance: long))
        XCTAssertEqual(action.text.count, Guardrails.actionLimit)
        XCTAssertTrue(Guardrails.isClean(action.text, form: .action), action.text)
        XCTAssertTrue(action.text.hasSuffix(TemplateDialogueEngine.actionSuffix))
    }

    func testTooShortUtteranceIsRejected() {
        XCTAssertNil(engine.microAction(fromUtterance: "あ"))
        XCTAssertNil(engine.microAction(fromUtterance: "  "))
    }

    func testShrinkCountIsCarriedOver() throws {
        let action = try XCTUnwrap(engine.microAction(fromUtterance: "見積書", shrinkCount: 2))
        XCTAssertEqual(action.shrinkCount, 2)
    }

    // MARK: - 例示は一般形で、名詞から作らない

    func testProposedActionsAreTheGeneralExamplesNotDerivedFromTheAvoidance() async throws {
        let actions = try await engine.proposeMicroActions(avoidance: "クライアントへの返信", reason: .awkward)
        XCTAssertEqual(actions.count, 3)
        for action in actions {
            XCTAssertFalse(action.text.contains("クライアント"), "逃げたいことの名詞が混ざっている: \(action.text)")
            XCTAssertFalse(action.text.contains("返信"), "逃げたいことの名詞が混ざっている: \(action.text)")
            XCTAssertTrue(Guardrails.isClean(action.text, form: .action), action.text)
        }

        let other = try await engine.proposeMicroActions(avoidance: "確定申告", reason: .tooMuch)
        XCTAssertEqual(actions.map(\.text), other.map(\.text), "提案は逃げたいことに依らない一般形")
    }

    // MARK: - 理由の分類

    func testReasonKeywordsCoverTheSevenCategories() async throws {
        let samples: [(String, ReasonCategory)] = [
            ("気まずいです", .awkward),
            ("完璧にやりたくて手が止まる", .perfectionism),
            ("面倒です", .tedious),
            ("怒られそうで怖いです", .anxious),
            ("量が多いです", .tooMuch),
            ("何から始めるか分からない", .unclearStart),
            ("期限が近くて怖い", .deadlineFear),
        ]
        for (answer, expected) in samples {
            let classification = try await engine.classifyReason(avoidance: "見積書", answer: answer)
            XCTAssertEqual(classification.category, expected, answer)
            XCTAssertEqual(classification.followUp, "", "Tier B は追加質問を作らない")
        }
        XCTAssertEqual(Set(samples.map(\.1)).count, ReasonCategory.allCases.count)
    }

    func testUnrecognizedReasonThrowsInsteadOfGuessing() async {
        do {
            _ = try await engine.classifyReason(avoidance: "見積書", answer: "うーん")
            XCTFail("分類できないときに値を作ってはいけない")
        } catch {
            XCTAssertEqual(error as? TemplateDialogueEngine.Failure, .reasonNotRecognized)
        }
    }

    func testFollowUpQuestionIsEmptyForTierB() async throws {
        let question = try await engine.followUpQuestion(avoidance: "クライアントへの返信")
        XCTAssertEqual(question, "")
    }

    // MARK: - 分野の分類

    func testDomainKeywords() async throws {
        let samples: [(String, TaskDomain)] = [
            ("クライアントへの返信", .reply),
            ("確定申告", .money),
            ("提案書の営業", .sales),
            ("契約書類の提出", .paperwork),
            ("歯医者の予約", .health),
            ("新しい企画のまとめ", .bigTask),
            ("庭の草むしり", .other),
        ]
        for (avoidance, expected) in samples {
            let domain = try await engine.classifyDomain(avoidance: avoidance)
            XCTAssertEqual(domain, expected, avoidance)
        }
    }

    // MARK: - 縮小

    func testShrinkGoesDownTheGeneralLadder() async throws {
        var action = MicroAction(text: "メールを開く", estimatedMinutes: 5, shrinkCount: 0)
        action = try await engine.shrink(action: action, blocker: "別の仕事を始めてしまった")
        XCTAssertEqual(action.text, ShrinkLadder.rungs[1].actionText)
        XCTAssertEqual(action.shrinkCount, 1)

        action = try await engine.shrink(action: action, blocker: "眠い")
        XCTAssertEqual(action.text, ShrinkLadder.rungs[2].actionText)
    }

    func testShrinkIgnoresTheBlockerWording() async throws {
        let action = MicroAction(text: "メールを開く", estimatedMinutes: 5, shrinkCount: 0)
        let first = try await engine.shrink(action: action, blocker: "会議が続いた")
        let second = try await engine.shrink(action: action, blocker: "気が乗らない")
        XCTAssertEqual(first, second, "段階表は分野にも理由にも依らない")
    }

    // MARK: - 週次の振り返り

    func testWeeklyReflectionStatesWhatAndWhyWithoutScoring() async throws {
        let stats = WeeklyStats(
            weekStart: Date(timeIntervalSince1970: 0),
            domainCounts: [.reply: 3, .money: 1],
            reasonRatios: [.awkward: 0.6, .tedious: 0.4]
        )
        let line = try await engine.weeklyReflection(stats: stats)
        XCTAssertEqual(line, "この1週間、いちばん多いのは人への返信。理由は気まずいが多い。")
        XCTAssertTrue(Guardrails.isClean(line, form: .statement), line)
        for word in ["達成", "率", "頑張", "目標"] {
            XCTAssertFalse(line.contains(word), "評価や激励を書かない: \(line)")
        }
    }

    func testWeeklyReflectionWithoutReasons() async throws {
        let stats = WeeklyStats(weekStart: Date(timeIntervalSince1970: 0), domainCounts: [.paperwork: 2])
        let line = try await engine.weeklyReflection(stats: stats)
        XCTAssertEqual(line, "この1週間、いちばん多いのは書類。")
        XCTAssertTrue(Guardrails.isClean(line, form: .statement))
    }

    func testWeeklyReflectionWithoutData() async throws {
        let line = try await engine.weeklyReflection(stats: WeeklyStats(weekStart: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(line, "まだ、見えてくるほどの記録がない。")
        XCTAssertTrue(Guardrails.isClean(line, form: .statement))
    }

    // MARK: - 契約を LLM なしで満たすこと

    func testEngineConformsToDialogueEngineWithoutAnyModel() async throws {
        let engine: any DialogueEngine = TemplateDialogueEngine()
        _ = try await engine.followUpQuestion(avoidance: "見積書")
        _ = try await engine.proposeMicroActions(avoidance: "見積書", reason: .tedious)
        _ = try await engine.shrink(action: ShrinkLadder.start(), blocker: "時間がない")
        _ = try await engine.classifyDomain(avoidance: "見積書")
        _ = try await engine.weeklyReflection(stats: WeeklyStats(weekStart: Date(timeIntervalSince1970: 0)))
        let classification = try await engine.classifyReason(avoidance: "見積書", answer: "面倒です")
        XCTAssertEqual(classification.category, .tedious)
    }

    // MARK: - FlowMachine が持つ本人の言葉と噛み合うこと

    func testFlowMachineUtteranceBecomesAValidActionText() throws {
        var transition = FlowMachine.start(FlowEntry(sessionType: .morning))
        transition = FlowMachine.handle(.transcript("見積書"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.tedious)), in: transition.state)
        transition = FlowMachine.handle(.transcript("見積書"), in: transition.state)

        let raw = try XCTUnwrap(transition.state.microAction?.text)
        XCTAssertEqual(raw, "見積書", "FlowMachine は本人の言葉をそのまま持つ")

        let formatted = try XCTUnwrap(engine.microAction(fromUtterance: raw))
        XCTAssertTrue(Guardrails.isClean(formatted.text, form: .action), formatted.text)
    }
}
