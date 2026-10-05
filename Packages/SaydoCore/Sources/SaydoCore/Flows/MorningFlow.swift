import Foundation

/// 朝の会話 M0〜M4（実装計画 §7.2）。
///
/// 保存するのは M0（逃げたいこと）・M1（理由）・M4（宣言）の 3 か所だけ。
/// M2（行動）と M3（時刻と場所）は `Commitment` の値として持ち回り、`VoiceEntry` にはしない。
public enum MorningFlow {

    /// 2 日以上空いたら再入場の文言に差し替える（retention R4）。
    public static let reentryThresholdDays = 2

    /// `short` が true なら短縮版の朝フロー（M0 → M2 → M4）。理由と時刻は聞かない。
    static func start(_ entry: FlowEntry, picker: CopyPicker, short: Bool = false) -> FlowTransition {
        var state = FlowState(
            sessionType: .morning,
            step: .morningAvoidance,
            mode: entry.mode,
            picker: picker,
            carryover: entry.carryover,
            isShortMorning: short,
            isVoicelessDay: entry.isVoicelessDay
        )

        var commands: [FlowCommand] = []
        // 空白日数・連続日数には一切言及しない。おかえりとだけ言う。
        if let gap = entry.daysSinceLastRecord, gap >= reentryThresholdDays {
            commands.append(.speak(state.picker.pickText(.morningReentry)))
        }

        let opening = enter(.morningAvoidance, in: state)
        state = opening.state
        commands.append(contentsOf: opening.commands)
        return FlowTransition(state: state, commands: commands)
    }

    static func enter(_ step: FlowStep, in state: FlowState) -> FlowTransition {
        var state = state
        state.step = step

        switch step {
        case .morningAvoidance:
            // 前夜の引き継ぎがあるうちは、まず引き継ぎ確認から入る。
            if let carryover = state.carryover, !carryover.isEmpty, state.carryoverDecision == nil {
                let line = state.picker.pickText(.morningCarryoverQuestion, topic: carryover)
                return FlowTransition(
                    state: state,
                    commands: [
                        .speak(line),
                        .showChoices([Choice(.carryoverKeep), Choice(.carryoverChange)]),
                    ]
                )
            }
            let line = state.picker.pickText(.morningAvoidanceQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .morningReason:
            let line = state.picker.pickText(.morningReasonQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .showChoices(ReasonCategory.allCases.map { Choice(.reason($0)) }),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .morningMicroAction:
            let line = state.picker.pickText(.morningMicroActionQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .morningPlannedTime:
            let line = state.picker.pickText(.morningTimePlaceQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .morningDeclaration:
            // 「声を出さない」の間（マイク拒否を含む）は、選択肢を出さずに文字の宣言を待つ。
            // 「後で声で」は、通知の実装が整うまで出さない（task_036。retention R1 は一時停止中）。
            if state.mode == .text {
                return textDeclarationWait(state)
            }
            let line = state.picker.pickText(.morningDeclarationRequest)
            return FlowTransition(
                state: state,
                commands: [.speak(line), .record(RecordRequest(step: .morningDeclaration))]
            )

        default:
            return FlowMachine.enter(step, in: state)
        }
    }

    static func handle(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        switch state.step {
        case .morningAvoidance: avoidance(event, in: state)
        case .morningReason: reason(event, in: state)
        case .morningMicroAction: microAction(event, in: state)
        case .morningPlannedTime: plannedTime(event, in: state)
        case .morningDeclaration: declaration(event, in: state)
        default: FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - M0

    /// 「特にない」と読める答え（retention R6）。
    static let nothingToAvoidAnswers = ["特にない", "特になし", "とくにない", "ない", "ないです", "なし", "思いつかない"]

    static func isNothingToAvoid(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return nothingToAvoidAnswers.contains(trimmed)
    }

    private static func avoidance(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // 逃げたいことが無い日は良い日として 10 秒で終わる。
            if isNothingToAvoid(text) {
                state.isGoodDay = true
                state.isFinished = true
                var commands: [FlowCommand] = []
                if let save = FlowMachine.save(.morningAvoidance, text: text, state: state, hasAudio: FlowMachine.hasAudio(state)) {
                    commands.append(save)
                }
                commands.append(.speak(state.picker.pickText(.morningGoodDay)))
                commands.append(.finish(.goodDay))
                return FlowTransition(state: state, commands: commands)
            }
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            state.avoidance = text
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.morningAvoidance, text: text, state: state, hasAudio: FlowMachine.hasAudio(state)) {
                commands.append(save)
            }
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        case .choice(let id):
            return carryoverChoice(id, in: state)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    private static func carryoverChoice(_ id: ChoiceID, in state: FlowState) -> FlowTransition {
        var state = state
        let carryover = state.carryover ?? ""

        switch id {
        case .carryoverKeep:
            state.carryoverDecision = id
            state.avoidance = carryover
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.morningAvoidance, text: carryover, state: state, hasAudio: false) {
                commands.append(save)
            }
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        case .carryoverChange:
            // 企画書 §9 の 6 選択肢はここで出す（夜 E0 では出さない）。
            state.carryoverDecision = id
            return FlowTransition(
                state: state,
                commands: [.showChoices(DialogueCopy.sixOptionIDs.map(Choice.init))]
            )

        case .shrinkMore, .askSomeone, .setDeadline, .differentWay:
            // 対象は変えず、進め方だけを変える。
            state.carryoverDecision = id
            state.avoidance = carryover
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.morningAvoidance, text: carryover, state: state, hasAudio: false) {
                commands.append(save)
            }
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        case .dropToday, .differentThing:
            // 今日は別のことを聞く。
            state.carryoverDecision = id
            state.carryover = nil
            return enter(.morningAvoidance, in: state)

        case .moveToTomorrow:
            // 明日また聞くために引き継ぎだけ残し、今日は別のことを聞く。
            state.carryoverDecision = id
            state.tomorrow = carryover
            state.carryover = nil
            return enter(.morningAvoidance, in: state)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - M1

    private static func reason(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .choice(.reason(let category)):
            state.reason = category
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.morningReason, text: category.displayName, state: state, hasAudio: false) {
                commands.append(save)
            }
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            // 分類は `DialogueEngine` の仕事。分類できなくても会話は止めない（retention R7）。
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.morningReason, text: text, state: state, hasAudio: FlowMachine.hasAudio(state)) {
                commands.append(save)
            }
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - M2

    private static func microAction(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            // 本人の言葉をそのまま行動文にする。名詞の切り出しはしない。
            state.microAction = MicroAction(text: text, shrinkCount: state.microAction?.shrinkCount ?? 0)
            return FlowMachine.advance(from: state)

        case .choice(let id):
            if let action = DialogueCopy.actionText(id) {
                state.microAction = MicroAction(text: action, shrinkCount: state.microAction?.shrinkCount ?? 0)
                return FlowMachine.advance(from: state)
            }
            if id == .shrinkMore {
                // 「もっと小さく」はいつでも選べる。もう一度、より小さい一歩を聞く。
                state.microAction = state.microAction.map {
                    MicroAction(text: $0.text, estimatedMinutes: $0.estimatedMinutes, shrinkCount: $0.shrinkCount + 1)
                }
                return enter(.morningMicroAction, in: state)
            }
            return FlowTransition(state: state, commands: [])

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - M3

    /// 時刻の答えは、ここでは解釈しない（時計を持たないため）。生の発話を `plannedAnswer` に残し、
    /// `resolveTime` でアプリに解釈を頼んで、結果（`timeResolved`）を待つ（実装計画 §16.7）。
    private static func plannedTime(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        let isAwaiting = state.timeResolution == .awaitingFirst || state.timeResolution == .awaitingSecond

        /// 答え（発話またはチップの文言）の解釈を頼む。
        func resolve(_ answer: String) -> FlowTransition {
            state.plannedAnswer = answer
            state.timeResolution = state.timeResolution == .reasking ? .awaitingSecond : .awaitingFirst
            return FlowTransition(state: state, commands: [.resolveTime(answer)])
        }

        switch event {
        case .timeResolved(let resolved):
            // 頼んでいない結果は受け流す。
            guard isAwaiting else {
                return FlowTransition(state: state, commands: [])
            }
            if let resolved {
                state.plannedTime = resolved
                return FlowMachine.advance(from: state)
            }
            guard state.timeResolution == .awaitingFirst else {
                // 聞き直しても決まらなかった。時刻なしで宣言へ進む。
                return FlowMachine.advance(from: state)
            }
            // 解釈できなかった、またはもう過ぎた時刻だった。時刻のチップを出して 1 回だけ聞き直す。
            state.timeResolution = .reasking
            state.silenceCount = 0
            state.retryCount = 0
            let line = state.picker.pickText(.morningTimeChipsPrompt)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .showChoices(DialogueCopy.timeChipIDs.map(Choice.init)),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .transcript(let raw):
            guard !isAwaiting else {
                return FlowTransition(state: state, commands: [])
            }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            // 「何時に、どこで」を 1 つの答えとして受け取る（retention R11）。
            return resolve(text)

        case .choice(let id):
            guard !isAwaiting else {
                return FlowTransition(state: state, commands: [])
            }
            if id == .timeUndecided {
                // 時刻を決めないまま宣言へ進む。
                return FlowMachine.advance(from: state)
            }
            guard DialogueCopy.timeExampleIDs.contains(id) || DialogueCopy.timeChipIDs.contains(id) else {
                return FlowTransition(state: state, commands: [])
            }
            if id == .timePick {
                // 時刻の選択は画面側の仕事。もう一度この質問で受け直す。
                return enter(.morningPlannedTime, in: state)
            }
            // チップと例示の文言も、声の答えと同じ経路で解釈する。
            return resolve(DialogueCopy.label(id))

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - M4

    /// 宣言を受けても、ここでは「受け取りました」と言わない。約束の保存と通知の登録を `commit` で
    /// アプリに頼み、結果（`commitResult`）に合う受領文を選んでから会話を終える（実装計画 §16.7）。
    private static func declaration(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        let isAwaiting = state.commitStage == .awaitingFirst || state.commitStage == .awaitingSecond

        switch event {
        case .choice(.declareLater):
            // 選択肢としては出さない。万一届いても後回しにせず、通常の文字の宣言待ちと同じに扱う。
            // 声の会話では、宣言の録音を邪魔しないよう受け流す。
            guard !isAwaiting, state.mode == .text else {
                return FlowTransition(state: state, commands: [])
            }
            return textDeclarationWait(state)

        case .transcript(let raw):
            // 結果を待っているあいだの答えは受け流す。
            guard !isAwaiting else {
                return FlowTransition(state: state, commands: [])
            }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            state.declaration = text
            state.commitStage = state.commitStage == .retrying ? .awaitingSecond : .awaitingFirst

            var commands: [FlowCommand] = []
            // その日が「声なし」かは、ここで決める。それまでに文字を使ったかどうかは見ない。
            // 声で頼んだ宣言を文字で受けた場合は録音が無いので、アプリが録音の有無で確定する。
            let hasAudio = FlowMachine.hasAudio(state)
            state.isVoicelessDay = !hasAudio
            if let save = FlowMachine.save(.morningDeclaration, text: text, state: state, hasAudio: hasAudio) {
                commands.append(save)
            }
            commands.append(.commit(CommitRequest(
                avoidance: state.avoidance,
                microAction: state.microAction,
                declaration: text,
                plannedTime: state.plannedTime,
                isDeclarationDeferred: state.isDeclarationDeferred
            )))
            return FlowTransition(state: state, commands: commands)

        case .commitResult(let result):
            // 頼んでいない結果は受け流す。
            guard isAwaiting else {
                return FlowTransition(state: state, commands: [])
            }
            return receive(result, in: state)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    /// 文字の宣言を待つ。声で言うよう頼まず、選択肢も出さない。
    private static func textDeclarationWait(_ state: FlowState) -> FlowTransition {
        var state = state
        let prompt = state.picker.pickText(.morningDeclarationTextPrompt)
        return FlowTransition(
            state: state,
            commands: [
                .speak(prompt),
                .listen(ListenRequest(step: .morningDeclaration, silenceSeconds: FlowMachine.firstSilenceSeconds, input: .text)),
            ]
        )
    }

    /// 約束の保存と通知の登録の結果に合う言葉を選ぶ。起きていないことは言わない。
    private static func receive(_ result: CommitResult, in state: FlowState) -> FlowTransition {
        var state = state
        let wasFirstAttempt = state.commitStage == .awaitingFirst

        switch result {
        case .scheduled, .savedWithoutNotification:
            state.commitStage = nil
            state.isFinished = true
            var commands: [FlowCommand] = []
            // 「◯時に届きます」と言うのは、通知を登録できたときだけ。時刻は整えた句を使い、生の発話は差し込まない。
            if result == .scheduled, let planned = state.plannedTime {
                commands.append(.speak(state.picker.pickText(.morningDeclarationReceipt, time: planned.phrase)))
            } else {
                commands.append(.speak(state.picker.pickText(.morningDeclarationReceiptNoTime)))
            }
            commands.append(.finish(.completed))
            return FlowTransition(state: state, commands: commands)

        case .saveFailed:
            guard wasFirstAttempt else {
                // 2 回目も保存できなかった。受け取ったとは言わず、成立しなかった会話として終える。
                state.commitStage = nil
                state.isFinished = true
                let line = state.picker.pickText(.morningCommitFailed)
                return FlowTransition(state: state, commands: [.speak(line), .finish(.abandoned)])
            }
            // 1 回だけ、宣言の聞き取りへ戻す。文字で宣言した日は文字で受け直す。
            state.commitStage = .retrying
            state.declaration = ""
            state.silenceCount = 0
            state.retryCount = 0
            let line = state.picker.pickText(.morningCommitRetry)
            let again: FlowCommand = state.mode == .text
                ? .listen(ListenRequest(step: .morningDeclaration, silenceSeconds: FlowMachine.firstSilenceSeconds, input: .text))
                : .record(RecordRequest(step: .morningDeclaration))
            return FlowTransition(state: state, commands: [.speak(line), again])

        case .incomplete:
            // 成立に必要な値が欠けている。約束は作られていないので、未成立の締めで終える。
            state.commitStage = nil
            return FlowMachine.abandon(state)
        }
    }
}
