import Foundation
import XCTest

@testable import SaydoCore

final class NightFlowTests: XCTestCase {

    private func nightEntry(mode: InputMode = .voice, outcome: CommitmentOutcome = .notYet) -> FlowEntry {
        FlowEntry(sessionType: .night, mode: mode, hasCommitmentToday: true, outcome: outcome)
    }

    // MARK: - E0

    func testNightStartsWithTheProgressQuestionAndNoChoices() {
        let transition = FlowMachine.start(nightEntry())
        XCTAssertEqual(transition.state.step, .nightProgress)
        XCTAssertEqual(transition.listens.first?.step, .nightProgress)
        XCTAssertTrue(transition.choiceGroups.isEmpty, "前進があるかどうかを聞く前にチップは出さない")
    }

    func testProgressIsSavedAndLeadsToTomorrow() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("メールは送れなかったけど、文章までは作りました"), in: transition.state)

        XCTAssertEqual(transition.saves.map(\.kind), [.progress])
        XCTAssertEqual(transition.saves.first?.text, "メールは送れなかったけど、文章までは作りました")
        XCTAssertEqual(transition.state.progress, "メールは送れなかったけど、文章までは作りました")
        XCTAssertTrue(transition.spoken.contains("それを今日の前進として残します。"))
        XCTAssertEqual(transition.state.step, .nightTomorrow)
    }

    func testNoProgressShowsExactlyTwoChipsAndNoBlame() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("何もできなかった"), in: transition.state)

        XCTAssertEqual(transition.choices, [.shrinkMore, .moveToTomorrow])
        XCTAssertEqual(transition.choices.count, 2)
        XCTAssertTrue(transition.spoken.contains("今日はそういう日。明日、もっと小さくしよう。"))
        XCTAssertEqual(transition.state.step, .nightProgress)
        for line in transition.spoken {
            XCTAssertTrue(Guardrails.isClean(line, form: .statement), line)
        }
    }

    func testNoProgressDoesNotUseTheSixOptions() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("ない"), in: transition.state)
        XCTAssertNotEqual(Set(transition.choices), Set(DialogueCopy.sixOptionIDs))
        XCTAssertEqual(transition.choices.count, 2, "6 選択肢は夜 E0 では出さない")
    }

    func testNoProgressStillKeepsTheUsersOwnWords() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("何もできなかった"), in: transition.state)
        XCTAssertEqual(transition.saves.map(\.kind), [.progress])
        XCTAssertEqual(transition.saves.first?.text, "何もできなかった")
        XCTAssertNil(transition.state.progress, "前進としては記録しない")
    }

    func testNoProgressChoiceMovesOnToTomorrow() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("ない"), in: transition.state)
        transition = FlowMachine.handle(.choice(.shrinkMore), in: transition.state)
        XCTAssertEqual(transition.state.nightDecision, .shrinkMore)
        XCTAssertEqual(transition.state.step, .nightTomorrow)
    }

    func testSilenceAtProgressSkipsToTomorrowWithoutSaving() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.spoken, ["長く考えなくていい。10秒で答えて。"])
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .nightTomorrow)
        XCTAssertTrue(transition.saves.isEmpty)
    }

    // MARK: - E1

    func testTomorrowIsSavedAndHandedToTheNextMorning() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("文章までは作りました"), in: transition.state)
        transition = FlowMachine.handle(.transcript("明日は午前中に送ります"), in: transition.state)

        XCTAssertEqual(transition.saves.map(\.kind), [.tomorrow])
        XCTAssertEqual(transition.state.tomorrow, "明日は午前中に送ります")
        XCTAssertEqual(transition.spoken.last, "明日の朝、聞くね。")
        XCTAssertEqual(transition.completion, .completed)
    }

    func testCarryoverFromNightBecomesTheNextMorningQuestion() {
        var night = FlowMachine.start(nightEntry())
        night = FlowMachine.handle(.transcript("文章までは作りました"), in: night.state)
        night = FlowMachine.handle(.transcript("明日は午前中に送ります"), in: night.state)

        let morning = FlowMachine.start(
            FlowEntry(sessionType: .morning, carryover: night.state.tomorrow)
        )
        XCTAssertEqual(morning.choices, [.carryoverKeep, .carryoverChange])
        XCTAssertTrue(morning.spoken.first?.contains("明日は午前中に送ります") == true, morning.spoken.first ?? "")
    }

    // MARK: - 中断とタイムボックス

    func testInterruptedAtTomorrowResumesAtTomorrow() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.transcript("文章までは作りました"), in: transition.state)
        let interrupted = FlowMachine.handle(.interrupted, in: transition.state)
        XCTAssertEqual(interrupted.state.step, .nightTomorrow)

        let resumed = FlowMachine.start(FlowEntry(sessionType: .night, resume: interrupted.state))
        XCTAssertEqual(resumed.state.step, .nightTomorrow)
        XCTAssertEqual(resumed.state.progress, "文章までは作りました")
    }

    func testTimeboxClosesTheNightSession() {
        var transition = FlowMachine.start(nightEntry())
        transition = FlowMachine.handle(.timeout(.timebox), in: transition.state)
        XCTAssertEqual(transition.completion, .timeboxExceeded)
        XCTAssertEqual(transition.spoken, ["続きは昼に聞くね。"])
    }

    // MARK: - 「話せない時」モード

    func testVoicelessNightUsesTextInput() {
        var transition = FlowMachine.start(nightEntry(mode: .text))
        XCTAssertEqual(transition.listens.first?.input, .text)
        transition = FlowMachine.handle(.transcript("資料は開けました"), in: transition.state)
        XCTAssertEqual(transition.saves.first?.hasAudio, false)
    }
}
