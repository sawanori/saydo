import Foundation
import XCTest

@testable import SaydoCore

/// 命令列を読みやすくするための取り出し（このテストターゲット全体で使う）。
extension FlowTransition {
    var spoken: [String] {
        commands.compactMap { command in
            if case .speak(let text) = command { text } else { nil }
        }
    }

    var saves: [SaveInstruction] {
        commands.compactMap { command in
            if case .save(let instruction) = command { instruction } else { nil }
        }
    }

    var listens: [ListenRequest] {
        commands.compactMap { command in
            if case .listen(let request) = command { request } else { nil }
        }
    }

    var records: [RecordRequest] {
        commands.compactMap { command in
            if case .record(let request) = command { request } else { nil }
        }
    }

    var plays: [PlaybackRequest] {
        commands.compactMap { command in
            if case .play(let request) = command { request } else { nil }
        }
    }

    var choiceGroups: [[ChoiceID]] {
        commands.compactMap { command in
            if case .showChoices(let choices) = command { choices.map(\.id) } else { nil }
        }
    }

    var choices: [ChoiceID] { choiceGroups.flatMap { $0 } }

    var scheduled: [NotificationRequest] {
        commands.compactMap { command in
            if case .scheduleNotification(let request) = command { request } else { nil }
        }
    }

    var cancelled: [NotificationRequest.Kind] {
        commands.compactMap { command in
            if case .cancelNotification(let kind) = command { kind } else { nil }
        }
    }

    var completion: FlowCompletion? {
        commands.compactMap { command in
            if case .finish(let completion) = command { completion } else { nil }
        }.first
    }
}

final class MorningFlowTests: XCTestCase {

    private func morningEntry(
        mode: InputMode = .voice,
        carryover: String? = nil,
        daysSinceLastRecord: Int? = nil
    ) -> FlowEntry {
        FlowEntry(
            sessionType: .morning,
            mode: mode,
            carryover: carryover,
            daysSinceLastRecord: daysSinceLastRecord
        )
    }

    // MARK: - 正常経路

    func testMorningWalksM0ToM4AndSavesThreeEntries() {
        var transition = FlowMachine.start(morningEntry())
        XCTAssertEqual(transition.state.step, .morningAvoidance)
        XCTAssertEqual(transition.listens.first?.step, .morningAvoidance)
        XCTAssertTrue(transition.choiceGroups.isEmpty, "M0 は選択肢を出さない")

        var saved: [VoiceEntryKind] = []

        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.state.step, .morningReason)
        XCTAssertEqual(transition.state.avoidance, "クライアントへの返信")

        transition = FlowMachine.handle(.choice(.reason(.awkward)), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.state.step, .morningMicroAction)
        XCTAssertEqual(transition.state.reason, .awkward)

        transition = FlowMachine.handle(.transcript("メールを開く"), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.state.step, .morningPlannedTime)
        XCTAssertEqual(transition.state.microAction?.text, "メールを開く")
        XCTAssertTrue(transition.saves.isEmpty, "M2 は VoiceEntry を保存しない")

        transition = FlowMachine.handle(.transcript("14時に自宅で"), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertEqual(transition.state.plannedAnswer, "14時に自宅で")
        XCTAssertEqual(transition.records.first?.maxSeconds, FlowMachine.declarationMaxSeconds)

        transition = FlowMachine.handle(.transcript("今日は14時にメールを開きます"), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertEqual(transition.scheduled.map(\.kind), [.actionTime])
        XCTAssertEqual(transition.scheduled.first?.timePhrase, "14時に自宅で")

        XCTAssertEqual(saved, [.avoidance, .reason, .declaration])
    }

    func testMicroActionKeepsUserWordsWithoutNounExtraction() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("確定申告"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.tedious)), in: transition.state)
        transition = FlowMachine.handle(.transcript("必要な書類を机に出す"), in: transition.state)
        XCTAssertEqual(transition.state.microAction?.text, "必要な書類を机に出す")
    }

    func testMicroActionExampleChipUsesActionTextNotLabel() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("見積書"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.unclearStart)), in: transition.state)

        XCTAssertEqual(transition.listens.first?.examples.map(\.id), DialogueCopy.exampleActionIDs)
        XCTAssertTrue(transition.choiceGroups.isEmpty, "M2 の一般形 4 つは例示であって選択肢ではない")

        transition = FlowMachine.handle(.choice(.exampleOpen), in: transition.state)
        XCTAssertEqual(DialogueCopy.label(.exampleOpen), "開くだけ")
        XCTAssertEqual(transition.state.microAction?.text, "開く")
        XCTAssertTrue(Guardrails.isClean(transition.state.microAction?.text ?? "", form: .action))
    }

    func testPlannedTimeAsksTimeAndPlaceInOneQuestion() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("見積書"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.tooMuch)), in: transition.state)
        transition = FlowMachine.handle(.transcript("フォルダを開く"), in: transition.state)

        XCTAssertEqual(transition.state.step, .morningPlannedTime)
        let question = transition.spoken.first ?? ""
        XCTAssertTrue(question.contains("何時") || question.contains("いつ"), question)
        XCTAssertTrue(question.contains("どこ"), question)
        XCTAssertTrue(transition.choiceGroups.isEmpty, "M3 は選択肢を出さない")
        XCTAssertEqual(transition.listens.first?.examples.map(\.id), DialogueCopy.timeExampleIDs)
    }

    // MARK: - M0 の分岐

    func testNothingToAvoidEndsAsGoodDay() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("特にない"), in: transition.state)

        XCTAssertTrue(transition.state.isGoodDay)
        XCTAssertEqual(transition.completion, .goodDay)
        XCTAssertEqual(transition.saves.map(\.kind), [.avoidance])
        XCTAssertEqual(transition.spoken.last, "それは良い日。10秒で終わるね。")
        XCTAssertTrue(transition.scheduled.isEmpty)
    }

    func testCarryoverIsOfferedWithTwoChoicesAndKeepingItSkipsTheQuestion() {
        var transition = FlowMachine.start(morningEntry(carryover: "見積書"))
        XCTAssertEqual(transition.choices, [.carryoverKeep, .carryoverChange])
        XCTAssertTrue(transition.spoken.first?.contains("見積書") == true, transition.spoken.first ?? "")

        transition = FlowMachine.handle(.choice(.carryoverKeep), in: transition.state)
        XCTAssertEqual(transition.state.avoidance, "見積書")
        XCTAssertEqual(transition.saves.map(\.kind), [.avoidance])
        XCTAssertEqual(transition.saves.first?.hasAudio, false)
        XCTAssertEqual(transition.state.step, .morningReason)
    }

    func testCarryoverChangeShowsTheSixOptions() {
        var transition = FlowMachine.start(morningEntry(carryover: "見積書"))
        transition = FlowMachine.handle(.choice(.carryoverChange), in: transition.state)
        XCTAssertEqual(transition.choices, DialogueCopy.sixOptionIDs)
        XCTAssertEqual(DialogueCopy.sixOptionIDs.count, 6)
    }

    func testCarryoverDroppedAsksForTodaysAvoidanceInstead() {
        var transition = FlowMachine.start(morningEntry(carryover: "見積書"))
        transition = FlowMachine.handle(.choice(.carryoverChange), in: transition.state)
        transition = FlowMachine.handle(.choice(.dropToday), in: transition.state)

        XCTAssertEqual(transition.state.step, .morningAvoidance)
        XCTAssertNil(transition.state.carryover)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertEqual(transition.listens.first?.step, .morningAvoidance)
    }

    func testCarryoverMovedToTomorrowKeepsItForTheNextMorning() {
        var transition = FlowMachine.start(morningEntry(carryover: "見積書"))
        transition = FlowMachine.handle(.choice(.carryoverChange), in: transition.state)
        transition = FlowMachine.handle(.choice(.moveToTomorrow), in: transition.state)

        XCTAssertEqual(transition.state.tomorrow, "見積書")
        XCTAssertEqual(transition.state.step, .morningAvoidance)
    }

    // MARK: - 空白後の再入場（retention R4）

    func testReentryAfterTwoOrMoreDaysUsesTheWelcomeBackLine() {
        let transition = FlowMachine.start(morningEntry(daysSinceLastRecord: 5))
        XCTAssertEqual(transition.spoken.first, "おかえり。今日から、また一つだけ。")
        for line in transition.spoken {
            XCTAssertFalse(line.contains("連続"), "連続日数に言及しない: \(line)")
            XCTAssertFalse(line.contains("ぶり"), "空白日数に言及しない: \(line)")
            XCTAssertFalse(line.contains("空い"), "空白日数に言及しない: \(line)")
            XCTAssertNil(line.range(of: "[0-9０-９]+日", options: .regularExpression), "空白日数に言及しない: \(line)")
        }
    }

    func testNoReentryLineWhenTheGapIsOneDay() {
        let transition = FlowMachine.start(morningEntry(daysSinceLastRecord: 1))
        XCTAssertFalse(transition.spoken.contains("おかえり。今日から、また一つだけ。"))
    }

    // MARK: - 沈黙とスキップ

    func testSilenceNudgesOnceThenSkipsTheQuestion() {
        var transition = FlowMachine.start(morningEntry())
        XCTAssertEqual(transition.listens.first?.silenceSeconds, FlowMachine.firstSilenceSeconds)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.spoken, ["長く考えなくていい。10秒で答えて。"])
        XCTAssertEqual(transition.listens.first?.silenceSeconds, FlowMachine.secondSilenceSeconds)
        XCTAssertEqual(transition.state.step, .morningAvoidance)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningReason, "2 回目の沈黙でその質問をスキップする")
        XCTAssertEqual(transition.state.silenceCount, 0)
    }

    func testSkipEventAdvancesWithoutSaving() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.skip, in: transition.state)
        XCTAssertEqual(transition.state.step, .morningReason)
        XCTAssertTrue(transition.saves.isEmpty)
    }

    // MARK: - 再入力の上限

    func testShortTranscriptRetriesTwiceThenFallsBackToChoices() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningReason)

        transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        XCTAssertEqual(transition.state.retryCount, 1)
        XCTAssertEqual(transition.spoken, ["もう一度、ゆっくりで大丈夫。"])
        XCTAssertEqual(transition.listens.count, 1)

        transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        XCTAssertEqual(transition.state.retryCount, 2)

        transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        XCTAssertEqual(transition.state.retryCount, FlowMachine.maxRetries)
        XCTAssertEqual(transition.choices.count, ReasonCategory.allCases.count, "上限を超えたら選択肢に落とす")
        XCTAssertTrue(transition.listens.isEmpty)
        XCTAssertEqual(transition.state.step, .morningReason)
    }

    func testShortTranscriptSkipsWhenTheStepHasNoAnswerChoices() {
        var transition = FlowMachine.start(morningEntry())
        for _ in 0..<(FlowMachine.maxRetries + 1) {
            transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        }
        XCTAssertEqual(transition.state.step, .morningReason, "選択肢が無いステップはスキップする")
    }

    // MARK: - 「話せない時」モード（retention R1）

    func testVoicelessModeListensWithTextInputThroughM0ToM3() {
        var transition = FlowMachine.start(morningEntry(mode: .text))
        XCTAssertEqual(transition.listens.first?.input, .text)

        transition = FlowMachine.handle(.transcript("上司への報告"), in: transition.state)
        XCTAssertEqual(transition.saves.first?.hasAudio, false)
        XCTAssertEqual(transition.listens.first?.input, .text)

        transition = FlowMachine.handle(.choice(.reason(.anxious)), in: transition.state)
        XCTAssertEqual(transition.listens.first?.input, .text)

        transition = FlowMachine.handle(.transcript("資料を開く"), in: transition.state)
        XCTAssertEqual(transition.listens.first?.input, .text)

        transition = FlowMachine.handle(.transcript("15時に会社で"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertEqual(transition.choices, [.declareNow, .declareLater], "M4 だけ声に回せる")
        XCTAssertTrue(transition.records.isEmpty)
    }

    func testDeferredDeclarationSchedulesASingleReminder() {
        var transition = FlowMachine.start(morningEntry(mode: .text))
        transition = FlowMachine.handle(.transcript("上司への報告"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.anxious)), in: transition.state)
        transition = FlowMachine.handle(.transcript("資料を開く"), in: transition.state)
        transition = FlowMachine.handle(.transcript("15時に会社で"), in: transition.state)

        transition = FlowMachine.handle(.choice(.declareLater), in: transition.state)
        XCTAssertTrue(transition.state.isDeclarationDeferred)
        XCTAssertEqual(transition.listens.first?.input, .text)

        transition = FlowMachine.handle(.transcript("15時に資料を開きます"), in: transition.state)
        XCTAssertEqual(transition.saves.map(\.kind), [.declaration])
        XCTAssertEqual(transition.saves.first?.hasAudio, false)
        let reminders = transition.scheduled.filter { $0.kind == .declarationReminder }
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.onlyOnce, true)
        XCTAssertEqual(transition.completion, .completed)
    }

    func testDeclareNowInVoicelessModeStartsRecording() {
        var transition = FlowMachine.start(morningEntry(mode: .text))
        transition = FlowMachine.handle(.transcript("上司への報告"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.anxious)), in: transition.state)
        transition = FlowMachine.handle(.transcript("資料を開く"), in: transition.state)
        transition = FlowMachine.handle(.transcript("15時に会社で"), in: transition.state)
        transition = FlowMachine.handle(.choice(.declareNow), in: transition.state)

        XCTAssertEqual(transition.records.map(\.step), [.morningDeclaration])
        XCTAssertFalse(transition.state.isDeclarationDeferred)
    }

    // MARK: - 中断と再開

    func testInterruptedKeepsTheStepAndResumesFromIt() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.awkward)), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningMicroAction)

        let interrupted = FlowMachine.handle(.interrupted, in: transition.state)
        XCTAssertEqual(interrupted.completion, .suspended)
        XCTAssertTrue(interrupted.state.isSuspended)
        XCTAssertEqual(interrupted.state.step, .morningMicroAction)
        XCTAssertTrue(interrupted.saves.isEmpty)

        let resumed = FlowMachine.start(FlowEntry(sessionType: .morning, resume: interrupted.state))
        XCTAssertEqual(resumed.state.step, .morningMicroAction)
        XCTAssertFalse(resumed.state.isSuspended)
        XCTAssertEqual(resumed.state.avoidance, "クライアントへの返信")
        XCTAssertEqual(resumed.state.reason, .awkward)
        XCTAssertEqual(resumed.listens.first?.step, .morningMicroAction)
    }

    func testInterruptedAtDeclarationResumesAtDeclaration() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("確定申告"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.tooMuch)), in: transition.state)
        transition = FlowMachine.handle(.transcript("書類を出す"), in: transition.state)
        transition = FlowMachine.handle(.transcript("20時に自宅で"), in: transition.state)
        let interrupted = FlowMachine.handle(.interrupted, in: transition.state)
        XCTAssertEqual(interrupted.state.step, .morningDeclaration)

        let resumed = FlowMachine.start(FlowEntry(sessionType: .morning, resume: interrupted.state))
        XCTAssertEqual(resumed.state.step, .morningDeclaration)
        XCTAssertEqual(resumed.records.map(\.step), [.morningDeclaration])
        XCTAssertEqual(resumed.state.plannedAnswer, "20時に自宅で")
    }

    // MARK: - タイムボックス

    func testTimeboxSavesNothingMoreAndClosesTheSession() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        transition = FlowMachine.handle(.timeout(.timebox), in: transition.state)

        XCTAssertEqual(transition.spoken, ["続きは昼に聞くね。"])
        XCTAssertEqual(transition.completion, .timeboxExceeded)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertTrue(transition.state.isFinished)
    }

    // MARK: - ユーザーの言葉には Guardrails をかけない

    func testUserTranscriptIsSavedVerbatimEvenWhenItBlamesThemselves() {
        var transition = FlowMachine.start(morningEntry())
        let blunt = "またサボってしまいそうな見積書"
        XCTAssertFalse(Guardrails.isClean(blunt, form: .statement), "生成文なら弾かれる文であること")

        transition = FlowMachine.handle(.transcript(blunt), in: transition.state)
        XCTAssertEqual(transition.saves.first?.text, blunt)
        XCTAssertEqual(transition.state.avoidance, blunt)
    }

    // MARK: - 保存の 1 対 1

    func testOnlySevenStepsProduceVoiceEntries() {
        let mapped = FlowStep.allCases.compactMap { step in
            VoiceEntryKind.kind(for: step).map { (step, $0) }
        }
        XCTAssertEqual(mapped.count, 7)
        XCTAssertEqual(
            mapped.map(\.0),
            [.morningAvoidance, .morningReason, .morningDeclaration, .noonStatus, .noonBlocker, .nightProgress, .nightTomorrow]
        )
        XCTAssertEqual(Set(mapped.map(\.1)).count, VoiceEntryKind.allCases.count)
    }
}
