import Foundation
import XCTest

@testable import SaydoCore

final class NoonFlowTests: XCTestCase {

    private func noonEntry(
        mode: InputMode = .voice,
        hasCommitmentToday: Bool = true,
        outcome: CommitmentOutcome = .pending,
        isBeforePlannedTime: Bool = false,
        plannedTimeLabel: String? = "14時",
        isVoicelessDay: Bool = false
    ) -> FlowEntry {
        FlowEntry(
            sessionType: .noon,
            mode: mode,
            hasCommitmentToday: hasCommitmentToday,
            outcome: outcome,
            isBeforePlannedTime: isBeforePlannedTime,
            plannedTimeLabel: plannedTimeLabel,
            isVoicelessDay: isVoicelessDay
        )
    }

    // MARK: - 入口の 3 状態

    func testEntranceClassification() {
        XCTAssertEqual(NoonFlow.entrance(noonEntry(hasCommitmentToday: false)), .shortMorning)
        XCTAssertEqual(NoonFlow.entrance(noonEntry(outcome: .done)), .alreadyDone)
        XCTAssertEqual(NoonFlow.entrance(noonEntry(outcome: .partial)), .alreadyDone)
        XCTAssertEqual(NoonFlow.entrance(noonEntry(outcome: .notYet)), .playback)
        XCTAssertEqual(NoonFlow.entrance(noonEntry(isBeforePlannedTime: true)), .promiseCheck)
        XCTAssertEqual(NoonFlow.entrance(noonEntry()), .playback)
        XCTAssertEqual(
            NoonFlow.entrance(noonEntry(hasCommitmentToday: false, outcome: .done)),
            .shortMorning,
            "宣言が無い日は結果より先に短縮版の朝フローを開く"
        )
    }

    func testNoCommitmentOpensTheShortMorningFlow() {
        var transition = FlowMachine.start(noonEntry(hasCommitmentToday: false))
        XCTAssertEqual(transition.state.sessionType, .morning)
        XCTAssertEqual(transition.state.step, .morningAvoidance)
        XCTAssertTrue(transition.state.isShortMorning)

        transition = FlowMachine.handle(.transcript("請求書の作成"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningMicroAction, "理由（M1）は聞かない")

        transition = FlowMachine.handle(.transcript("テンプレートを開く"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningDeclaration, "時刻（M3）も聞かない")
        XCTAssertEqual(transition.records.map(\.step), [.morningDeclaration])

        transition = FlowMachine.handle(.transcript("今日はテンプレートを開きます"), in: transition.state)
        XCTAssertEqual(transition.saves.map(\.kind), [.declaration])
        XCTAssertTrue(transition.scheduled.filter { $0.kind == .actionTime }.isEmpty, "時刻を聞いていないので行動時刻通知は登録しない")
        XCTAssertEqual(transition.completion, .completed)
    }

    func testAlreadyDoneCancelsNotificationsAndEnds() {
        let transition = FlowMachine.start(noonEntry(outcome: .done))
        XCTAssertEqual(transition.cancelled, [.noonFixed, .actionTime])
        XCTAssertEqual(transition.spoken, ["今日はもう動けてる。"])
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertTrue(transition.saves.isEmpty)
    }

    func testBeforePlannedTimeAsksWhetherThePromiseIsStillAlive() {
        let transition = FlowMachine.start(noonEntry(isBeforePlannedTime: true))
        XCTAssertEqual(transition.choices, [.promiseAlive, .changeTime])
        XCTAssertEqual(transition.spoken, ["14時の約束、まだ生きてる？"])
        XCTAssertTrue(transition.plays.isEmpty, "「どうだった？」も再生も出さない")
    }

    func testPromiseAliveEndsImmediately() {
        var transition = FlowMachine.start(noonEntry(isBeforePlannedTime: true))
        transition = FlowMachine.handle(.choice(.promiseAlive), in: transition.state)
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertTrue(transition.saves.isEmpty)
    }

    func testChangeTimeReschedulesTheActionNotification() {
        var transition = FlowMachine.start(noonEntry(isBeforePlannedTime: true))
        transition = FlowMachine.handle(.choice(.changeTime), in: transition.state)
        XCTAssertTrue(transition.state.isChangingTime)
        XCTAssertEqual(transition.listens.first?.step, .noonStatus)

        transition = FlowMachine.handle(.transcript("17時に自宅で"), in: transition.state)
        XCTAssertEqual(transition.scheduled.map(\.kind), [.actionTime])
        XCTAssertEqual(transition.scheduled.first?.timePhrase, "17時に自宅で")
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertTrue(transition.saves.isEmpty)
    }

    // MARK: - N0

    func testPlaybackPlaysTheDeclarationAudioThenAsksTheStatus() {
        var transition = FlowMachine.start(noonEntry())
        XCTAssertEqual(transition.spoken, ["朝のあなたからです。"])
        XCTAssertEqual(transition.plays.map(\.target), [.declarationAudio])

        transition = FlowMachine.handle(.playbackFinished, in: transition.state)
        XCTAssertEqual(transition.state.step, .noonStatus)
        XCTAssertEqual(transition.choices, [.status(.done), .status(.partial), .status(.notYet)])
    }

    func testVoicelessDayShowsTheDeclarationTextInsteadOfPlayingIt() {
        let transition = FlowMachine.start(noonEntry(isVoicelessDay: true))
        XCTAssertEqual(transition.plays.map(\.target), [.declarationText])
        XCTAssertEqual(transition.spoken, ["朝のあなたからです。"])
    }

    // MARK: - N1

    private func atStatus(_ entry: FlowEntry? = nil) -> FlowState {
        let start = FlowMachine.start(entry ?? noonEntry())
        return FlowMachine.handle(.playbackFinished, in: start.state).state
    }

    func testDoneEndsAndCancelsTheActionNotification() {
        let transition = FlowMachine.handle(.choice(.status(.done)), in: atStatus())
        XCTAssertEqual(transition.state.outcome, .done)
        XCTAssertEqual(transition.saves.map(\.kind), [.status])
        XCTAssertEqual(transition.saves.first?.text, "やった")
        XCTAssertEqual(transition.cancelled, [.actionTime])
        XCTAssertEqual(transition.spoken, ["それを残しておくね。"])
        XCTAssertEqual(transition.completion, .completed)
    }

    func testPartialCountsAsProgressAndDoesNotAskWhatIsBlocking() {
        let transition = FlowMachine.handle(.choice(.status(.partial)), in: atStatus())
        XCTAssertEqual(transition.state.outcome, .partial)
        XCTAssertTrue(transition.state.outcome.isProgress)
        XCTAssertEqual(transition.saves.map(\.kind), [.status])
        XCTAssertEqual(transition.spoken, ["それを今日の前進として残すね。"])
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertNotEqual(transition.state.step, .noonBlocker)
    }

    func testNotYetGoesToTheBlockerQuestion() {
        let transition = FlowMachine.handle(.choice(.status(.notYet)), in: atStatus())
        XCTAssertEqual(transition.state.outcome, .notYet)
        XCTAssertEqual(transition.state.step, .noonBlocker)
        XCTAssertEqual(transition.saves.map(\.kind), [.status])
        XCTAssertNil(transition.completion)
    }

    func testStatusSpokenInTheUsersOwnWordsIsSavedVerbatim() {
        let transition = FlowMachine.handle(.transcript("まだやってません"), in: atStatus())
        XCTAssertEqual(transition.state.outcome, .notYet)
        XCTAssertEqual(transition.saves.first?.text, "まだやってません")
        XCTAssertEqual(transition.saves.first?.hasAudio, true)
    }

    func testStatusKeywordMatching() {
        XCTAssertEqual(NoonFlow.matchOutcome("やりました"), .done)
        XCTAssertEqual(NoonFlow.matchOutcome("やった"), .done)
        XCTAssertNil(NoonFlow.matchOutcome("うーん"))
        XCTAssertEqual(NoonFlow.matchOutcome("少しやった"), .partial)
        XCTAssertEqual(NoonFlow.matchOutcome("まだです"), .notYet)
        XCTAssertEqual(NoonFlow.matchOutcome("メールを送った"), .done)
    }

    func testUnmatchedStatusFallsBackToChoicesAfterTwoRetries() {
        var state = atStatus()
        for _ in 0..<FlowMachine.maxRetries {
            state = FlowMachine.handle(.transcript("うーん"), in: state).state
        }
        let transition = FlowMachine.handle(.transcript("うーん"), in: state)
        XCTAssertEqual(transition.choices, [.status(.done), .status(.partial), .status(.notYet)])
        XCTAssertTrue(transition.listens.isEmpty)
    }

    // MARK: - N2 と N3

    private func atShrink() -> FlowState {
        var state = FlowMachine.handle(.choice(.status(.notYet)), in: atStatus()).state
        state = FlowMachine.handle(.transcript("別の仕事を始めちゃいました"), in: state).state
        return state
    }

    func testBlockerIsSavedAndLeadsToTheShrinkStep() {
        let transition = FlowMachine.handle(.transcript("別の仕事を始めちゃいました"), in: FlowMachine.handle(.choice(.status(.notYet)), in: atStatus()).state)
        XCTAssertEqual(transition.saves.map(\.kind), [.blocker])
        XCTAssertEqual(transition.state.blocker, "別の仕事を始めちゃいました")
        XCTAssertEqual(transition.state.step, .noonShrink)
    }

    func testShrinkStepOffersItsFourChoicesAndTheGeneralExamples() {
        var transition = FlowMachine.handle(.choice(.status(.notYet)), in: atStatus())
        transition = FlowMachine.handle(.transcript("別の仕事を始めちゃいました"), in: transition.state)
        XCTAssertEqual(transition.choices, [.cannotDecide, .retryInOneHour, .dropToday, .moveToTomorrow])
        XCTAssertEqual(transition.listens.first?.examples.map(\.id), DialogueCopy.exampleActionIDs)
    }

    func testShrinkAcceptsTheUsersOwnWords() {
        let transition = FlowMachine.handle(.transcript("メールを開く"), in: atShrink())
        XCTAssertEqual(transition.state.microAction?.text, "メールを開く")
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertTrue(transition.saves.isEmpty, "N3 は VoiceEntry を保存しない")
    }

    func testCannotDecideStepsDownTheLadderAndAsksAgain() {
        var state = atShrink()
        state.microAction = MicroAction(text: "メールを開く")
        let transition = FlowMachine.handle(.choice(.cannotDecide), in: state)
        XCTAssertEqual(transition.state.microAction?.shrinkCount, 1)
        XCTAssertEqual(transition.state.step, .noonShrink)
        XCTAssertNil(transition.completion)
    }

    func testRetryInOneHourReschedulesTheActionNotification() {
        let transition = FlowMachine.handle(.choice(.retryInOneHour), in: atShrink())
        XCTAssertEqual(transition.scheduled.map(\.kind), [.actionTime])
        XCTAssertEqual(transition.scheduled.first?.timePhrase, "1時間後")
        XCTAssertEqual(transition.completion, .completed)
    }

    func testDropTodayCancelsTheActionNotificationWithoutBlame() {
        let transition = FlowMachine.handle(.choice(.dropToday), in: atShrink())
        XCTAssertEqual(transition.cancelled, [.actionTime])
        XCTAssertEqual(transition.completion, .completed)
        for line in transition.spoken {
            XCTAssertTrue(Guardrails.isClean(line, form: .statement), line)
        }
    }

    func testMoveToTomorrowCarriesTheActionOver() {
        var state = atShrink()
        state.microAction = MicroAction(text: "メールを開く")
        let transition = FlowMachine.handle(.choice(.moveToTomorrow), in: state)
        XCTAssertEqual(transition.state.tomorrow, "メールを開く")
        XCTAssertEqual(transition.cancelled, [.actionTime])
        XCTAssertEqual(transition.completion, .completed)
    }

    // MARK: - 中断

    func testInterruptedAtBlockerResumesAtBlocker() {
        let state = FlowMachine.handle(.choice(.status(.notYet)), in: atStatus()).state
        let interrupted = FlowMachine.handle(.interrupted, in: state)
        XCTAssertEqual(interrupted.state.step, .noonBlocker)
        XCTAssertEqual(interrupted.completion, .suspended)

        let resumed = FlowMachine.start(FlowEntry(sessionType: .noon, resume: interrupted.state))
        XCTAssertEqual(resumed.state.step, .noonBlocker)
        XCTAssertEqual(resumed.state.outcome, .notYet)
        XCTAssertEqual(resumed.listens.first?.step, .noonBlocker)
    }

    // MARK: - 手動起動

    func testAdhocSessionUsesTheSameEntranceRules() {
        let transition = FlowMachine.start(
            FlowEntry(sessionType: .adhoc, hasCommitmentToday: true, outcome: .done)
        )
        XCTAssertEqual(transition.spoken, ["今日はもう動けてる。"])
        XCTAssertEqual(transition.cancelled, [.noonFixed, .actionTime])
    }
}
