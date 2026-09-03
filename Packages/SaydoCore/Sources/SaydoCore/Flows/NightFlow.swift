import Foundation

/// 夜の会話 E0〜E1（実装計画 §7.2）。
///
/// 反省会にしない。前進が無い日も、その日を否定的にラベル付けしない。
public enum NightFlow {

    static func start(_ entry: FlowEntry, picker: CopyPicker) -> FlowTransition {
        let state = FlowState(
            sessionType: .night,
            step: .nightProgress,
            mode: entry.mode,
            picker: picker,
            outcome: entry.outcome,
            carryover: entry.carryover,
            isVoicelessDay: entry.isVoicelessDay
        )
        return enter(.nightProgress, in: state)
    }

    static func enter(_ step: FlowStep, in state: FlowState) -> FlowTransition {
        var state = state
        state.step = step

        switch step {
        case .nightProgress:
            let line = state.picker.pickText(.nightProgressQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        case .nightTomorrow:
            let line = state.picker.pickText(.nightTomorrowQuestion)
            return FlowTransition(
                state: state,
                commands: [
                    .speak(line),
                    .listen(FlowMachine.listenRequest(for: state, silenceSeconds: FlowMachine.firstSilenceSeconds)),
                ]
            )

        default:
            return FlowMachine.enter(step, in: state)
        }
    }

    /// E0 で前進が無い日に出す 2 つのチップだけ。企画書 §9 の 6 選択肢はここでは出さない。
    static let noProgressChoices: [Choice] = [Choice(.shrinkMore), Choice(.moveToTomorrow)]

    /// 前進が無いと読める答え。
    static let noProgressAnswers = [
        "ない", "ないです", "なし", "特にない", "特になし", "とくにない",
        "何もできなかった", "なにもできなかった", "できなかった", "進んでない", "進んでいない",
    ]

    static func isNoProgress(_ text: String) -> Bool {
        noProgressAnswers.contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func handle(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        switch state.step {
        case .nightProgress: progress(event, in: state)
        case .nightTomorrow: tomorrow(event, in: state)
        default: FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - E0

    private static func progress(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }

            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.nightProgress, text: text, state: state, hasAudio: FlowMachine.hasAudio(state)) {
                commands.append(save)
            }

            if isNoProgress(text) {
                // 「今日はそういう日。」とだけ言い、チップは 2 つに絞る。
                commands.append(.speak(state.picker.pickText(.nightNoProgress)))
                commands.append(.showChoices(noProgressChoices))
                return FlowTransition(state: state, commands: commands)
            }

            state.progress = text
            commands.append(.speak(state.picker.pickText(.nightProgressAck)))
            let next = FlowMachine.advance(from: state)
            return FlowTransition(state: next.state, commands: commands + next.commands)

        case .choice(let id) where NightFlow.noProgressChoices.contains(where: { $0.id == id }):
            state.nightDecision = id
            return FlowMachine.advance(from: state)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }

    // MARK: - E1

    private static func tomorrow(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        switch event {
        case .transcript(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard FlowMachine.isUsable(text) else {
                return FlowMachine.retryOrFallback(state)
            }
            // 翌朝の M0 に渡す引き継ぎ。
            state.tomorrow = text
            state.isFinished = true
            var commands: [FlowCommand] = []
            if let save = FlowMachine.save(.nightTomorrow, text: text, state: state, hasAudio: FlowMachine.hasAudio(state)) {
                commands.append(save)
            }
            commands.append(.speak(state.picker.pickText(.nightEnding)))
            commands.append(.finish(.completed))
            return FlowTransition(state: state, commands: commands)

        default:
            return FlowTransition(state: state, commands: [])
        }
    }
}
