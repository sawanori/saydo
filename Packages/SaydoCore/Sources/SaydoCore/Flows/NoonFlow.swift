import Foundation

/// 昼の会話 N0〜N3 と、その前に必ず通る入口の 3 条件（実装計画 §7.2）。
///
/// 行動時刻通知・固定の昼通知・手動起動のいずれからでもここに入る。
public enum NoonFlow {

    /// 入口の判定結果。
    public enum Entrance: String, Sendable, Equatable, Hashable, Codable {
        /// 当日の `Commitment` が無い。短縮版の朝フロー（M0 → M2 → M4）を開く。
        case shortMorning
        /// すでに `done` か `partial`（少しやった = 前進。fix-decisions P2.5 / P2.6）。
        /// 固定の昼通知と行動時刻通知を取り消して終わる。
        case alreadyDone
        /// 行動時刻より前。「まだ生きてる？」だけ聞いて終わる。
        case promiseCheck
        /// 通常どおり N0 から進む。
        case playback
    }

    /// 入口の条件を判定する。
    public static func entrance(_ entry: FlowEntry) -> Entrance {
        if !entry.hasCommitmentToday { return .shortMorning }
        if entry.outcome.isProgress { return .alreadyDone }
        if entry.isBeforePlannedTime { return .promiseCheck }
        return .playback
    }

    static func start(_ entry: FlowEntry, picker: CopyPicker) -> FlowTransition {
        switch entrance(entry) {
        case .shortMorning:
            // 理由（M1）と時刻（M3）は聞かない。
            return MorningFlow.start(entry, picker: picker, short: true)

        case .alreadyDone:
            var state = FlowState(
                sessionType: .noon,
                step: .finished,
                mode: entry.mode,
                picker: picker,
                outcome: entry.outcome,
                isVoicelessDay: entry.isVoicelessDay,
                isFinished: true
            )
            let line = state.picker.pickText(.noonAlreadyDone)
            return FlowTransition(
                state: state,
                commands: [
                    .cancelNotification(.noonFixed),
                    .cancelNotification(.actionTime),
                    .speak(line),
                    .finish(.completed),
                ]
            )

        case .promiseCheck:
            var state = FlowState(
                sessionType: .noon,
                step: .noonStatus,
                mode: entry.mode,
                picker: picker,
                plannedAnswer: entry.plannedTimeLabel,
                outcome: entry.outcome,
                isPromiseCheck: true,
                isVoicelessDay: entry.isVoicelessDay
            )
            let line = state.picker.pickText(.noonBeforePlannedTime, time: entry.plannedTimeLabel ?? "")
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .showChoices([Choice(.promiseAlive), Choice(.changeTime)]),
                ]
            )

        case .playback:
            let state = FlowState(
                sessionType: .noon,
                step: .noonPlayback,
                mode: entry.mode,
                picker: picker,
                plannedAnswer: entry.plannedTimeLabel,
                outcome: entry.outcome,
                isVoicelessDay: entry.isVoicelessDay
            )
            return enter(.noonPlayback, in: state)
        }
    }

    static func enter(_ step: FlowStep, in state: FlowState) -> FlowTransition {
        var state = state
        state.step = step

        switch step {
        case .noonPlayback:
            let line = state.picker.pickText(.noonIntro)
            // 「声なし」の日は宣言テキストを大きく出す。本人の言葉を読み上げ直さない。
            let target: PlaybackRequest.Target = state.isVoicelessDay ? .declarationText : .declarationAudio
            return FlowTransition(
                state: state,
                commands: [.speak(line), .play(PlaybackRequest(target: target))]
            )

        case .noonStatus:
            if state.isPromiseCheck {
                let line = state.picker.pickText(.noonBeforePlannedTime, time: state.plannedAnswer ?? "")
                return FlowTransition(
                    state: state,
                    commands: [.speak(line), .showChoices([Choice(.promiseAlive), Choice(.changeTime)])]
                )
            }
            let line = state.picker.pickText(.noonStatusQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .showChoices(statusChoices),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .noonBlocker:
            let line = state.picker.pickText(.noonBlockerQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .noonShrink:
            let line = state.picker.pickText(.noonShrinkPrompt, topic: state.topic)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .showChoices(shrinkChoices),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        default:
            return FlowMachine.enter(step, in: state)
        }
    }

    /// N1 の選択肢。`pending` は出さない。
    static let statusChoices: [Choice] = [
        Choice(.status(.done)), Choice(.status(.partial)), Choice(.status(.notYet)),
    ]

    /// N3 の選択肢。企画書 §9 の 6 選択肢のうち「今日は捨てる」「明日に回す」をここで使う。
    static let shrinkChoices: [Choice] = [
        Choice(.cannotDecide), Choice(.retryInOneHour), Choice(.dropToday), Choice(.moveToTomorrow),
    ]

    static func handle(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        switch state.step {
        case .noonPlayback: playback(event, in: state)
        case .noonStatus: status(event, in: state)
        case .noonBlocker: blocker(event, in: state)
        case .noonShrink: shrink(event, in: state)
        default: FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - N0

    private static func playback(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        switch event {
        case .playbackFinished:
            FlowMachine.advance(from: state)
        default:
            FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - 入口（行動時刻より前）と N1

    /// 声で答えたときに `CommitmentOutcome` を読み取る言葉。
    static func matchOutcome(_ text: String) -> CommitmentOutcome? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let partialWords = ["少し", "ちょっと", "途中", "半分", "すこし"]
        let notYetWords = ["まだ", "できてない", "やってない", "できていない", "やっていない", "手つかず"]
        let doneWords = [
            "やった", "やりました", "できた", "できました",
            "終わった", "終わりました", "終えた", "送った", "送りました", "済んだ",
        ]

        if partialWords.contains(where: { trimmed.contains($0) }) { return .partial }
        if notYetWords.contains(where: { trimmed.contains($0) }) { return .notYet }
        if doneWords.contains(where: { trimmed.contains($0) }) { return .done }
        return nil
    }

    private static func status(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        if state.isPromiseCheck {
            return promiseCheck(event, in: state)
        }
        if state.isChangingTime {
            return changeTime(event, in: state)
        }

        switch event {
        case .choice(.status(let outcome)):
            return finishStatus(outcome, text: outcome.displayName, hasAudio: false, in: state)

        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text), let outcome = matchOutcome(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            return finishStatus(outcome, text: text, hasAudio: FlowMachine.hasAudio(state), in: state)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    /// 「時間を変える」を選んだ後、新しい時刻を受け取って通知を登録し直す。
    private static func changeTime(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state

        func accept(_ phrase: String) -> FlowTransition {
            state.plannedAnswer = phrase
            state.isChangingTime = false
            state.isFinished = true
            return FlowTransition(
                state: state,
                commands: [
                    .scheduleNotification(NotificationRequest(kind: .actionTime, timePhrase: phrase)),
                    .speak(state.picker.pickText(.noonPromiseAliveAck)),
                    .finish(.completed),
                ]
            )
        }

        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            return accept(text)

        case .choice(let id) where DialogueCopy.timeExampleIDs.contains(id) && id != .timePick:
            return accept(DialogueCopy.label(id))

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    private static func finishStatus(
        _ outcome: CommitmentOutcome,
        text: String,
        hasAudio: Bool,
        in state: FlowState
    ) -> FlowTransition {
        var state = state
        state.outcome = outcome

        var commands: [FlowCommand] = []
        if let save = FlowMachine.save(.noonStatus, text: text, state: state, hasAudio: hasAudio) {
            commands.append(save)
        }

        switch outcome {
        case .done:
            state.isFinished = true
            commands.append(.cancelNotification(.actionTime))
            commands.append(.speak(state.picker.pickText(.noonDoneEnding)))
            commands.append(.finish(.completed))
            return FlowTransition(state: state, commands: commands)

        case .partial:
            // 「少しやった」も前進。ここで終わり、N2 には進まない。
            state.isFinished = true
            commands.append(.speak(state.picker.pickText(.noonPartialEnding)))
            commands.append(.finish(.completed))
            return FlowTransition(state: state, commands: commands)

        case .notYet, .pending:
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)
        }
    }

    private static func promiseCheck(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .choice(.promiseAlive):
            state.isFinished = true
            return FlowTransition(
                state: state,
                commands: [.speak(state.picker.pickText(.noonPromiseAliveAck)), .finish(.completed)]
            )

        case .choice(.changeTime):
            state.isPromiseCheck = false
            state.isChangingTime = true
            let line = state.picker.pickText(.morningTimePlaceQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(ListenRequest(
                        step: .noonStatus,
                        silenceSeconds: FlowMachine.firstSilenceSeconds,
                        input: state.mode,
                        examples: DialogueCopy.timeExampleIDs.map(Choice.init)
                    )),
                ]
            )

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - N2

    private static func blocker(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            state.blocker = text
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.noonBlocker, text: text, state: state, hasAudio: FlowMachine.hasAudio(state)) {
                commands.append(save)
            }
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - N3

    private static func shrink(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            state.microAction = shrunk(state.microAction, to: text)
            state.isFinished = true
            return FlowTransition(
                state: state,
                commands: [.speak(state.picker.pickText(.noonShrinkAccepted)), .finish(.completed)]
            )

        case .choice(let id):
            if let action = DialogueCopy.actionText(id) {
                state.microAction = shrunk(state.microAction, to: action)
                state.isFinished = true
                return FlowTransition(
                    state: state,
                    commands: [.speak(state.picker.pickText(.noonShrinkAccepted)), .finish(.completed)]
                )
            }
            switch id {
            case .cannotDecide, .shrinkMore:
                // 段階表を 1 段下るのは「決められない」を選んだときだけ。
                state.microAction = state.microAction.map {
                    MicroAction(text: $0.text, estimatedMinutes: $0.estimatedMinutes, shrinkCount: $0.shrinkCount + 1)
                }
                return enter(.noonShrink, in: state)

            case .retryInOneHour:
                state.isFinished = true
                return FlowTransition(
                    state: state,
                    commands: [
                        .scheduleNotification(NotificationRequest(kind: .actionTime, timePhrase: DialogueCopy.label(.timeInOneHour))),
                        .speak(state.picker.pickText(.noonRetryLaterAck)),
                        .finish(.completed),
                    ]
                )

            case .dropToday:
                state.isFinished = true
                return FlowTransition(
                    state: state,
                    commands: [
                        .cancelNotification(.actionTime),
                        .speak(state.picker.pickText(.noonDropAck)),
                        .finish(.completed),
                    ]
                )

            case .moveToTomorrow:
                state.tomorrow = state.microAction?.text ?? state.topic
                state.isFinished = true
                return FlowTransition(
                    state: state,
                    commands: [
                        .cancelNotification(.actionTime),
                        .speak(state.picker.pickText(.noonMoveToTomorrowAck)),
                        .finish(.completed),
                    ]
                )

            default:
                return FlowTransition(state: state, commands: [])
            }

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    private static func shrunk(_ action: MicroAction?, to text: String) -> MicroAction {
        guard let action else { return MicroAction(text: text, shrinkCount: 1) }
        return action.shrunk(to: text, estimatedMinutes: action.estimatedMinutes)
    }
}
