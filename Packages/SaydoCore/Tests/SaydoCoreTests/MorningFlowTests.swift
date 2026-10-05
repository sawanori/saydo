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

    var commits: [CommitRequest] {
        commands.compactMap { command in
            if case .commit(let request) = command { request } else { nil }
        }
    }

    var completion: FlowCompletion? {
        commands.compactMap { command in
            if case .finish(let completion) = command { completion } else { nil }
        }.first
    }
}

final class MorningFlowTests: XCTestCase {

    /// アプリ側が返す、解釈済みの時刻（中身はこのテストでは問わない）。
    private let twoPM = ResolvedTime(date: Date(timeIntervalSince1970: 1_790_000_000), phrase: "14時", place: "自宅")

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

        // M3 の答えは、アプリに解釈を頼んで結果を待つ（task_034）。M4 へはその結果で進む。
        transition = FlowMachine.handle(.transcript("14時に自宅で"), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.state.step, .morningPlannedTime)
        XCTAssertEqual(transition.state.plannedAnswer, "14時に自宅で")
        XCTAssertEqual(transition.commands, [.resolveTime("14時に自宅で")])

        transition = FlowMachine.handle(.timeResolved(twoPM), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertEqual(transition.state.plannedTime, twoPM)
        XCTAssertEqual(transition.records.first?.maxSeconds, FlowMachine.declarationMaxSeconds)

        // M4 の宣言は、アプリに約束の保存と通知の登録を頼んで結果を待つ（task_035）。会話はその結果で終わる。
        transition = FlowMachine.handle(.transcript("今日は14時にメールを開きます"), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertNil(transition.completion)
        XCTAssertEqual(transition.commits.map(\.plannedTime), [twoPM])
        XCTAssertTrue(transition.scheduled.isEmpty, "行動時刻の通知は commit の中でアプリが登録する")

        transition = FlowMachine.handle(.commitResult(.scheduled), in: transition.state)
        saved += transition.saves.map(\.kind)
        XCTAssertEqual(transition.completion, .completed)

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

    // MARK: - M3 の時刻の解釈（task_034）

    /// M3 の答えは生の発話のまま `plannedAnswer` に残し、解釈はアプリに頼む。結果が来るまで M4 へ進まない。
    func testPlannedTimeAnswerAsksTheAppToResolveIt() {
        let transition = FlowMachine.handle(.transcript(" 16時から "), in: morning(at: .morningPlannedTime).state)

        XCTAssertEqual(transition.commands, [.resolveTime("16時から")])
        XCTAssertEqual(transition.state.step, .morningPlannedTime)
        XCTAssertEqual(transition.state.plannedAnswer, "16時から")
        XCTAssertNil(transition.state.plannedTime)
    }

    /// 解釈できた値は `plannedTime` に入り、宣言へ進む。
    func testResolvedTimeIsKeptAndTheDeclarationFollows() {
        var transition = FlowMachine.handle(.transcript("16時から"), in: morning(at: .morningPlannedTime).state)
        let resolved = ResolvedTime(date: Date(timeIntervalSince1970: 1_790_007_200), phrase: "16時", place: nil)
        transition = FlowMachine.handle(.timeResolved(resolved), in: transition.state)

        XCTAssertEqual(transition.state.plannedTime, resolved)
        XCTAssertEqual(transition.state.plannedAnswer, "16時から")
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertEqual(transition.records.map(\.step), [.morningDeclaration])
        XCTAssertTrue(transition.choiceGroups.isEmpty)
    }

    /// 解釈できなかったら、時刻のチップを出して 1 回だけ聞き直す。2 回目も駄目なら時刻なしで宣言へ進む。
    func testUnresolvedTimeShowsTheTimeChipsOnceThenGoesOnWithoutATime() {
        var transition = FlowMachine.handle(.transcript("あとでやる"), in: morning(at: .morningPlannedTime).state)
        XCTAssertEqual(transition.commands, [.resolveTime("あとでやる")])

        transition = FlowMachine.handle(.timeResolved(nil), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningPlannedTime, "聞き直しのあいだは M3 に留まる")
        XCTAssertEqual(transition.choiceGroups, [DialogueCopy.timeChipIDs])
        XCTAssertEqual(
            DialogueCopy.timeChipIDs.map(DialogueCopy.label),
            ["30分後", "昼", "夕方", "決めない"]
        )
        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.morningTimeChipsPrompt).prefix(1).map(\.text))
        XCTAssertEqual(transition.listens.map(\.step), [.morningPlannedTime], "声でも答えられる")
        XCTAssertNil(transition.state.plannedTime)
        XCTAssertNil(transition.completion)

        // 声で答え直す。同じ経路で解釈を頼む。
        transition = FlowMachine.handle(.transcript("そのうち"), in: transition.state)
        XCTAssertEqual(transition.commands, [.resolveTime("そのうち")])
        XCTAssertEqual(transition.state.plannedAnswer, "そのうち")

        // 2 回目も解釈できない。もう聞き直さず、時刻なしで宣言へ進む。
        transition = FlowMachine.handle(.timeResolved(nil), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertNil(transition.state.plannedTime)
        XCTAssertTrue(transition.choiceGroups.isEmpty, "チップをもう一度は出さない")
        XCTAssertEqual(transition.records.map(\.step), [.morningDeclaration])
    }

    /// 「決めない」を選ぶと、時刻なしのまま宣言へ進む。解釈は頼まない。
    func testChoosingUndecidedGoesOnWithoutATime() {
        var transition = FlowMachine.handle(.transcript("あとでやる"), in: morning(at: .morningPlannedTime).state)
        transition = FlowMachine.handle(.timeResolved(nil), in: transition.state)

        transition = FlowMachine.handle(.choice(.timeUndecided), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertNil(transition.state.plannedTime)
        XCTAssertFalse(transition.commands.contains { if case .resolveTime = $0 { true } else { false } })
        XCTAssertEqual(transition.records.map(\.step), [.morningDeclaration])
    }

    /// 時刻のチップ（「決めない」以外）は、その文言を同じ経路で解釈に回す。
    func testChoosingATimeChipIsResolvedThroughTheSameRoute() {
        for id in [ChoiceID.timeInThirtyMinutes, .timeNoon, .timeEvening] {
            var transition = FlowMachine.handle(.transcript("あとでやる"), in: morning(at: .morningPlannedTime).state)
            transition = FlowMachine.handle(.timeResolved(nil), in: transition.state)

            transition = FlowMachine.handle(.choice(id), in: transition.state)
            XCTAssertEqual(transition.commands, [.resolveTime(DialogueCopy.label(id))], "\(id)")
            XCTAssertEqual(transition.state.step, .morningPlannedTime, "\(id)")

            let resolved = ResolvedTime(date: Date(timeIntervalSince1970: 1_790_010_000), phrase: DialogueCopy.label(id))
            transition = FlowMachine.handle(.timeResolved(resolved), in: transition.state)
            XCTAssertEqual(transition.state.plannedTime, resolved, "\(id)")
            XCTAssertEqual(transition.state.step, .morningDeclaration, "\(id)")
        }
    }

    /// 聞き直しのあいだの沈黙とスキップは、M3 が必須でないので時刻なしで宣言へ進む。
    func testSilenceOrSkipWhileReaskingTheTimeGoesOnWithoutATime() {
        var asked = FlowMachine.handle(.transcript("あとでやる"), in: morning(at: .morningPlannedTime).state)
        asked = FlowMachine.handle(.timeResolved(nil), in: asked.state)

        let skipped = FlowMachine.handle(.skip, in: asked.state)
        XCTAssertEqual(skipped.state.step, .morningDeclaration)
        XCTAssertNil(skipped.state.plannedTime)

        var silent = FlowMachine.handle(.timeout(.silence), in: asked.state)
        XCTAssertEqual(silent.state.step, .morningPlannedTime)
        silent = FlowMachine.handle(.timeout(.silence), in: silent.state)
        XCTAssertEqual(silent.state.step, .morningDeclaration)
        XCTAssertNil(silent.state.plannedTime)
        XCTAssertNil(silent.state.timeResolution)
    }

    /// 最初の質問の時刻の例（「1時間後」など）も、その文言を同じ経路で解釈に回す。
    func testTimeExampleIsResolvedThroughTheSameRoute() {
        let transition = FlowMachine.handle(.choice(.timeInOneHour), in: morning(at: .morningPlannedTime).state)
        XCTAssertEqual(transition.commands, [.resolveTime("1時間後")])
        XCTAssertEqual(transition.state.plannedAnswer, "1時間後")
        XCTAssertEqual(transition.state.step, .morningPlannedTime)
    }

    /// 解釈の結果は、頼んだときにだけ受ける。頼んでいない結果は受け流す。
    func testTimeResolvedIsIgnoredUnlessItWasAskedFor() {
        let atTime = morning(at: .morningPlannedTime)
        let stray = FlowMachine.handle(.timeResolved(twoPM), in: atTime.state)
        XCTAssertTrue(stray.commands.isEmpty)
        XCTAssertEqual(stray.state, atTime.state)

        let atDeclaration = morning(at: .morningDeclaration)
        let late = FlowMachine.handle(.timeResolved(nil), in: atDeclaration.state)
        XCTAssertTrue(late.commands.isEmpty)
        XCTAssertEqual(late.state.plannedTime, twoPM)
    }

    /// 短縮版の朝フローは時刻を聞かないので、解釈も頼まない。
    func testShortMorningNeverAsksToResolveATime() {
        var transition = FlowMachine.start(FlowEntry(sessionType: .noon, hasCommitmentToday: false))
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        transition = FlowMachine.handle(.transcript("メールを開く"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertNil(transition.state.plannedTime)
        XCTAssertFalse(transition.commands.contains { if case .resolveTime = $0 { true } else { false } })
    }

    /// 追加したプロパティを持たない保存済みの状態（task_034 より前の形）も読める。
    func testFlowStateWithoutThePlannedTimeStillDecodes() throws {
        let before = morning(at: .morningMicroAction).state
        let data = try JSONEncoder().encode(before)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        XCTAssertFalse(keys.contains("plannedTime"))
        XCTAssertFalse(keys.contains("timeResolution"))
        XCTAssertEqual(try JSONDecoder().decode(FlowState.self, from: data), before)

        let after = morning(at: .morningDeclaration).state
        XCTAssertEqual(try JSONDecoder().decode(FlowState.self, from: JSONEncoder().encode(after)).plannedTime, twoPM)
    }

    // MARK: - M4 の約束の保存と受領文（task_035）

    /// 朝の会話を M4 の宣言まで答えた直後の遷移。時刻の答えと解釈結果は引数で変える。
    private func declared(
        timeAnswer: String = "14時に自宅で",
        resolved: ResolvedTime?,
        declaration: String = "今日はメールを開きます"
    ) -> FlowTransition {
        var transition = FlowMachine.handle(.transcript(timeAnswer), in: morning(at: .morningPlannedTime).state)
        transition = FlowMachine.handle(.timeResolved(resolved), in: transition.state)
        if resolved == nil {
            // 聞き直しで「決めない」を選んで、時刻なしで宣言へ進む。
            transition = FlowMachine.handle(.choice(.timeUndecided), in: transition.state)
        }
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        return FlowMachine.handle(.transcript(declaration), in: transition.state)
    }

    /// どの受領文も、この言葉で始まる。
    private var receiptOpening: String { "受け取りました" }

    /// 宣言を受けたら、宣言の保存と `commit` だけを出す。この時点では受領文も読まず、会話も終えない。
    func testDeclarationAsksTheAppToCommitAndSaysNothingYet() {
        let transition = declared(resolved: twoPM)

        XCTAssertEqual(
            transition.commands,
            [
                .save(SaveInstruction(kind: .declaration, step: .morningDeclaration, text: "今日はメールを開きます", hasAudio: true)),
                .commit(CommitRequest(
                    avoidance: "クライアントへの返信",
                    microAction: MicroAction(text: "メールを開く"),
                    declaration: "今日はメールを開きます",
                    plannedTime: twoPM,
                    isDeclarationDeferred: false
                )),
            ]
        )
        XCTAssertTrue(transition.spoken.isEmpty, "結果を受けるまで「受け取りました」と言わない")
        XCTAssertNil(transition.completion)
        XCTAssertFalse(transition.state.isFinished)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertEqual(transition.state.commitStage, .awaitingFirst)
    }

    /// 保存でき、通知も登録できたときだけ「◯時に…届きます」と言う。時刻は整えた句を使う。
    func testScheduledResultReadsTheReceiptWithTheResolvedPhrase() {
        let transition = FlowMachine.handle(.commitResult(.scheduled), in: declared(resolved: twoPM).state)

        XCTAssertEqual(transition.spoken, ["受け取りました。14時に、朝のあなたから届きます。"])
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertTrue(transition.state.isFinished)
        XCTAssertNil(transition.state.commitStage)
        XCTAssertTrue(transition.scheduled.isEmpty)
    }

    /// 「16時から」と答えた日の受領文に、生の発話を差し込まない（「16時から 16時から。に…」を作らない）。
    func testReceiptNeverInsertsTheRawAnswer() {
        let fourPM = ResolvedTime(date: Date(timeIntervalSince1970: 1_790_007_200), phrase: "16時", place: "から")
        for rawAnswer in ["16時から", "16時から 16時から。"] {
            let asked = declared(timeAnswer: rawAnswer, resolved: fourPM)
            XCTAssertEqual(asked.state.plannedAnswer, rawAnswer)
            let transition = FlowMachine.handle(.commitResult(.scheduled), in: asked.state)

            XCTAssertEqual(transition.spoken.count, 1)
            let receipt = transition.spoken.first ?? ""
            XCTAssertTrue(receipt.contains("16時に"), receipt)
            XCTAssertFalse(receipt.contains("16時から"), receipt)
            XCTAssertFalse(receipt.contains("。に"), receipt)
            XCTAssertFalse(receipt.contains(rawAnswer), receipt)
        }
    }

    /// 保存はできたが通知が無い日は、理由が何であっても、時刻にも「届きます」にも触れない。
    func testSavedWithoutNotificationNeverMentionsATimeOrADelivery() {
        for reason in CommitResult.NoNotificationReason.allCases {
            // 時刻なしは時刻を決めなかった会話、ほかは時刻を決めた会話で起きる。
            let asked = declared(resolved: reason == .noTime ? nil : twoPM)
            let transition = FlowMachine.handle(.commitResult(.savedWithoutNotification(reason)), in: asked.state)

            XCTAssertEqual(transition.completion, .completed, reason.rawValue)
            XCTAssertTrue(transition.state.isFinished, reason.rawValue)
            XCTAssertEqual(transition.spoken.count, 1, reason.rawValue)
            let receipt = transition.spoken.first ?? ""
            XCTAssertTrue(receipt.hasPrefix(receiptOpening), "\(reason.rawValue): \(receipt)")
            XCTAssertFalse(receipt.contains("届きます"), "\(reason.rawValue): \(receipt)")
            XCTAssertFalse(receipt.contains("14時"), "\(reason.rawValue): \(receipt)")
            XCTAssertFalse(receipt.contains("時間になったら"), "\(reason.rawValue): \(receipt)")
            XCTAssertFalse(receipt.contains("あとでやる"), "\(reason.rawValue): \(receipt)")
        }
    }

    /// 時刻が決まらなかった日（「あとでやる」→「決めない」）の受領文に、答えの言葉を差し込まない。
    func testUndecidedTimeReceiptDoesNotQuoteTheAnswer() {
        let asked = declared(timeAnswer: "あとでやる", resolved: nil)
        XCTAssertEqual(asked.commits.map(\.plannedTime), [nil])
        let transition = FlowMachine.handle(.commitResult(.savedWithoutNotification(.noTime)), in: asked.state)

        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.morningDeclarationReceiptNoTime).prefix(1).map(\.text))
        XCTAssertFalse(transition.spoken.joined().contains("あとでやる"))
        XCTAssertFalse(transition.spoken.joined().contains("届きます"))
    }

    /// 保存できなかったら受領文を読まない。1 回目は責めずに伝えて、宣言の聞き取りへ戻す。
    func testSaveFailedOnceGoesBackToTheDeclarationWithoutAReceipt() {
        let transition = FlowMachine.handle(.commitResult(.saveFailed), in: declared(resolved: twoPM).state)

        XCTAssertNil(transition.completion)
        XCTAssertFalse(transition.state.isFinished)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertEqual(transition.state.commitStage, .retrying)
        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.morningCommitRetry).prefix(1).map(\.text))
        XCTAssertFalse(transition.spoken.joined().contains(receiptOpening))
        XCTAssertEqual(transition.records.map(\.step), [.morningDeclaration], "宣言をもう一度録る")
        XCTAssertTrue(transition.saves.isEmpty && transition.scheduled.isEmpty)

        // 言い直した宣言で、もう一度保存を頼む。
        let again = FlowMachine.handle(.transcript("今日はメールを開く"), in: transition.state)
        XCTAssertEqual(again.commits.map(\.declaration), ["今日はメールを開く"])
        XCTAssertEqual(again.state.commitStage, .awaitingSecond)
        XCTAssertTrue(again.spoken.isEmpty)

        let saved = FlowMachine.handle(.commitResult(.scheduled), in: again.state)
        XCTAssertEqual(saved.completion, .completed)
        XCTAssertEqual(saved.spoken, ["受け取りました。14時に、朝のあなたから届きます。"])
    }

    /// 2 回目も保存できなかったら、保存できなかったことを伝えて、成立しなかった会話として終える。
    func testSaveFailedTwiceEndsAbandonedWithoutAReceipt() {
        var transition = FlowMachine.handle(.commitResult(.saveFailed), in: declared(resolved: twoPM).state)
        transition = FlowMachine.handle(.transcript("今日はメールを開く"), in: transition.state)
        transition = FlowMachine.handle(.commitResult(.saveFailed), in: transition.state)

        XCTAssertEqual(transition.completion, .abandoned)
        XCTAssertTrue(transition.state.isFinished)
        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.morningCommitFailed).prefix(1).map(\.text))
        XCTAssertFalse(transition.spoken.joined().contains(receiptOpening))
        XCTAssertFalse(transition.spoken.joined().contains("届きます"))
        XCTAssertTrue(transition.records.isEmpty && transition.listens.isEmpty, "3 回目は聞かない")
        XCTAssertTrue(transition.scheduled.isEmpty)
    }

    /// 文字で宣言した日（「後で声で」）に保存できなかったら、文字の入力待ちへ戻す。
    func testSaveFailedOnATypedDeclarationGoesBackToTextInput() {
        var transition = FlowMachine.start(morningEntry(mode: .text))
        transition = FlowMachine.handle(.transcript("上司への報告"), in: transition.state)
        transition = FlowMachine.handle(.choice(.reason(.anxious)), in: transition.state)
        transition = FlowMachine.handle(.transcript("資料を開く"), in: transition.state)
        transition = FlowMachine.handle(.transcript("15時に会社で"), in: transition.state)
        transition = FlowMachine.handle(.timeResolved(twoPM), in: transition.state)
        transition = FlowMachine.handle(.choice(.declareLater), in: transition.state)
        transition = FlowMachine.handle(.transcript("15時に資料を開きます"), in: transition.state)

        transition = FlowMachine.handle(.commitResult(.saveFailed), in: transition.state)

        XCTAssertNil(transition.completion)
        XCTAssertTrue(transition.records.isEmpty)
        XCTAssertEqual(transition.listens.map(\.input), [.text])
        XCTAssertEqual(transition.listens.first?.step, .morningDeclaration)
        XCTAssertTrue(transition.scheduled.isEmpty, "保存できていないので、後の声かけも約束しない")
    }

    /// 成立に必要な値が欠けていたら、受領文を読まず、未成立の締めで終える。
    func testIncompleteResultEndsAbandonedWithTheAbandonedClosing() {
        let transition = FlowMachine.handle(.commitResult(.incomplete), in: declared(resolved: twoPM).state)

        XCTAssertEqual(transition.completion, .abandoned)
        XCTAssertTrue(transition.state.isFinished)
        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.sessionAbandoned).prefix(1).map(\.text))
        XCTAssertFalse(transition.spoken.joined().contains(receiptOpening))
        XCTAssertTrue(transition.scheduled.isEmpty)
    }

    /// 頼んでいない結果は受け流す。結果を待っているあいだの答えも受け流す。
    func testCommitResultIsIgnoredUnlessItWasAskedFor() {
        let waitingForTheDeclaration = morning(at: .morningDeclaration)
        let early = FlowMachine.handle(.commitResult(.scheduled), in: waitingForTheDeclaration.state)
        XCTAssertTrue(early.commands.isEmpty)
        XCTAssertFalse(early.state.isFinished)

        let asked = declared(resolved: twoPM)
        let second = FlowMachine.handle(.transcript("別の宣言です"), in: asked.state)
        XCTAssertTrue(second.commands.isEmpty)
        XCTAssertEqual(second.state.declaration, "今日はメールを開きます")
    }

    /// 短縮版の朝フローは時刻を聞かないので、`commit` に時刻が無い。
    func testShortMorningCommitsWithoutATime() {
        var transition = morning(at: .morningDeclaration, short: true)
        transition = FlowMachine.handle(.transcript("今日はメールを開きます"), in: transition.state)
        XCTAssertEqual(transition.commits.map(\.plannedTime), [nil])

        transition = FlowMachine.handle(.commitResult(.savedWithoutNotification(.noTime)), in: transition.state)
        XCTAssertEqual(transition.completion, .completed)
        XCTAssertFalse(transition.spoken.joined().contains("届きます"))
    }

    /// 追加したプロパティ（`commitStage`）を持たない保存済みの状態も読める。
    func testFlowStateWithoutTheCommitStageStillDecodes() throws {
        let state = morning(at: .morningDeclaration).state
        let encoded = try JSONEncoder().encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["commitStage"], "nil のときは符号化されない")
        object.removeValue(forKey: "commitStage")
        let decoded = try JSONDecoder().decode(FlowState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.commitStage)
        XCTAssertEqual(decoded.step, .morningDeclaration)
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

    /// 朝の会話を、声で答えながら指定の質問まで進める。
    private func morning(at step: FlowStep, short: Bool = false) -> FlowTransition {
        var transition = short
            ? FlowMachine.start(FlowEntry(sessionType: .noon, hasCommitmentToday: false))
            : FlowMachine.start(morningEntry())
        let answers: [(FlowStep, FlowEvent)] = [
            (.morningAvoidance, .transcript("クライアントへの返信")),
            (.morningReason, .choice(.reason(.awkward))),
            (.morningMicroAction, .transcript("メールを開く")),
            (.morningPlannedTime, .transcript("14時に自宅で")),
            (.morningPlannedTime, .timeResolved(twoPM)),
        ]
        for (answered, event) in answers where transition.state.step != step {
            guard transition.state.step == answered else { continue }
            transition = FlowMachine.handle(event, in: transition.state)
        }
        XCTAssertEqual(transition.state.step, step)
        return transition
    }

    func testRequiredQuestionsAreAvoidanceMicroActionAndDeclaration() {
        XCTAssertEqual(
            FlowStep.allCases.filter(\.isRequired),
            [.morningAvoidance, .morningMicroAction, .morningDeclaration]
        )
    }

    /// 必須でない質問（M1）は、従来どおり催促を 1 回挟んでから次へ進む。
    func testSilenceNudgesOnceThenSkipsAQuestionThatIsNotRequired() {
        var transition = morning(at: .morningReason)
        XCTAssertEqual(transition.listens.first?.silenceSeconds, FlowMachine.firstSilenceSeconds)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.spoken, ["長く考えなくていい。10秒で答えて。"])
        XCTAssertEqual(transition.listens.first?.silenceSeconds, FlowMachine.secondSilenceSeconds)
        XCTAssertEqual(transition.state.step, .morningReason)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningMicroAction, "2 回目の沈黙でその質問をスキップする")
        XCTAssertEqual(transition.state.silenceCount, 0)
    }

    /// 必須でない M3 も、沈黙 2 回で宣言へ進む。
    func testSilenceTwiceAtPlannedTimeStillAdvances() {
        var transition = morning(at: .morningPlannedTime)
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertNil(transition.state.plannedAnswer)
    }

    /// M2 は沈黙 2 回でも M3 へ進まない。押せる例（行動のチップ）に落とす。
    func testSilenceTwiceAtMicroActionShowsTheActionChipsInsteadOfAdvancing() {
        var transition = morning(at: .morningMicroAction)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.spoken, ["長く考えなくていい。10秒で答えて。"])
        XCTAssertEqual(transition.state.step, .morningMicroAction)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningMicroAction, "行動が空のまま時刻の質問へ進まない")
        XCTAssertNil(transition.state.microAction)
        XCTAssertEqual(transition.choices, DialogueCopy.exampleActionIDs)
        XCTAssertTrue(transition.listens.isEmpty)
        XCTAssertNil(transition.completion)
        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.morningMicroActionChipsPrompt).prefix(1).map(\.text))

        // チップを押せば、その行動で先へ進む。
        transition = FlowMachine.handle(.choice(.exampleWriteOneLine), in: transition.state)
        XCTAssertEqual(transition.state.microAction?.text, "1行だけ書く")
        XCTAssertEqual(transition.state.step, .morningPlannedTime)
    }

    /// M0 は沈黙 2 回でも M1 へ進まない。その質問だけ文字の入力待ちに落とす。
    func testSilenceTwiceAtAvoidanceWaitsForTextInsteadOfAdvancing() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningAvoidance)

        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningAvoidance, "逃げたいことが空のまま理由の質問へ進まない")
        XCTAssertEqual(transition.listens.map(\.input), [.text])
        XCTAssertEqual(transition.listens.first?.step, .morningAvoidance)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertNil(transition.completion)
    }

    /// 必須でない質問（M1 理由、M3 時刻）のスキップは従来どおり次へ進む。
    func testSkipAdvancesOnQuestionsThatAreNotRequired() {
        var transition = FlowMachine.handle(.skip, in: morning(at: .morningReason).state)
        XCTAssertEqual(transition.state.step, .morningMicroAction)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertNil(transition.completion)

        transition = FlowMachine.handle(.skip, in: morning(at: .morningPlannedTime).state)
        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertNil(transition.completion)
    }

    /// 必須の質問（M0・M2・M4）のスキップは次へ進まず、約束を作らずに終える。保存命令も通知命令も出ない。
    func testSkipOnARequiredQuestionEndsAsAbandonedWithoutSaving() {
        let closings = Set(DialogueCopy.variants(.sessionAbandoned).map(\.text))
        let receipts = DialogueCopy.variants(.morningDeclarationReceipt).map(\.text)
            + DialogueCopy.variants(.morningDeclarationReceiptNoTime).map(\.text)

        for step in [FlowStep.morningAvoidance, .morningMicroAction, .morningDeclaration] {
            let transition = FlowMachine.handle(.skip, in: morning(at: step).state)

            XCTAssertEqual(transition.completion, .abandoned, "\(step.code)")
            XCTAssertEqual(transition.state.step, step, "\(step.code): 次の質問へ進まない")
            XCTAssertTrue(transition.state.isFinished, "\(step.code)")
            XCTAssertTrue(transition.saves.isEmpty, "\(step.code): 保存命令を出さない")
            XCTAssertTrue(transition.scheduled.isEmpty, "\(step.code): 通知を登録しない")
            XCTAssertTrue(transition.listens.isEmpty && transition.records.isEmpty, "\(step.code)")
            XCTAssertEqual(transition.spoken.count, 1, "\(step.code): 締めは 1 文だけ")
            XCTAssertTrue(closings.contains(transition.spoken.first ?? ""), "\(step.code): \(transition.spoken)")
            for receipt in receipts {
                XCTAssertFalse(transition.spoken.contains(receipt), "\(step.code): 受け取ったとは言わない")
            }
        }
    }

    /// 短縮版の朝フロー（M0 → M2 → M4）にも同じ規則を当てる。
    func testRequiredQuestionsInTheShortMorningFlowFollowTheSameRule() {
        for step in [FlowStep.morningAvoidance, .morningMicroAction, .morningDeclaration] {
            let skipped = FlowMachine.handle(.skip, in: morning(at: step, short: true).state)
            XCTAssertEqual(skipped.completion, .abandoned, "\(step.code)")
            XCTAssertTrue(skipped.saves.isEmpty, "\(step.code)")
        }

        var transition = morning(at: .morningMicroAction, short: true)
        XCTAssertTrue(transition.state.isShortMorning)
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        transition = FlowMachine.handle(.timeout(.silence), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningMicroAction)
        XCTAssertEqual(transition.choices, DialogueCopy.exampleActionIDs)
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

    /// 必須でなく選択肢も無い質問（M3）は、聞き直しの上限でスキップする。
    func testShortTranscriptSkipsWhenTheStepIsNotRequiredAndHasNoAnswerChoices() {
        var transition = morning(at: .morningPlannedTime)
        for _ in 0..<(FlowMachine.maxRetries + 1) {
            transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        }
        XCTAssertEqual(transition.state.step, .morningDeclaration, "選択肢が無いステップはスキップする")
    }

    /// M0 は聞き直しの上限に達しても M1 へ進まない。その質問だけ文字の入力待ちになる。
    func testRetryLimitAtAvoidanceWaitsForTextInsteadOfAdvancing() {
        var transition = FlowMachine.start(morningEntry())
        for _ in 0..<FlowMachine.maxRetries {
            transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
            XCTAssertEqual(transition.listens.map(\.input), [.voice])
        }

        transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningAvoidance, "逃げたいことが空のまま理由の質問へ進まない")
        XCTAssertTrue(transition.state.avoidance.isEmpty)
        XCTAssertEqual(transition.listens.map(\.input), [.text])
        XCTAssertEqual(transition.listens.first?.step, .morningAvoidance)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertNil(transition.completion)
        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.requiredTextPrompt).prefix(1).map(\.text))

        // 文字で答えると先へ進む。会話全体は文字に固定されず、次の質問は声で聞く。
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        XCTAssertEqual(transition.state.step, .morningReason)
        XCTAssertEqual(transition.state.avoidance, "クライアントへの返信")
        XCTAssertEqual(transition.state.mode, .voice)
        XCTAssertEqual(transition.listens.map(\.input), [.voice])
    }

    /// M4 も聞き直しの上限で終わらせない。宣言が空のまま会話を完了にせず、文字の入力待ちになる。
    func testRetryLimitAtDeclarationWaitsForTextInsteadOfFinishing() {
        var transition = morning(at: .morningDeclaration)
        for _ in 0..<(FlowMachine.maxRetries + 1) {
            transition = FlowMachine.handle(.transcript(""), in: transition.state)
        }

        XCTAssertEqual(transition.state.step, .morningDeclaration)
        XCTAssertFalse(transition.state.isFinished)
        XCTAssertNil(transition.completion, "宣言が空のまま完了にしない")
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertEqual(transition.listens.map(\.input), [.text])
        XCTAssertEqual(transition.listens.first?.step, .morningDeclaration)
        XCTAssertEqual(transition.state.mode, .voice)
        XCTAssertFalse(transition.state.isVoicelessDay, "その日を声なしに固定しない")

        transition = FlowMachine.handle(.transcript("今日は14時にメールを開きます"), in: transition.state)
        XCTAssertEqual(transition.saves.map(\.kind), [.declaration])
        XCTAssertEqual(transition.commits.map(\.declaration), ["今日は14時にメールを開きます"])
        transition = FlowMachine.handle(.commitResult(.scheduled), in: transition.state)
        XCTAssertEqual(transition.completion, .completed)
    }

    /// M2 は聞き直しの上限でも M3 へ進まず、行動のチップに落とす。
    func testRetryLimitAtMicroActionShowsTheActionChips() {
        var transition = morning(at: .morningMicroAction)
        for _ in 0..<(FlowMachine.maxRetries + 1) {
            transition = FlowMachine.handle(.transcript("あ"), in: transition.state)
        }
        XCTAssertEqual(transition.state.step, .morningMicroAction)
        XCTAssertNil(transition.state.microAction)
        XCTAssertEqual(transition.choices, DialogueCopy.exampleActionIDs)
        XCTAssertTrue(transition.listens.isEmpty)
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
        transition = FlowMachine.handle(.timeResolved(twoPM), in: transition.state)
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
        transition = FlowMachine.handle(.timeResolved(twoPM), in: transition.state)

        transition = FlowMachine.handle(.choice(.declareLater), in: transition.state)
        XCTAssertTrue(transition.state.isDeclarationDeferred)
        XCTAssertEqual(transition.listens.first?.input, .text)

        transition = FlowMachine.handle(.transcript("15時に資料を開きます"), in: transition.state)
        XCTAssertEqual(transition.saves.map(\.kind), [.declaration])
        XCTAssertEqual(transition.saves.first?.hasAudio, false)
        XCTAssertEqual(transition.commits.map(\.isDeclarationDeferred), [true])
        XCTAssertTrue(transition.scheduled.isEmpty, "保存の結果を受けるまで、後の声かけも約束しない")

        transition = FlowMachine.handle(.commitResult(.scheduled), in: transition.state)
        XCTAssertTrue(transition.spoken.contains(DialogueCopy.variants(.morningDeclarationDeferred)[0].text))
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
        transition = FlowMachine.handle(.timeResolved(twoPM), in: transition.state)
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
        transition = FlowMachine.handle(.timeResolved(twoPM), in: transition.state)
        let interrupted = FlowMachine.handle(.interrupted, in: transition.state)
        XCTAssertEqual(interrupted.state.step, .morningDeclaration)

        let resumed = FlowMachine.start(FlowEntry(sessionType: .morning, resume: interrupted.state))
        XCTAssertEqual(resumed.state.step, .morningDeclaration)
        XCTAssertEqual(resumed.records.map(\.step), [.morningDeclaration])
        XCTAssertEqual(resumed.state.plannedAnswer, "20時に自宅で")
        XCTAssertEqual(resumed.state.plannedTime, twoPM)
    }

    // MARK: - タイムボックス

    func testTimeboxSavesNothingMoreAndClosesTheSession() {
        var transition = FlowMachine.start(morningEntry())
        transition = FlowMachine.handle(.transcript("クライアントへの返信"), in: transition.state)
        transition = FlowMachine.handle(.timeout(.timebox), in: transition.state)

        XCTAssertEqual(transition.spoken, DialogueCopy.variants(.timeboxExceeded).prefix(1).map(\.text))
        XCTAssertEqual(transition.completion, .timeboxExceeded)
        XCTAssertTrue(transition.saves.isEmpty)
        XCTAssertTrue(transition.state.isFinished)
    }

    /// 時間切れの一言は、実装されていない続きを約束しない。会話の種類に合う文言を選ぶ。
    func testTimeboxLinePromisesNoContinuationInAnySession() {
        let morning = FlowMachine.handle(.timeout(.timebox), in: FlowMachine.start(morningEntry()).state)
        let shortMorning = FlowMachine.handle(
            .timeout(.timebox),
            in: FlowMachine.start(FlowEntry(sessionType: .noon, hasCommitmentToday: false)).state
        )
        let noon = FlowMachine.handle(
            .timeout(.timebox),
            in: FlowMachine.start(FlowEntry(sessionType: .noon, hasCommitmentToday: true)).state
        )
        let night = FlowMachine.handle(
            .timeout(.timebox),
            in: FlowMachine.start(FlowEntry(sessionType: .night, hasCommitmentToday: true)).state
        )

        XCTAssertEqual(morning.spoken, DialogueCopy.variants(.timeboxExceeded).prefix(1).map(\.text))
        XCTAssertEqual(shortMorning.spoken, DialogueCopy.variants(.timeboxExceeded).prefix(1).map(\.text))
        XCTAssertEqual(noon.spoken, DialogueCopy.variants(.timeboxExceededNoon).prefix(1).map(\.text))
        XCTAssertEqual(night.spoken, DialogueCopy.variants(.timeboxExceededNight).prefix(1).map(\.text))

        for transition in [morning, shortMorning, noon, night] {
            XCTAssertEqual(transition.completion, .timeboxExceeded)
            for line in transition.spoken {
                XCTAssertFalse(line.contains("続き"), "続きを約束しない: \(line)")
                XCTAssertFalse(line.contains("聞くね"), "後で聞くと約束しない: \(line)")
            }
        }
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
