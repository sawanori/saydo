import Foundation

// MARK: - 入力イベント

/// 会話に入ってくる出来事（実装計画 §7.2）。
public enum FlowEvent: Sendable, Equatable, Hashable, Codable {
    /// 音声または短文入力の確定結果。
    case transcript(String)
    /// 選択肢を選んだ。
    case choice(ChoiceID)
    /// 待ち時間が尽きた。
    case timeout(TimeoutKind)
    /// 宣言音声の再生が終わった。
    case playbackFinished
    /// 本人がこの質問を飛ばした。
    case skip
    /// 着信・Siri 起動・オーディオ経路変更で中断した。
    case interrupted

    public enum TimeoutKind: String, Sendable, Equatable, Hashable, Codable {
        /// 聞く区間が沈黙のまま終わった。
        case silence
        /// セッション全体のタイムボックス（朝 3 分 / 昼 1 分 / 夜 1 分）を超えた。
        case timebox
    }
}

/// 選択肢の識別子。
public enum ChoiceID: Sendable, Equatable, Hashable, Codable {
    // M0 引き継ぎ確認
    case carryoverKeep
    case carryoverChange
    case differentThing

    // 企画書 §9 の 6 選択肢（E0 では使わない）
    case shrinkMore
    case dropToday
    case moveToTomorrow
    case askSomeone
    case setDeadline
    case differentWay

    // M1
    case reason(ReasonCategory)

    // M2 / N3 の例示（一般形 4 つ）
    case exampleOpen
    case exampleWriteOneLine
    case examplePutOnDesk
    case exampleSearchName

    // M3 の時刻の例示
    case timeInOneHour
    case timeAfternoon
    case timeEvening
    case timePick

    // M4（「話せない時」モードのみ）
    case declareNow
    case declareLater

    // N1
    case status(CommitmentOutcome)

    // N3
    case cannotDecide
    case retryInOneHour

    // 昼の入口（行動時刻より前）
    case promiseAlive
    case changeTime
}

/// 画面に出す選択肢。
public struct Choice: Sendable, Equatable, Hashable, Codable, Identifiable {
    public let id: ChoiceID
    public let label: String

    public init(_ id: ChoiceID) {
        self.id = id
        self.label = DialogueCopy.label(id)
    }
}

// MARK: - 命令

/// 入力の受け方。「話せない時」モードとマイク拒否では `.text` になる。
public enum InputMode: String, Sendable, Equatable, Hashable, Codable {
    case voice
    case text
}

/// 聞く区間の指定。
public struct ListenRequest: Sendable, Equatable, Hashable, Codable {
    /// どのステップの答えを待っているか。
    public var step: FlowStep
    /// 沈黙をどれだけ待つか（初回 5 秒、催促の後は 10 秒）。
    public var silenceSeconds: Int
    /// 聞く区間の上限（実装計画 §7.2 では 20 秒）。
    public var maxSeconds: Int
    /// 音声で聞くか、短文入力で受けるか。
    public var input: InputMode
    /// 答えに詰まったときの例示。**選択肢ではない**ので、これを出しても
    /// 「チップは M1・N1・E0 だけ」という規則には触れない（実装計画 §7.2）。
    public var examples: [Choice]

    public init(
        step: FlowStep,
        silenceSeconds: Int,
        maxSeconds: Int = FlowMachine.listenMaxSeconds,
        input: InputMode,
        examples: [Choice] = []
    ) {
        self.step = step
        self.silenceSeconds = silenceSeconds
        self.maxSeconds = maxSeconds
        self.input = input
        self.examples = examples
    }
}

/// 宣言の録音指定（M4）。
public struct RecordRequest: Sendable, Equatable, Hashable, Codable {
    public var step: FlowStep
    public var maxSeconds: Int

    public init(step: FlowStep, maxSeconds: Int = FlowMachine.declarationMaxSeconds) {
        self.step = step
        self.maxSeconds = maxSeconds
    }
}

/// 朝の宣言の返し方（N0）。
public struct PlaybackRequest: Sendable, Equatable, Hashable, Codable {
    public enum Target: String, Sendable, Equatable, Hashable, Codable {
        /// 宣言音声を再生する。
        case declarationAudio
        /// 「声なし」の日は宣言テキストを大きく表示する。
        case declarationText
    }

    public var target: Target

    public init(target: Target) {
        self.target = target
    }
}

/// `VoiceEntry` の種類（実装計画 §10）。
public enum VoiceEntryKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case avoidance
    case reason
    case declaration
    case status
    case blocker
    case progress
    case tomorrow

    /// 保存するステップと種類は 1 対 1。ここに無いステップでは保存しない。
    public static func kind(for step: FlowStep) -> VoiceEntryKind? {
        switch step {
        case .morningAvoidance: .avoidance
        case .morningReason: .reason
        case .morningDeclaration: .declaration
        case .noonStatus: .status
        case .noonBlocker: .blocker
        case .nightProgress: .progress
        case .nightTomorrow: .tomorrow
        case .morningMicroAction, .morningPlannedTime, .noonPlayback, .noonShrink, .finished: nil
        }
    }
}

/// 保存命令。
public struct SaveInstruction: Sendable, Equatable, Hashable, Codable {
    public var kind: VoiceEntryKind
    public var step: FlowStep
    /// 文字起こし、または選択肢の言葉。
    public var text: String
    /// 音声ファイルを伴うか。選択肢と短文入力で答えた場合は false。
    public var hasAudio: Bool

    public init(kind: VoiceEntryKind, step: FlowStep, text: String, hasAudio: Bool) {
        self.kind = kind
        self.step = step
        self.text = text
        self.hasAudio = hasAudio
    }
}

/// 通知の登録・取り消し。`Date` への変換は SaydoCore の外（task_005b / task_009）で行う。
public struct NotificationRequest: Sendable, Equatable, Hashable, Codable {
    public enum Kind: String, Sendable, Equatable, Hashable, Codable {
        /// 行動時刻の通知（「朝のあなたからです。」）。
        case actionTime
        /// 宣言を後回しにしたときの、一人になれる時刻の 1 回だけの通知（retention R1）。
        case declarationReminder
        /// 固定の昼通知。
        case noonFixed
        /// 固定の夜通知。
        case night
    }

    public var kind: Kind
    /// 本人の言葉の時刻表現（「14時」「1時間後」）。解決は外で行う。
    public var timePhrase: String?
    /// 1 回だけ送って再通知しないか。
    public var onlyOnce: Bool

    public init(kind: Kind, timePhrase: String? = nil, onlyOnce: Bool = false) {
        self.kind = kind
        self.timePhrase = timePhrase
        self.onlyOnce = onlyOnce
    }
}

/// 会話の終わり方。
public enum FlowCompletion: String, Sendable, Equatable, Hashable, Codable {
    /// 最後まで進んだ。
    case completed
    /// 逃げたいことが無い良い日（retention R6）。`Commitment` は作らない。
    case goodDay
    /// 中断した。同じ `FlowStep` から再開する。
    case suspended
    /// タイムボックスを超えた。
    case timeboxExceeded
}

/// 会話の外側に出す命令。FlowMachine 自身は副作用を持たない。
public enum FlowCommand: Sendable, Equatable, Hashable, Codable {
    case speak(String)
    case listen(ListenRequest)
    case showChoices([Choice])
    case record(RecordRequest)
    case play(PlaybackRequest)
    case save(SaveInstruction)
    case scheduleNotification(NotificationRequest)
    case cancelNotification(NotificationRequest.Kind)
    case finish(FlowCompletion)
}

// MARK: - 状態

/// 会話の途中状態。中断（`interrupted`）したらこれを保存し、次回起動時に同じ
/// `step` から再開する（実装計画 §7.2）。
public struct FlowState: Sendable, Equatable, Hashable, Codable {
    public var sessionType: SessionType
    public var step: FlowStep
    public var mode: InputMode
    public var picker: CopyPicker

    /// 逃げたいこと（本人の言葉）。
    public var avoidance: String
    /// 理由。声で答えた場合は分類を待たずに nil のまま進む（会話を止めない）。
    public var reason: ReasonCategory?
    /// 5 分以下の行動。
    public var microAction: MicroAction?
    /// M3 の答え（「14時に自宅で」）。時刻と場所への分解は task_005b が行う。
    public var plannedAnswer: String?
    /// 宣言の言葉。
    public var declaration: String
    /// 宣言を「後で声で」に回したか（retention R1）。
    public var isDeclarationDeferred: Bool
    /// 昼に聞いた「何が止めているか」。
    public var blocker: String?
    /// 夜の前進。
    public var progress: String?
    /// 明日へ引き継ぐ言葉。
    public var tomorrow: String?
    public var outcome: CommitmentOutcome
    /// 前夜からの引き継ぎ。
    public var carryover: String?
    /// 引き継ぎ確認で本人が選んだこと。
    public var carryoverDecision: ChoiceID?
    /// 夜に前進が無かった日に本人が選んだこと。
    public var nightDecision: ChoiceID?

    /// 「特にない」で終わった良い日か（retention R6）。
    public var isGoodDay: Bool
    /// 短縮版の朝フロー（M0 → M2 → M4）か。
    public var isShortMorning: Bool
    /// 行動時刻より前の「まだ生きてる？」確認中か。
    public var isPromiseCheck: Bool
    /// 「時間を変える」を選んで、新しい時刻を聞いている最中か。
    public var isChangingTime: Bool
    /// 「声なし」の日か（マイク拒否・宣言の後回し）。
    public var isVoicelessDay: Bool

    /// 現在のステップで沈黙した回数（0 → 催促、1 → スキップ）。
    public var silenceCount: Int
    /// 現在のステップで聞き直した回数（上限 2 回）。
    public var retryCount: Int
    /// 中断中か。
    public var isSuspended: Bool
    /// 終わったか。
    public var isFinished: Bool

    public init(
        sessionType: SessionType,
        step: FlowStep,
        mode: InputMode = .voice,
        picker: CopyPicker = CopyPicker(),
        avoidance: String = "",
        reason: ReasonCategory? = nil,
        microAction: MicroAction? = nil,
        plannedAnswer: String? = nil,
        declaration: String = "",
        isDeclarationDeferred: Bool = false,
        blocker: String? = nil,
        progress: String? = nil,
        tomorrow: String? = nil,
        outcome: CommitmentOutcome = .pending,
        carryover: String? = nil,
        carryoverDecision: ChoiceID? = nil,
        nightDecision: ChoiceID? = nil,
        isGoodDay: Bool = false,
        isShortMorning: Bool = false,
        isPromiseCheck: Bool = false,
        isChangingTime: Bool = false,
        isVoicelessDay: Bool = false,
        silenceCount: Int = 0,
        retryCount: Int = 0,
        isSuspended: Bool = false,
        isFinished: Bool = false
    ) {
        self.sessionType = sessionType
        self.step = step
        self.mode = mode
        self.picker = picker
        self.avoidance = avoidance
        self.reason = reason
        self.microAction = microAction
        self.plannedAnswer = plannedAnswer
        self.declaration = declaration
        self.isDeclarationDeferred = isDeclarationDeferred
        self.blocker = blocker
        self.progress = progress
        self.tomorrow = tomorrow
        self.outcome = outcome
        self.carryover = carryover
        self.carryoverDecision = carryoverDecision
        self.nightDecision = nightDecision
        self.isGoodDay = isGoodDay
        self.isShortMorning = isShortMorning
        self.isPromiseCheck = isPromiseCheck
        self.isChangingTime = isChangingTime
        self.isVoicelessDay = isVoicelessDay
        self.silenceCount = silenceCount
        self.retryCount = retryCount
        self.isSuspended = isSuspended
        self.isFinished = isFinished
    }

    /// `DialogueEngine` に渡す入力に変換する。
    public var dialogueContext: DialogueContext {
        DialogueContext(
            sessionType: sessionType,
            step: step,
            avoidance: avoidance,
            reason: reason,
            domain: nil,
            microAction: microAction,
            blocker: blocker,
            carryover: carryover,
            outcome: outcome
        )
    }

    /// 話題として文言に差し込む本人の名詞（retention R5）。
    var topic: String {
        if !avoidance.isEmpty { return avoidance }
        if let carryover, !carryover.isEmpty { return carryover }
        return ""
    }
}

/// 会話の入口の条件。フローを開く前に呼び出し側が埋める。
public struct FlowEntry: Sendable, Equatable, Hashable, Codable {
    public var sessionType: SessionType
    /// 「話せない時」モードとマイク拒否では `.text`。
    public var mode: InputMode
    /// 前夜からの引き継ぎ。
    public var carryover: String?
    /// 前回の記録からの空白日数。2 日以上なら再入場の文言に差し替える（retention R4）。
    public var daysSinceLastRecord: Int?
    /// 当日の `Commitment` があるか。
    public var hasCommitmentToday: Bool
    /// 当日の `Commitment` の結果。
    public var outcome: CommitmentOutcome
    /// 現在時刻が `plannedAt` より前か。
    public var isBeforePlannedTime: Bool
    /// 宣言に添えた時刻の表示（「14時」）。
    public var plannedTimeLabel: String?
    /// 「声なし」の日か。
    public var isVoicelessDay: Bool
    /// 文言選択のための通し日番号。
    public var day: Int
    /// 使ってきた文言の履歴。
    public var copyHistory: [CopyPicker.Use]
    /// 中断から再開する場合の途中状態。
    public var resume: FlowState?

    public init(
        sessionType: SessionType,
        mode: InputMode = .voice,
        carryover: String? = nil,
        daysSinceLastRecord: Int? = nil,
        hasCommitmentToday: Bool = false,
        outcome: CommitmentOutcome = .pending,
        isBeforePlannedTime: Bool = false,
        plannedTimeLabel: String? = nil,
        isVoicelessDay: Bool = false,
        day: Int = 0,
        copyHistory: [CopyPicker.Use] = [],
        resume: FlowState? = nil
    ) {
        self.sessionType = sessionType
        self.mode = mode
        self.carryover = carryover
        self.daysSinceLastRecord = daysSinceLastRecord
        self.hasCommitmentToday = hasCommitmentToday
        self.outcome = outcome
        self.isBeforePlannedTime = isBeforePlannedTime
        self.plannedTimeLabel = plannedTimeLabel
        self.isVoicelessDay = isVoicelessDay
        self.day = day
        self.copyHistory = copyHistory
        self.resume = resume
    }
}

/// 遷移の結果。
public struct FlowTransition: Sendable, Equatable {
    public var state: FlowState
    public var commands: [FlowCommand]

    public init(state: FlowState, commands: [FlowCommand]) {
        self.state = state
        self.commands = commands
    }
}

// MARK: - 状態機械

/// `(state, event) -> (state, [Command])` の純関数。副作用を持たず、時計にも触らない。
public enum FlowMachine {

    /// 沈黙を待つ秒数（1 回目）。
    public static let firstSilenceSeconds = 5
    /// 催促の後に沈黙を待つ秒数。この後はその質問をスキップする。
    public static let secondSilenceSeconds = 10
    /// 聞く区間の上限。
    public static let listenMaxSeconds = 20
    /// 宣言の録音の上限。
    public static let declarationMaxSeconds = 30
    /// 聞き直しの上限。
    public static let maxRetries = 2

    /// 会話を開く。入口の条件で流すフローが変わる。
    public static func start(_ entry: FlowEntry) -> FlowTransition {
        if var resumed = entry.resume {
            resumed.isSuspended = false
            resumed.isFinished = false
            resumed.silenceCount = 0
            resumed.retryCount = 0
            return enter(resumed.step, in: resumed)
        }

        let picker = CopyPicker(day: entry.day, history: entry.copyHistory)
        switch entry.sessionType {
        case .morning:
            return MorningFlow.start(entry, picker: picker)
        case .night:
            return NightFlow.start(entry, picker: picker)
        case .noon, .adhoc:
            return NoonFlow.start(entry, picker: picker)
        }
    }

    /// 出来事を受けて次の状態と命令を返す。
    public static func handle(_ event: FlowEvent, in state: FlowState) -> FlowTransition {
        var state = state
        guard !state.isFinished else { return FlowTransition(state: state, commands: []) }

        switch event {
        case .interrupted:
            // 途中状態を残したままセッションを閉じる。step は動かさない。
            state.isSuspended = true
            state.isFinished = true
            return FlowTransition(state: state, commands: [.finish(.suspended)])

        case .timeout(.timebox):
            let line = state.picker.pickText(.timeboxExceeded)
            state.isFinished = true
            return FlowTransition(state: state, commands: [.speak(line), .finish(.timeboxExceeded)])

        case .timeout(.silence):
            if state.silenceCount == 0 {
                state.silenceCount = 1
                let nudge = state.picker.pickText(.silenceNudge)
                return FlowTransition(
                    state: state,
                    commands: [.speak(nudge), .listen(listenRequest(for: state, silenceSeconds: secondSilenceSeconds))]
                )
            }
            return advance(from: state)

        case .skip:
            return advance(from: state)

        default:
            break
        }

        // 短縮版の朝フローは昼・手動の入口から開くので、どのフローが受けるかは
        // `sessionType` ではなく現在の `FlowStep` で決める。
        switch state.step.sessionType ?? state.sessionType {
        case .morning:
            return MorningFlow.handle(event, in: state)
        case .noon, .adhoc:
            return NoonFlow.handle(event, in: state)
        case .night:
            return NightFlow.handle(event, in: state)
        }
    }

    // MARK: - 共通の部品

    /// ステップに入るときの発話と入力要求。
    static func enter(_ step: FlowStep, in state: FlowState) -> FlowTransition {
        var state = state
        state.step = step
        state.silenceCount = 0
        state.retryCount = 0

        if step == .finished {
            state.isFinished = true
            return FlowTransition(state: state, commands: [.finish(.completed)])
        }

        switch step {
        case .morningAvoidance, .morningReason, .morningMicroAction, .morningPlannedTime, .morningDeclaration:
            return MorningFlow.enter(step, in: state)
        case .noonPlayback, .noonStatus, .noonBlocker, .noonShrink:
            return NoonFlow.enter(step, in: state)
        case .nightProgress, .nightTomorrow:
            return NightFlow.enter(step, in: state)
        case .finished:
            state.isFinished = true
            return FlowTransition(state: state, commands: [.finish(.completed)])
        }
    }

    /// 次のステップへ進む。
    static func advance(from state: FlowState) -> FlowTransition {
        enter(nextStep(after: state.step, in: state), in: state)
    }

    /// フローごとの並び。短縮版の朝フローは M1 と M3 を飛ばす。
    static func nextStep(after step: FlowStep, in state: FlowState) -> FlowStep {
        switch step {
        case .morningAvoidance:
            state.isShortMorning ? .morningMicroAction : .morningReason
        case .morningReason:
            .morningMicroAction
        case .morningMicroAction:
            state.isShortMorning ? .morningDeclaration : .morningPlannedTime
        case .morningPlannedTime:
            .morningDeclaration
        case .morningDeclaration:
            .finished
        case .noonPlayback:
            .noonStatus
        case .noonStatus:
            .noonBlocker
        case .noonBlocker:
            .noonShrink
        case .noonShrink:
            .finished
        case .nightProgress:
            .nightTomorrow
        case .nightTomorrow:
            .finished
        case .finished:
            .finished
        }
    }

    /// 現在のステップの聞く区間。
    static func listenRequest(for state: FlowState, silenceSeconds: Int) -> ListenRequest {
        ListenRequest(
            step: state.step,
            silenceSeconds: silenceSeconds,
            input: state.mode,
            examples: examples(for: state.step)
        )
    }

    /// 例示（選択肢ではない）。
    static func examples(for step: FlowStep) -> [Choice] {
        switch step {
        case .morningMicroAction, .noonShrink:
            DialogueCopy.exampleActionIDs.map(Choice.init)
        case .morningPlannedTime:
            DialogueCopy.timeExampleIDs.map(Choice.init)
        default:
            []
        }
    }

    /// このステップで「答えを選ばせる」チップ（実装計画 §7.2）。
    ///
    /// M1（理由）・N1（状態）・E0 の前進なし分岐の 3 か所だけ。
    /// M0 の引き継ぎ確認と N3 は「答え」ではなく進め方の選択なので、ここには含めない。
    static func answerChoices(for state: FlowState) -> [Choice] {
        switch state.step {
        case .morningReason:
            ReasonCategory.allCases.map { Choice(.reason($0)) }
        case .noonStatus:
            (state.isPromiseCheck || state.isChangingTime) ? [] : NoonFlow.statusChoices
        default:
            []
        }
    }

    /// 文字起こしが使えないときの聞き直し。
    ///
    /// 最大 2 回まで聞き直し、その後は選択肢に落とす。選択肢が無いステップは
    /// その質問をスキップして次へ進む（実装計画 §7.2 の沈黙時と同じ扱い）。
    static func retryOrFallback(_ state: FlowState) -> FlowTransition {
        var state = state
        if state.retryCount < maxRetries {
            state.retryCount += 1
            state.silenceCount = 0
            let line = state.picker.pickText(.retryPrompt)
            return FlowTransition(
                state: state,
                commands: [.speak(line), .listen(listenRequest(for: state, silenceSeconds: firstSilenceSeconds))]
            )
        }
        let choices = answerChoices(for: state)
        guard !choices.isEmpty else { return advance(from: state) }
        let line = state.picker.pickText(.retryPrompt)
        return FlowTransition(state: state, commands: [.speak(line), .showChoices(choices)])
    }

    /// 文字起こしが使えるか（空・2 文字未満は使えない。実装計画 §9）。
    static func isUsable(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    /// 保存命令を作る。保存するステップと `VoiceEntryKind` は 1 対 1。
    static func save(_ step: FlowStep, text: String, state: FlowState, hasAudio: Bool) -> FlowCommand? {
        guard let kind = VoiceEntryKind.kind(for: step) else { return nil }
        return .save(SaveInstruction(kind: kind, step: step, text: text, hasAudio: hasAudio))
    }

    /// 音声で答えたか（「話せない時」モードと選択肢では音声を持たない）。
    static func hasAudio(_ state: FlowState) -> Bool {
        state.mode == .voice
    }
}
