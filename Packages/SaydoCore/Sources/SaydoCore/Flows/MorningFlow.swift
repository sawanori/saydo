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
            let line = state.picker.pickText(.morningDeclarationRequest)
            // 声で言えない状況では「今、声で言う」か「後で声で」を選ぶ（retention R1）。
            if state.mode == .text {
                let prompt = state.picker.pickText(.morningDeclarationChoice)
                return FlowTransition(
                    state: state,
                    commands: [
                        .speak(line),
                        .speak(prompt),
                        .showChoices([Choice(.declareNow), Choice(.declareLater)]),
                    ]
                )
            }
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

    private static func plannedTime(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            // 「何時に、どこで」を 1 つの答えとして受け取る（retention R11）。
            // 時刻と場所への分解は JapaneseTimeParser（task_005b）が行う。
            state.plannedAnswer = text
            return FlowMachine.advance(from: state)

        case .choice(let id):
            guard DialogueCopy.timeExampleIDs.contains(id) else {
                return FlowTransition(state: state, commands: [])
            }
            if id == .timePick {
                // 時刻の選択は画面側の仕事。もう一度この質問で受け直す。
                return enter(.morningPlannedTime, in: state)
            }
            state.plannedAnswer = DialogueCopy.label(id)
            return FlowMachine.advance(from: state)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - M4

    private static func declaration(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .choice(.declareNow):
            return FlowTransition(state: state, commands: [.record(RecordRequest(step: .morningDeclaration))])

        case .choice(.declareLater):
            state.isDeclarationDeferred = true
            state.isVoicelessDay = true
            let prompt = state.picker.pickText(.morningDeclarationTextPrompt)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(prompt),
                    .listen(ListenRequest(step: .morningDeclaration, silenceSeconds: FlowMachine.firstSilenceSeconds, input: .text)),
                ]
            )

        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            state.declaration = text
            state.isFinished = true

            var commands: [FlowCommand] = []
            let hasAudio = !state.isDeclarationDeferred && state.mode == .voice
            if let save = FlowMachine.save(.morningDeclaration, text: text, state: state, hasAudio: hasAudio) {
                commands.append(save)
            }
            if let planned = state.plannedAnswer, !planned.isEmpty {
                commands.append(.scheduleNotification(NotificationRequest(kind: .actionTime, timePhrase: planned)))
            }
            if state.isDeclarationDeferred {
                // 一人になれる時刻に 1 回だけ声をかける（retention R1）。再通知はしない。
                commands.append(.scheduleNotification(NotificationRequest(kind: .declarationReminder, onlyOnce: true)))
                commands.append(.speak(state.picker.pickText(.morningDeclarationDeferred)))
            }
            if let planned = state.plannedAnswer, !planned.isEmpty {
                commands.append(.speak(state.picker.pickText(.morningDeclarationReceipt, time: planned)))
            } else {
                commands.append(.speak(state.picker.pickText(.morningDeclarationReceiptNoTime)))
            }
            commands.append(.finish(.completed))
            return FlowTransition(state: state, commands: commands)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }
}
