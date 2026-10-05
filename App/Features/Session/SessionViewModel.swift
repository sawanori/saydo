import AVFoundation
import Foundation
import Observation
import OSLog
import SwiftData
import SaydoCore

// MARK: - 通知の登録契約

/// `FlowMachine` の `scheduleNotification` / `cancelNotification` 命令を実際の通知に落とす契約。
///
/// 実装は task_009（`App/Notifications/NotificationScheduler.swift`）が持つ。ここでは
/// `SessionViewModel` が依存する境界だけを定義する。時刻表現（`NotificationRequest.timePhrase`）は
/// `JapaneseTimeParser` で解決してから `fireDate` として渡す（解決できなければ nil）。
protocol NotificationScheduling: Sendable {
    /// 通知を 1 件登録する。`commitmentID` は通知タップからフローを開くために `userInfo` に載せる。
    func schedule(_ request: NotificationRequest, fireDate: Date?, commitmentID: UUID?, on day: Date) async throws

    /// その日の該当する通知を取り消す。
    func cancel(_ kind: NotificationRequest.Kind, on day: Date) async throws
}

// MARK: - 保存の契約

/// `SessionViewModel` が使う保存操作だけを切り出した契約。
///
/// `Repository` は `@ModelActor` の具象アクターなので、テストで差し替えるためにこの契約を挟む。
/// 実体は `RepositorySessionStore`、テストはインメモリの実装を注入する。
protocol SessionStore: Sendable {
    func todayCommitment(on date: Date) async throws -> CommitmentSnapshot?
    func createCommitment(_ draft: CommitmentDraft) async throws -> CommitmentSnapshot
    func updateOutcome(
        commitmentID: UUID,
        outcome: CommitmentOutcome,
        progressNote: String?,
        at date: Date
    ) async throws -> CommitmentSnapshot
    func shrink(
        commitmentID: UUID,
        to text: String,
        estimatedMinutes: Int,
        at date: Date
    ) async throws -> CommitmentSnapshot
    /// 昼 N3・夜 E0 の選択と N1 の「やった」を、逃げている対象の状態に写す（task_011）。
    func updateAvoidanceStatus(commitmentID: UUID, status: AvoidanceStatus, at date: Date) async throws
    func appendVoiceEntry(_ draft: VoiceEntryDraft) async throws -> VoiceEntrySnapshot
    func deleteVoiceEntry(id: UUID) async throws
    func entries(for day: Date) async throws -> [VoiceEntrySnapshot]
    func carryover(for day: Date) async throws -> CarryoverSnapshot?
    func saveCarryover(
        forDay day: Date,
        text: String,
        sourceEntryID: UUID?,
        at date: Date
    ) async throws -> CarryoverSnapshot
    func lastEntryDate() async throws -> Date?

    /// 会話の開始を `SessionLog` に残し、その id を返す（実装計画 §10 / fix-decisions P1.3）。
    func startSessionLog(sessionType: SessionType, startedAt: Date, tier: DialogueTier) async throws -> UUID
    /// 会話の終わりを `SessionLog` に書き足す。
    func finishSessionLog(
        id: UUID,
        endedAt: Date,
        completed: Bool,
        lastStep: FlowStep?,
        guardrailReplacedCount: Int
    ) async throws
}

/// `Repository`（`@ModelActor`）を `SessionStore` として渡すための薄い包み。
///
/// `Repository` の各メソッドは既定引数（`calendar` など）を持つため、そのままでは
/// プロトコル要件の witness にならない。ここで引数を明示して転送する。
struct RepositorySessionStore: SessionStore {
    let repository: Repository

    init(_ repository: Repository) {
        self.repository = repository
    }

    func todayCommitment(on date: Date) async throws -> CommitmentSnapshot? {
        try await repository.todayCommitment(on: date)
    }

    func createCommitment(_ draft: CommitmentDraft) async throws -> CommitmentSnapshot {
        try await repository.createCommitment(draft)
    }

    func updateOutcome(
        commitmentID: UUID,
        outcome: CommitmentOutcome,
        progressNote: String?,
        at date: Date
    ) async throws -> CommitmentSnapshot {
        try await repository.updateOutcome(
            commitmentID: commitmentID,
            outcome: outcome,
            progressNote: progressNote,
            at: date
        )
    }

    func shrink(
        commitmentID: UUID,
        to text: String,
        estimatedMinutes: Int,
        at date: Date
    ) async throws -> CommitmentSnapshot {
        try await repository.shrink(
            commitmentID: commitmentID,
            to: text,
            estimatedMinutes: estimatedMinutes,
            at: date
        )
    }

    func updateAvoidanceStatus(commitmentID: UUID, status: AvoidanceStatus, at date: Date) async throws {
        try await repository.updateAvoidanceStatus(commitmentID: commitmentID, status: status, at: date)
    }

    func appendVoiceEntry(_ draft: VoiceEntryDraft) async throws -> VoiceEntrySnapshot {
        try await repository.appendVoiceEntry(draft)
    }

    func deleteVoiceEntry(id: UUID) async throws {
        try await repository.deleteVoiceEntry(id: id)
    }

    func entries(for day: Date) async throws -> [VoiceEntrySnapshot] {
        try await repository.entries(for: day)
    }

    func carryover(for day: Date) async throws -> CarryoverSnapshot? {
        try await repository.carryover(for: day)
    }

    func saveCarryover(
        forDay day: Date,
        text: String,
        sourceEntryID: UUID?,
        at date: Date
    ) async throws -> CarryoverSnapshot {
        try await repository.saveCarryover(forDay: day, text: text, sourceEntryID: sourceEntryID, at: date)
    }

    func lastEntryDate() async throws -> Date? {
        try await repository.lastEntryDate()
    }

    func startSessionLog(sessionType: SessionType, startedAt: Date, tier: DialogueTier) async throws -> UUID {
        try await repository.startSessionLog(sessionType: sessionType, startedAt: startedAt, tier: tier)
    }

    func finishSessionLog(
        id: UUID,
        endedAt: Date,
        completed: Bool,
        lastStep: FlowStep?,
        guardrailReplacedCount: Int
    ) async throws {
        try await repository.finishSessionLog(
            id: id,
            endedAt: endedAt,
            completed: completed,
            lastStep: lastStep,
            guardrailReplacedCount: guardrailReplacedCount
        )
    }
}

// MARK: - 画面の状態

/// 会話が進めなくなった理由（実装計画 §8 の `error(micDenied / assetDownloading)`）。
enum SessionFailure: String, Sendable, Equatable {
    /// マイクが使えない。テキスト経路に切り替えて完走させ、設定アプリへの導線を出す。
    case micDenied
    /// ja-JP の認識モデルを取得中。
    case assetDownloading
    /// マイクの権限はあるのに録音を始められなかった（やり直しても駄目だった）。その質問だけ文字で受ける。
    case captureFailed
}

/// 会話画面の状態（実装計画 §8）。
enum SessionPhase: Sendable, Equatable {
    case idle
    case speaking
    case listening
    case thinking
    case choosing
    case recordingDeclaration
    case playback
    case done
    case error(SessionFailure)
}

/// 朝の宣言の返し方（retention R8 / 実装計画 §7.3）。
///
/// イヤホン未接続かつ音量が大きいまま鳴らすと、本人の声が周りに漏れる。再生と TTS の
/// **前**に本人に選ばせ、どれを選んでも体験が成立するようにする。
enum ListenMode: String, Sendable, Equatable, Hashable, CaseIterable {
    /// そのまま鳴らす（イヤホンが繋がっていればそちらへ回る）。
    case speaker
    /// 受話口で鳴らす。耳に当てて聞く。
    case receiver
    /// 音を出さず、宣言テキストを画面で読む。
    case readText
}

/// 時間待ちの注入点。テストは実時間を待たずに経路だけを検証する。
struct SessionTimer: Sendable {
    var sleep: @Sendable (Duration) async throws -> Void

    static let system = SessionTimer(sleep: { try await Task.sleep(for: $0) })
}

// MARK: - ViewModel

/// 会話画面の頭脳。`FlowMachine`（純関数）の命令を、音声・保存・通知の実体に配線する。
///
/// - 文言は一切持たない。話す言葉はすべて `FlowCommand.speak` として `DialogueCopy` から来る。
/// - `installTap` 由来の値は `VoiceCapture` が `@MainActor` に届けたものだけを扱う（計画 §7.3）。
@MainActor
@Observable
final class SessionViewModel {

    // MARK: 公開する状態

    private(set) var phase: SessionPhase = .idle
    /// いま読み上げている（読み上げ終えた）1 行。
    private(set) var spokenLine: String = ""
    /// 答えを選ばせるチップ（M1 / N1 / E0 の前進なし分岐だけ）。
    private(set) var choices: [Choice] = []
    /// 答えに詰まったときの例示。チップではない（実装計画 §7.2）。
    private(set) var examples: [Choice] = []
    /// 波形の描画に使うレベル履歴。
    let waveform = WaveformSampler()
    /// 認識の途中結果。
    private(set) var partialTranscript: String = ""
    /// M0 の文字起こし 1 行（retention R7）。
    private(set) var avoidanceTranscript: String = ""
    /// M0 の再録音がまだ使えるか（1 回だけ）。
    private(set) var canRetakeAvoidance = false
    /// マイク拒否・モデル取得中の掲示。会話は `phase` の側で進む。
    private(set) var notice: SessionFailure?
    /// 「声なし」の日か（マイク拒否・宣言の後回し。fix-decisions P2.3 / R1）。
    private(set) var isVoiceless = false
    /// 昼 N0 で画面に大きく出す宣言テキスト（「声なし」の日、または「文字で読む」を選んだとき）。
    private(set) var declarationTextToShow: String?
    /// M3 で本人が言った場所（`Commitment.plannedPlace` に保存する。統合判断 D1）。
    private(set) var plannedPlace: String = ""
    /// 再生と TTS の前に「イヤホンで聞く / 文字で読む」を出しているか（retention R8）。
    /// true の間は発話も再生も始まっていない。`chooseListenMode(_:)` で先へ進む。
    private(set) var listenModePrompt = false
    /// 本人が選んだ返し方。既定はそのまま鳴らす。
    private(set) var listenMode: ListenMode = .speaker
    /// 宣言音声の長さ（秒）。再生リボンの再生位置に使う。分からなければ 0。
    private(set) var declarationDurationSec: Double = 0
    /// 宣言音声を鳴らし始めた時刻。鳴っていなければ nil。
    private(set) var declarationPlaybackStartedAt: Date?
    /// 会話の終わり方。まだ終わっていなければ nil。
    private(set) var completion: FlowCompletion?
    /// 今日の宣言。
    private(set) var commitment: CommitmentSnapshot?
    /// Guardrails でテンプレートに置換した回数。Tier A（task_015）が積む。
    private(set) var guardrailReplacedCount = 0
    /// 中断して保存した途中状態。次回起動時に `start(resume:)` へ渡す。
    private(set) var suspendedState: FlowState?

    /// いまテキスト入力を受ける状態か。
    var acceptsTextInput: Bool { pendingListen?.input == .text }
    /// いまどの質問にいるか。会話が始まっていなければ nil。
    var currentStep: FlowStep? { state?.step }

    // MARK: 依存

    private let store: any SessionStore
    private let synthesizer: any Synthesizing
    private let capture: any VoiceCapturing
    private let transcriber: any Transcribing
    private let player: any Playing
    private let notifications: any NotificationScheduling
    private let engine: any DialogueEngine
    private let audioFiles: AudioFileStore
    /// 再生前の配慮（retention R8）の判定と出力経路。持たない場合は確認を出さない。
    private let audioSession: (any AudioSessionControlling)?
    private let copyHistoryStore: any CopyHistoryStoring
    private let timer: SessionTimer
    private let tier: DialogueTier
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    /// 実機での切り分け用（Console: subsystem com.nonturn.saydo category session）。本人の言葉は長さだけ出す。
    private let logger = Logger(subsystem: "com.nonturn.saydo", category: "session")

    // MARK: 内部の状態

    private var state: FlowState?
    private var sessionLogID: UUID?
    private var startedAt: Date?
    private var pendingListen: ListenRequest?
    private var timeboxTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var detector = SilenceDetector(duration: .standard)
    /// 直前に録った音声。`SaveInstruction.hasAudio` が true のときだけ使う。
    private var lastRecording: (relativePath: String, duration: TimeInterval)?
    /// M0 で保存した `VoiceEntry`。再録音のときに消す。
    private var avoidanceEntryID: UUID?
    /// M0 の録り直しをもう使ったか（1 回だけ。retention R7）。
    private var hasRetakenAvoidance = false
    /// M0 に戻るための途中状態。
    private var stateAtAvoidance: FlowState?
    /// 宣言（M4）の保存内容。`Commitment` を作るときに一緒に書く。
    private var pendingDeclaration: (text: String, audioPath: String?, duration: TimeInterval)?
    /// 宣言より先に来た通知命令。`Commitment` を作ってから登録する。
    private var pendingNotifications: [NotificationRequest] = []
    /// M1 を声で答えた場合の分類結果。
    private var classifiedReason: ReasonCategory?
    /// 最後に選んだチップ。会話の終わりに `AvoidanceItem.status` へ写すために持つ。
    private var lastChoiceID: ChoiceID?
    /// 逃げている対象の分野。
    private var classifiedDomain: TaskDomain = .other
    /// 「イヤホンで聞く / 文字で読む」の答えを待って止めてある命令列（retention R8）。
    private var pendingPlaybackCommands: [FlowCommand] = []

    // MARK: 進行の直列化（実装計画 §16.7）

    /// 会話を進める入力。画面の操作も見張りも、進行を自分のタスクでは実行せず、これを渡すだけにする。
    private enum Input: Sendable {
        case start(sessionType: SessionType, microphoneGranted: Bool, voicelessMode: Bool, resume: FlowState?)
        case event(FlowEvent)
        /// 録音の見張りが、無音・上限・失敗のどれかで聞き取りの終わりを見つけた。
        case captureEnded(generation: Int, relativePath: String, duration: TimeInterval)
        /// 沈黙の見張りが、待ち時間の終わりを見つけた。
        case silence(generation: Int)
        case retakeAvoidance
        case switchToText
        case listenMode(ListenMode)
    }

    private struct Envelope: Sendable {
        var input: Input
        /// 渡した時点の `interruptions`。処理が始まるまでに割り込まれたかを見分ける。
        var mark: Int
        /// 処理が終わったら再開する待ち手。見張りは待たないので nil。
        var done: CheckedContinuation<Void, Never>?
    }

    /// 進行の入口。受け取った入力は `init` で起こした 1 本のタスクが順に処理する。
    /// 入力を渡した側のタスクが止められても、進行は止まらない。
    private let inbox: AsyncStream<Envelope>.Continuation
    /// 聞き取りの世代。聞き取りを始めるたび・止めるたびに進める。準備や確定の `await` から
    /// 戻ったときにこれが変わっていたら、その聞き取りはもう古い。
    private var listenGeneration = 0
    /// 画面の操作と時間切れが進行に割り込んだ回数。
    private var interruptions = 0
    /// いま処理している入力の `Envelope.mark`。
    private var turnMark = 0
    /// いま答えを待っている命令（`.listen` か `.record`）。割り込みで止めた後、
    /// `FlowMachine` がその入力を受け流したときに聞き取りを戻すために持つ。
    private var waiting: FlowCommand?

    /// 声を聞いている聞き取り（宣言の録音を含む）の世代。文字の入力待ちでは進めない。
    private var hearingGeneration: Int?
    /// 時間切れが来たが、聞いている途中だったので、その答えが確定するまで待たせているか。
    private var timeboxIsDue = false

    /// いま処理している入力の後から割り込まれたか。割り込まれた入力の残りの
    /// 発話・聞き取り・再生は実行しない。
    private var isInterrupted: Bool { turnMark != interruptions }
    /// 声の聞き取りが動いているか。文字の入力待ちは見張りを持たないので含まない。
    private var isListening: Bool { captureTask != nil || silenceTask != nil }
    /// 本人の声を聞いている途中か（録音中、または録り終えて文字起こしの確定を待っている）。
    private var isHearingAnAnswer: Bool { hearingGeneration == listenGeneration && completion == nil }

    // MARK: 定数

    /// タイムボックス（実装計画 §7.2: 朝 3 分 / 昼 1 分 / 夜 1 分）。
    static func timebox(for sessionType: SessionType) -> Duration {
        switch sessionType {
        case .morning: .seconds(180)
        case .noon, .night, .adhoc: .seconds(60)
        }
    }

    init(
        store: any SessionStore,
        synthesizer: any Synthesizing,
        capture: any VoiceCapturing,
        transcriber: any Transcribing,
        player: any Playing,
        notifications: any NotificationScheduling,
        engine: any DialogueEngine = TemplateDialogueEngine(),
        audioFiles: AudioFileStore,
        audioSession: (any AudioSessionControlling)? = nil,
        copyHistory: any CopyHistoryStoring = UserDefaultsCopyHistoryStore(),
        timer: SessionTimer = .system,
        tier: DialogueTier = .b,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.synthesizer = synthesizer
        self.capture = capture
        self.transcriber = transcriber
        self.player = player
        self.notifications = notifications
        self.engine = engine
        self.audioFiles = audioFiles
        self.audioSession = audioSession
        self.copyHistoryStore = copyHistory
        self.timer = timer
        self.tier = tier
        self.calendar = calendar
        self.now = now

        let (inputs, inbox) = AsyncStream<Envelope>.makeStream()
        self.inbox = inbox
        Task { [weak self] in
            for await envelope in inputs {
                await self?.process(envelope)
                envelope.done?.resume()
            }
        }
    }

    deinit {
        inbox.finish()
    }

    // MARK: - 進行の入口

    /// 見張りから入力を渡す。待たない。
    private func post(_ input: Input) {
        inbox.yield(Envelope(input: input, mark: interruptions, done: nil))
    }

    /// 画面から入力を渡し、その処理が終わるまで待つ。
    private func deliver(_ input: Input) async {
        let mark = interruptions
        await withCheckedContinuation { done in
            inbox.yield(Envelope(input: input, mark: mark, done: done))
        }
    }

    /// 進行に割り込む。いまの聞き取りを止めて世代を進め、処理中（と処理待ち）の入力の
    /// 残りの発話・聞き取り・再生を捨てさせる。会話を閉じる割り込みは、鳴っている音も止める。
    private func cutIn(stoppingSound: Bool = false) {
        interruptions += 1
        stopListening()
        if stoppingSound {
            synthesizer.stop()
            player.stop()
        }
    }

    private func process(_ envelope: Envelope) async {
        turnMark = envelope.mark
        switch envelope.input {
        case .start(let sessionType, let microphoneGranted, let voicelessMode, let resume):
            await open(
                sessionType: sessionType,
                microphoneGranted: microphoneGranted,
                voicelessMode: voicelessMode,
                resume: resume
            )
        case .event(let event):
            await handle(event)
        case .captureEnded(let generation, let relativePath, let duration):
            await finishListening(generation: generation, relativePath: relativePath, duration: duration)
        case .silence(let generation):
            guard isCurrent(generation) else { return }
            logger.info("silence watch fired heardSpeech=\(self.detector.hasHeardSpeech, privacy: .public)")
            stopListening()
            await handle(.timeout(.silence))
        case .retakeAvoidance:
            await restartAvoidance()
        case .switchToText:
            await enterTextMode()
        case .listenMode(let mode):
            await continuePlayback(in: mode)
        }
    }

    // MARK: - 会話を開く

    /// 入口の条件を保存済みのデータから組み立てて会話を開く。
    ///
    /// - Parameters:
    ///   - sessionType: 通知またはボタンが指定したセッション。
    ///   - microphoneGranted: マイクが使えるか。使えなければテキスト経路で完走させる。
    ///   - voicelessMode: 「話せない時」モード（retention R1）。
    ///   - resume: 中断から再開する場合の途中状態。
    func start(
        sessionType: SessionType,
        microphoneGranted: Bool = true,
        voicelessMode: Bool = false,
        resume: FlowState? = nil
    ) async {
        await deliver(.start(
            sessionType: sessionType,
            microphoneGranted: microphoneGranted,
            voicelessMode: voicelessMode,
            resume: resume
        ))
    }

    private func open(
        sessionType: SessionType,
        microphoneGranted: Bool,
        voicelessMode: Bool,
        resume: FlowState?
    ) async {
        let today = now()
        let mode: InputMode = (microphoneGranted && !voicelessMode) ? .voice : .text
        // 会話の間だけ .playAndRecord にする（task_007 の申し送り: deactivate は ViewModel が明示的に呼ぶ）。
        _ = try? audioSession?.activate(mode: .standard)
        if !microphoneGranted {
            notice = .micDenied
        }
        isVoiceless = mode == .text

        let entry = await makeEntry(sessionType: sessionType, mode: mode, on: today, resume: resume)
        startedAt = today
        sessionLogID = try? await store.startSessionLog(sessionType: sessionType, startedAt: today, tier: tier)
        startTimebox(for: sessionType)

        var transition = FlowMachine.start(entry)
        restoreNoonContext(into: &transition.state)
        await apply(transition)
    }

    /// 昼の会話は当日の宣言の上で進む。`FlowEntry` には行動文を載せる場所が無いので、
    /// `NoonFlow` が組み立てた直後の状態にここで戻す（統合判断 D9）。
    ///
    /// これが無いと N3 の「今の行動文」が空になり、`shrinkCount` も 0 から数え直しになる。
    private func restoreNoonContext(into state: inout FlowState) {
        guard let today = commitment, state.step.sessionType == .noon else { return }
        if state.microAction == nil {
            state.microAction = today.microAction
        }
        if state.avoidance.isEmpty {
            state.avoidance = today.avoidanceTitle
        }
    }

    /// 入口の条件（実装計画 §7.2 の昼フローの 3 状態を含む）を保存済みのデータから作る。
    private func makeEntry(
        sessionType: SessionType,
        mode: InputMode,
        on day: Date,
        resume: FlowState?
    ) async -> FlowEntry {
        let today = try? await store.todayCommitment(on: day)
        commitment = today
        let carry = (try? await store.carryover(for: day)) ?? nil
        let lastEntry = (try? await store.lastEntryDate()) ?? nil

        var gap: Int?
        if let lastEntry {
            gap = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: lastEntry),
                to: calendar.startOfDay(for: day)
            ).day
        }

        var isBefore = false
        if let plannedAt = today?.plannedAt {
            isBefore = day < plannedAt
        }

        if let today, today.isVoiceless {
            isVoiceless = true
        }
        if let today {
            plannedPlace = today.plannedPlace ?? ""
            await loadDeclarationDuration(for: today, on: day)
        }

        let dayNumber = calendar.ordinality(of: .day, in: .era, for: day) ?? 0

        return FlowEntry(
            sessionType: sessionType,
            mode: mode,
            carryover: carry?.text,
            daysSinceLastRecord: gap,
            hasCommitmentToday: today != nil,
            outcome: today?.outcome ?? .pending,
            isBeforePlannedTime: isBefore,
            plannedTimeLabel: today?.plannedAt.map(Self.timeLabel(for:)),
            isVoicelessDay: today?.isVoiceless ?? (mode == .text),
            day: dayNumber,
            // 3 日以内に同じ文言を繰り返さない（retention R5）。履歴は端末に残す（統合判断 D2）。
            copyHistory: copyHistoryStore.load(currentDay: dayNumber),
            resume: resume
        )
    }

    /// 再生リボンの再生位置に使う宣言音声の長さ。宣言の `VoiceEntry` から読む。
    private func loadDeclarationDuration(for today: CommitmentSnapshot, on day: Date) async {
        guard today.declarationAudioPath != nil else {
            declarationDurationSec = 0
            return
        }
        let entries = (try? await store.entries(for: day)) ?? []
        declarationDurationSec = entries.first { $0.kind == .declaration }?.durationSec ?? 0
    }

    /// 「14:30」の形。文言そのものは `DialogueCopy` が持つので、ここでは値だけを作る。
    private static func timeLabel(for date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "ja_JP"))
        )
    }

    // MARK: - 画面から来る入力

    /// 短文入力または確定した文字起こしを流す。
    func submit(text: String) async {
        cutIn()
        await deliver(.event(.transcript(text)))
    }

    /// チップを選んだ。進行中の聞き取りは止め、その結果はもう使わない。
    func select(_ choice: Choice) async {
        choices = []
        lastChoiceID = choice.id
        cutIn()
        await deliver(.event(.choice(choice.id)))
    }

    /// この質問を飛ばす。
    func skip() async {
        cutIn()
        await deliver(.event(.skip))
    }

    /// 着信・Siri 起動・オーディオ経路変更（実装計画 §7.2 / fix-decisions P3.6）。
    /// 会話を閉じるときもこれを呼ぶ。読み上げと再生はその場で止める。
    func interrupt() async {
        cutIn(stoppingSound: true)
        await deliver(.event(.interrupted))
    }

    /// 沈黙の待ち時間が尽きた。1 回目は催促。2 回目は、必須でない質問ならスキップし、
    /// 必須の質問なら受け方を変えて留まる（分岐は `FlowMachine` が持つ）。
    func silenceElapsed() async {
        await deliver(.silence(generation: listenGeneration))
    }

    /// タイムボックス（朝 3 分 / 昼 1 分 / 夜 1 分）を超えた。読み上げ中でもその場で止める。
    /// 聞き取り中と宣言の録音中だけは打ち切らず、その答えが確定してから終える。
    func timeboxElapsed() async {
        guard expireTimebox() else { return }
        await deliver(.event(.timeout(.timebox)))
    }

    /// 時間切れを進行に割り込ませる。声を聞いている途中なら割り込まずに覚えておき、false を返す。
    private func expireTimebox() -> Bool {
        guard !isHearingAnAnswer else {
            logger.info("timebox deferred until the answer settles")
            timeboxIsDue = true
            return false
        }
        cutIn(stoppingSound: true)
        return true
    }

    /// 待たせていた時間切れを、答えを受けないまま聞き取りが止まった場面（文字への切り替え・録り直し）で実行する。
    private func endIfTimeboxIsDue() async -> Bool {
        guard timeboxIsDue else { return false }
        timeboxIsDue = false
        await handle(.timeout(.timebox))
        return true
    }

    /// M0 の文字起こしが違うときの再録音（retention R7）。1 回だけ。
    func retakeAvoidance() async {
        guard canRetakeAvoidance, stateAtAvoidance != nil else { return }
        canRetakeAvoidance = false
        hasRetakenAvoidance = true
        cutIn()
        await deliver(.retakeAvoidance)
    }

    private func restartAvoidance() async {
        guard let base = stateAtAvoidance else { return }
        if await endIfTimeboxIsDue() { return }
        if let avoidanceEntryID {
            try? await store.deleteVoiceEntry(id: avoidanceEntryID)
            self.avoidanceEntryID = nil
        }
        avoidanceTranscript = ""
        var restart = base
        restart.step = .morningAvoidance
        restart.avoidance = ""
        // 再開の入口（`FlowEntry.resume`）でそのステップから入り直す。
        await apply(FlowMachine.start(
            FlowEntry(sessionType: restart.sessionType, mode: restart.mode, resume: restart)
        ))
    }

    /// 「話せない時」モードへ切り替える。進行中の読み上げは即座に止める（実装計画 §8）。
    func switchToTextMode() async {
        synthesizer.stop()
        await deliver(.switchToText)
    }

    private func enterTextMode() async {
        stopListening()
        if await endIfTimeboxIsDue() { return }
        isVoiceless = true
        guard var current = state else { return }
        current.mode = .text
        current.isVoicelessDay = true
        state = current
        if let pendingListen {
            var request = pendingListen
            request.input = .text
            await beginListening(request)
        }
    }

    // MARK: - 状態機械の駆動

    private func handle(_ event: FlowEvent) async {
        guard let current = state else { return }
        let transition = FlowMachine.handle(event, in: current)
        logger.info("event \(Self.describe(event), privacy: .public) step \(String(describing: current.step), privacy: .public) -> \(String(describing: transition.state.step), privacy: .public) retry=\(transition.state.retryCount, privacy: .public)")
        if timeboxIsDue, !transition.state.isFinished {
            // 待たせていた時間切れ。答えは受け取って保存し、次の発話も聞き取りも始めずに終える。
            timeboxIsDue = false
            await apply(FlowTransition(
                state: transition.state,
                commands: transition.commands.filter { !Self.needsTheFloor($0) }
            ))
            await handle(.timeout(.timebox))
            return
        }
        await apply(transition)
        if transition.commands.isEmpty {
            await resumeWaiting()
        }
    }

    /// `FlowMachine` が受け流した入力（前の質問のチップなど）のために止めた聞き取りを戻す。
    private func resumeWaiting() async {
        guard completion == nil, !isListening, let waiting else { return }
        await execute([waiting])
    }

    /// ログ用。本人の言葉（transcript）は中身を出さず長さだけにする。
    private static func describe(_ event: FlowEvent) -> String {
        switch event {
        case .transcript(let text): "transcript(\(text.count)chars)"
        default: String(describing: event)
        }
    }

    private static func describe(_ command: FlowCommand) -> String {
        switch command {
        case .speak(let line): "speak(\(line.count))"
        case .listen(let request): "listen(\(request.input),\(request.silenceSeconds)s)"
        case .showChoices(let list): "choices(\(list.count))"
        case .record: "record"
        case .play: "play"
        case .save(let instruction): "save(\(instruction.kind))"
        case .scheduleNotification(let request): "schedule(\(request.kind))"
        case .cancelNotification(let kind): "cancel(\(kind))"
        case .finish(let completion): "finish(\(completion))"
        }
    }

    private func apply(_ transition: FlowTransition) async {
        state = transition.state
        // 文言を 1 つ使うたびに履歴を残す。セッションをまたいで重複を避けるため（統合判断 D2）。
        copyHistoryStore.save(transition.state.picker.history)
        if transition.state.step == .morningAvoidance, stateAtAvoidance == nil {
            stateAtAvoidance = transition.state
        }
        if shouldAskListenMode(for: transition) {
            // 発話も再生もまだ始めない。本人が返し方を選んでから続きを流す（retention R8）。
            pendingPlaybackCommands = transition.commands
            listenModePrompt = true
            phase = .playback
            return
        }
        logger.info("commands \(transition.commands.map(Self.describe).joined(separator: ","), privacy: .public)")
        await execute(transition.commands)
    }

    /// 命令を順に実行する。会話が終わっていたら残りは実行しない。割り込まれていたら、
    /// 残りの発話・聞き取り・再生は実行せず、保存・通知・終了だけを実行する。
    private func execute(_ commands: [FlowCommand]) async {
        for command in commands {
            guard completion == nil else { return }
            if isInterrupted, Self.needsTheFloor(command) {
                if Self.awaitsAnAnswer(command) {
                    waiting = command
                }
                logger.info("command dropped \(Self.describe(command), privacy: .public)")
                continue
            }
            await run(command)
        }
    }

    /// 本人に向けて鳴らす・聞く・選ばせる命令か。
    private static func needsTheFloor(_ command: FlowCommand) -> Bool {
        switch command {
        case .speak, .listen, .showChoices, .record, .play: true
        case .save, .scheduleNotification, .cancelNotification, .finish: false
        }
    }

    private static func awaitsAnAnswer(_ command: FlowCommand) -> Bool {
        switch command {
        case .listen, .record: true
        default: false
        }
    }

    /// 宣言音声を鳴らす前に「イヤホンで聞く / 文字で読む」を出すか（retention R8）。
    ///
    /// 「声なし」の日は音を鳴らさないので確認しない（`.declarationText` はここに入らない）。
    private func shouldAskListenMode(for transition: FlowTransition) -> Bool {
        guard !listenModePrompt,
              let audioSession,
              audioSession.requiresAudiblePlaybackConfirmation
        else { return false }
        return transition.commands.contains { command in
            guard case .play(let request) = command else { return false }
            return request.target == .declarationAudio
        }
    }

    /// 「イヤホンで聞く / 文字で読む / 耳に当てて聞く」の答えを受けて、止めてあった続きを流す。
    func chooseListenMode(_ mode: ListenMode) async {
        await deliver(.listenMode(mode))
    }

    private func continuePlayback(in mode: ListenMode) async {
        guard listenModePrompt else { return }
        listenModePrompt = false
        listenMode = mode
        let commands = pendingPlaybackCommands
        pendingPlaybackCommands = []
        await execute(commands.filter { command in
            // 「文字で読む」を選んだ日は TTS も鳴らさない。本人の言葉は画面に出す。
            if mode == .readText, case .speak = command { return false }
            return true
        })
    }

    /// 朝の宣言をもう一度返す（PlaybackCard の「聞く」「耳に当てて聞く」）。会話は進めない。
    func replayDeclaration(preferReceiver: Bool = false) async {
        guard commitment?.declarationAudioPath != nil else { return }
        listenMode = preferReceiver ? .receiver : .speaker
        await playDeclarationAudio(preferReceiver: preferReceiver)
    }

    private func run(_ command: FlowCommand) async {
        switch command {
        case .speak(let line):
            await speak(line)

        case .listen(let request):
            await beginListening(request)

        case .showChoices(let list):
            choices = list
            phase = .choosing

        case .record(let request):
            await beginDeclarationRecording(request)

        case .play(let request):
            await playDeclaration(request)

        case .save(let instruction):
            await save(instruction)

        case .scheduleNotification(let request):
            await schedule(request)

        case .cancelNotification(let kind):
            try? await notifications.cancel(kind, on: now())

        case .finish(let completion):
            await finish(completion)
        }
    }

    // MARK: - 発話（半二重）

    private func speak(_ line: String) async {
        phase = .speaking
        spokenLine = line
        // TTS 発話中は STT へ流さない（実装計画 §7.3 の半二重）。
        // 「耳に当てて聞く」を選んだ日は読み上げも受話口から出す（retention R8）。
        let startedAt = ContinuousClock.now
        await synthesizer.speak(line, preferReceiver: listenMode == .receiver)
        let elapsed = ContinuousClock.now - startedAt
        logger.info("speak done chars=\(line.count, privacy: .public) elapsed=\(elapsed, privacy: .public)")
    }

    // MARK: - 聞く

    /// その聞き取りがまだ有効か。世代が進んでいるか会話が終わっていれば、もう古い。
    private func isCurrent(_ generation: Int) -> Bool {
        generation == listenGeneration && completion == nil
    }

    private func beginListening(_ request: ListenRequest) async {
        listenGeneration += 1
        let generation = listenGeneration
        pendingListen = request
        waiting = .listen(request)
        logger.info("listen begin step=\(String(describing: request.step), privacy: .public) input=\(String(describing: request.input), privacy: .public) silence=\(request.silenceSeconds, privacy: .public)s")
        examples = request.examples
        partialTranscript = ""
        lastRecording = nil
        detector = SilenceDetector(duration: .standard)

        guard request.input == .voice else {
            // 短文入力を待つ。沈黙の見張りは張らない（書いている途中で催促も質問の送りもしない）。
            phase = .listening
            return
        }

        if notice == .captureFailed {
            // 前の質問で声を始められなかった掲示。この質問では声をもう一度試みる。
            notice = nil
        }

        do {
            let format = try await prepareTranscriber()
            guard isCurrent(generation) else {
                // 準備を待つあいだに止められた。録音は始めない。
                logger.info("listen dropped stage=prepare")
                return
            }
            guard let started = try await startCapture(format: format, limit: .utterance, generation: generation) else { return }
            phase = .listening
            observe(started.session, relativePath: started.relativePath, generation: generation)
            startSilenceWatch(seconds: request.silenceSeconds, generation: generation)
        } catch {
            guard isCurrent(generation) else { return }
            // マイクの権限はある（拒否なら `open` の時点で文字の経路に入っている）。
            // 録音が始められなくても会話は止めない。この質問だけ文字で受け、その日を声なしにはしない。
            logger.error("listen start failed: \(error.localizedDescription, privacy: .public) -> text for this question")
            notice = .captureFailed
            var fallback = request
            fallback.input = .text
            pendingListen = fallback
            waiting = .listen(fallback)
            phase = .listening
        }
    }

    private struct StartedCapture {
        var session: VoiceCaptureSession
        var relativePath: String
    }

    /// 録音と認識を始める。失敗したら後始末をして 1 回だけやり直す。
    /// 待っているあいだに世代が進んだ（止められた）ときは、始めずに nil を返す。
    private func startCapture(
        format: AVAudioFormat,
        limit: VoiceCaptureLimit,
        generation: Int
    ) async throws -> StartedCapture? {
        do {
            return try await startCaptureOnce(format: format, limit: limit, generation: generation)
        } catch {
            guard isCurrent(generation) else { return nil }
            logger.error("listen start failed: \(error.localizedDescription, privacy: .public) -> retry")
        }
        return try await startCaptureOnce(format: format, limit: limit, generation: generation)
    }

    private func startCaptureOnce(
        format: AVAudioFormat,
        limit: VoiceCaptureLimit,
        generation: Int
    ) async throws -> StartedCapture? {
        do {
            let allocation = try audioFiles.allocate(recordedAt: now())
            capture.limit = limit
            let session = try capture.start(writingTo: allocation.url, analyzerFormat: format)
            try await transcriber.start(inputSequence: session.analyzerInput)
            guard isCurrent(generation) else {
                // 認識の開始を待つあいだに止められた。止めた側は開始前の認識器しか片づけていない。
                logger.info("listen dropped stage=start")
                discardCapture()
                return nil
            }
            return StartedCapture(session: session, relativePath: allocation.relativePath)
        } catch {
            // 始まっていた録音を残さない（残すと、やり直しが二重開始で失敗する）。
            discardCapture()
            throw error
        }
    }

    private func discardCapture() {
        if capture.isCapturing {
            capture.stop()
        }
        transcriber.cancel()
    }

    /// ja-JP モデルの用意。取得中は掲示を出してから待つ。
    private func prepareTranscriber() async throws -> AVAudioFormat {
        if case .downloading = transcriber.assetState {
            notice = .assetDownloading
            phase = .error(.assetDownloading)
        }
        let format = try await transcriber.prepare()
        if notice == .assetDownloading {
            notice = nil
        }
        return format
    }

    /// 録音の見張り。`VoiceCapture` が `@MainActor` に届けた値だけを見る。タップのクロージャには触らない。
    ///
    /// 聞き取りの終わりを見つけたら進行に渡して終わる。確定も次の発話もここでは実行しない
    /// （このタスクは聞き取りを止めるときに止められるので、進行を載せると読み上げを待てなくなる）。
    private func observe(_ session: VoiceCaptureSession, relativePath: String, generation: Int) {
        hearingGeneration = generation
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            var peakRMS: Float = 0
            var levelCount = 0
            for await event in session.events {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case .level(let rms, let duration):
                    elapsed += duration
                    peakRMS = max(peakRMS, rms)
                    levelCount += 1
                    self.waveform.append(rms: rms)
                    self.partialTranscript = self.transcriber.volatileText
                    guard self.detector.feed(rms: rms, duration: duration) else { continue }
                    self.logger.info("listen end reason=silence elapsed=\(elapsed, privacy: .public) peakRMS=\(peakRMS, privacy: .public) levels=\(levelCount, privacy: .public) partial=\(self.partialTranscript.count, privacy: .public)chars")
                case .reachedLimit:
                    self.logger.info("listen end reason=limit elapsed=\(elapsed, privacy: .public) peakRMS=\(peakRMS, privacy: .public) heard=\(self.detector.hasHeardSpeech, privacy: .public)")
                case .failed(let fault):
                    self.logger.error("listen end reason=failed \(String(describing: fault), privacy: .public) elapsed=\(elapsed, privacy: .public)")
                }
                self.post(.captureEnded(generation: generation, relativePath: relativePath, duration: elapsed))
                return
            }
        }
    }

    private func finishListening(generation: Int, relativePath: String, duration: TimeInterval) async {
        // 見張りが終わりを見つけた後で止められた聞き取り。止めた側が片づけている。
        guard isCurrent(generation) else { return }
        cancelSilenceWatch()
        captureTask = nil
        capture.stop()
        phase = .thinking
        let startedAt = ContinuousClock.now
        let text = await transcriber.finish()
        guard isCurrent(generation) else {
            // 確定を待つあいだに止められた。結果は流さず、確定済みの文字列も残さない。
            logger.info("listen dropped stage=finalize chars=\(text.count, privacy: .public)")
            transcriber.cancel()
            return
        }
        logger.info("transcript ready chars=\(text.count, privacy: .public) finalize=\(ContinuousClock.now - startedAt, privacy: .public) recorded=\(duration, privacy: .public)s")
        transcriber.reset()
        listenGeneration += 1
        waiting = nil
        lastRecording = (relativePath, duration)
        await handle(.transcript(text))
    }

    /// 聞き取りを止めて世代を進める。準備・開始・確定を待っている途中の聞き取りは、
    /// 戻ってきたときに世代を見て自分で後始末する。
    private func stopListening() {
        listenGeneration += 1
        cancelSilenceWatch()
        captureTask?.cancel()
        captureTask = nil
        if capture.isCapturing {
            capture.stop()
        }
        transcriber.cancel()
    }

    /// 声の聞き取りの沈黙を計る。5 秒で催促を 1 回、さらに 10 秒で次の扱いへ（実装計画 §7.2 / §16.7）。
    /// 実際の分岐は `FlowMachine` が持つ。ここは時間を計って進行に渡すだけ。文字の入力待ちでは使わない。
    private func startSilenceWatch(seconds: Int, generation: Int) {
        silenceTask?.cancel()
        let sleep = timer.sleep
        silenceTask = Task { [weak self] in
            do {
                try await sleep(.seconds(seconds))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            // 話し始めていれば無音判定（`SilenceDetector`）に任せる。
            guard !self.detector.hasHeardSpeech else { return }
            self.post(.silence(generation: generation))
        }
    }

    private func cancelSilenceWatch() {
        silenceTask?.cancel()
        silenceTask = nil
    }

    // MARK: - タイムボックス

    private func startTimebox(for sessionType: SessionType) {
        timeboxTask?.cancel()
        let sleep = timer.sleep
        let limit = Self.timebox(for: sessionType)
        timeboxTask = Task { [weak self] in
            do {
                try await sleep(limit)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            // 読み上げ中でも待たせない。音をその場で止めてから、進行に渡す。
            // 声を聞いている途中だけは、その答えが確定するまで待つ。
            guard self.expireTimebox() else { return }
            self.post(.event(.timeout(.timebox)))
        }
    }

    // MARK: - 宣言の録音（M4）

    private func beginDeclarationRecording(_ request: RecordRequest) async {
        listenGeneration += 1
        let generation = listenGeneration
        waiting = .record(request)
        // 前の質問の録音を、宣言の音声として持ち越さない。
        lastRecording = nil
        if notice == .captureFailed {
            notice = nil
        }
        do {
            let format = try await prepareTranscriber()
            guard isCurrent(generation) else {
                logger.info("record dropped stage=prepare")
                return
            }
            guard let started = try await startCapture(format: format, limit: .declaration, generation: generation) else {
                return
            }
            detector = SilenceDetector(duration: .long)
            phase = .recordingDeclaration
            observe(started.session, relativePath: started.relativePath, generation: generation)
        } catch {
            guard isCurrent(generation) else { return }
            // 聞き取りの開始と同じ扱い。マイクの権限はあるので、拒否の掲示は出さず、その日を声なしにも
            // 宣言の後回しにもしない。宣言だけ文字で受ける。
            logger.error("record start failed: \(error.localizedDescription, privacy: .public) -> text for the declaration")
            notice = .captureFailed
            let fallback = ListenRequest(
                step: request.step,
                silenceSeconds: FlowMachine.firstSilenceSeconds,
                input: .text
            )
            pendingListen = fallback
            waiting = .listen(fallback)
            phase = .listening
        }
    }

    // MARK: - 宣言の再生（N0）

    private func playDeclaration(_ request: PlaybackRequest) async {
        phase = .playback
        switch request.target {
        case .declarationText:
            // 本人の言葉を TTS で読み上げ直さない。画面に出す（fix-decisions P2.3）。
            declarationTextToShow = commitment?.declarationTranscript
        case .declarationAudio where listenMode == .readText:
            // 「文字で読む」を選んだ日も、鳴らさずに本人の言葉を画面に出す（retention R8）。
            declarationTextToShow = commitment?.declarationTranscript
        case .declarationAudio:
            declarationTextToShow = nil
            await playDeclarationAudio(preferReceiver: listenMode == .receiver)
        }
        // 再生の途中で割り込まれたら、聞き終えた扱いにはしない。
        guard !isInterrupted else { return }
        await handle(.playbackFinished)
    }

    /// 宣言音声を鳴らす。出力経路は鳴らす直前に決める（実装計画 §7.3）。
    private func playDeclarationAudio(preferReceiver: Bool) async {
        guard let path = commitment?.declarationAudioPath else { return }
        audioSession?.applyOutputRoute(preferReceiver: preferReceiver)
        declarationPlaybackStartedAt = now()
        try? await player.play(audioFiles.url(forRelativePath: path), preferReceiver: preferReceiver)
        declarationPlaybackStartedAt = nil
    }

    // MARK: - 保存

    private func save(_ instruction: SaveInstruction) async {
        let audioPath = instruction.hasAudio ? lastRecording?.relativePath : nil
        let duration = instruction.hasAudio ? (lastRecording?.duration ?? 0) : 0

        // 宣言は `Commitment` と同時に書く（音声ファイルを二重に持たせない。実装計画 §10）。
        if instruction.kind == .declaration {
            pendingDeclaration = (instruction.text, audioPath, duration)
            lastRecording = nil
            return
        }

        guard let sessionType = state?.sessionType else { return }
        let kind = VoiceEntryKind(rawValue: instruction.kind.rawValue) ?? .avoidance
        let draft = VoiceEntryDraft(
            recordedAt: now(),
            sessionType: sessionType,
            kind: kind,
            audioPath: audioPath,
            transcript: instruction.text,
            durationSec: duration,
            commitmentID: commitment?.id
        )
        let saved = try? await store.appendVoiceEntry(draft)
        lastRecording = nil

        switch instruction.kind {
        case .avoidance:
            // 文字起こしは従。1 行だけ出して、違えば 1 回だけ録り直せる（retention R7）。
            avoidanceTranscript = instruction.text
            avoidanceEntryID = saved?.id
            canRetakeAvoidance = audioPath != nil && !hasRetakenAvoidance
            phase = .thinking
            classifiedDomain = (try? await engine.classifyDomain(avoidance: instruction.text)) ?? .other

        case .reason:
            // 声で答えた日は分類を試みる。失敗しても会話は止めない（実装計画 §7.2）。
            if instruction.hasAudio, let avoidance = state?.avoidance {
                phase = .thinking
                classifiedReason = try? await engine
                    .classifyReason(avoidance: avoidance, answer: instruction.text)
                    .category
            } else {
                classifiedReason = state?.reason
            }

        case .status:
            if let id = commitment?.id, let outcome = state?.outcome {
                commitment = try? await store.updateOutcome(
                    commitmentID: id,
                    outcome: outcome,
                    progressNote: nil,
                    at: now()
                )
            }

        case .progress:
            if let id = commitment?.id {
                commitment = try? await store.updateOutcome(
                    commitmentID: id,
                    outcome: state?.outcome ?? .pending,
                    progressNote: instruction.text,
                    at: now()
                )
            }

        case .blocker, .tomorrow, .declaration:
            break
        }
    }

    // MARK: - 通知

    private func schedule(_ request: NotificationRequest) async {
        // 行動時刻の通知は `commitmentID` を載せたいので、宣言が保存されるまで待つ。
        if commitment == nil, state?.sessionType == .morning || state?.step.sessionType == .morning {
            pendingNotifications.append(request)
            return
        }
        await send(request)
    }

    private func send(_ request: NotificationRequest) async {
        let fireDate = request.timePhrase.flatMap {
            JapaneseTimeParser().parse($0, now: now(), calendar: calendar).date
        }
        try? await notifications.schedule(
            request,
            fireDate: fireDate,
            commitmentID: commitment?.id,
            on: now()
        )
    }

    // MARK: - 終わり

    /// 昼 N3 の「今日は捨てる / 明日に回す」、夜 E0 の「明日に回す」、N1 の「やった」を
    /// 逃げている対象の状態に写す（task_011 scope）。「もっと小さくする」は対象を open のまま残す。
    private func avoidanceStatusToPersist(for completion: FlowCompletion) -> AvoidanceStatus? {
        guard completion == .completed, let current = state else { return nil }
        if lastChoiceID == .dropToday { return .dropped }
        if lastChoiceID == .moveToTomorrow || current.nightDecision == .moveToTomorrow { return .carriedOver }
        if current.sessionType != .morning, commitment?.outcome == .done { return .done }
        return nil
    }

    private func persistAvoidanceStatusIfNeeded(_ completion: FlowCompletion) async {
        guard let status = avoidanceStatusToPersist(for: completion) else { return }
        var target = commitment
        if target == nil {
            target = (try? await store.todayCommitment(on: now())) ?? nil
        }
        guard let id = target?.id else { return }
        try? await store.updateAvoidanceStatus(commitmentID: id, status: status, at: now())
    }

    private func finish(_ completion: FlowCompletion) async {
        stopListening()
        // 会話が終わったら何も鳴らさない。読み上げと再生が残っていれば止める。
        synthesizer.stop()
        player.stop()
        timeboxTask?.cancel()
        timeboxTask = nil
        choices = []
        examples = []
        pendingListen = nil
        waiting = nil
        audioSession?.deactivate()

        if completion == .suspended {
            suspendedState = state
        }

        // 約束を作るのは成立した会話だけ。成立しなかった会話（`abandoned`）や途中で終えた会話では作らない。
        if completion == .completed {
            await persistCommitmentIfNeeded()
        }
        await persistShrinkIfNeeded()
        await persistCarryoverIfNeeded()
        await persistAvoidanceStatusIfNeeded(completion)

        for request in pendingNotifications {
            await send(request)
        }
        pendingNotifications.removeAll()

        self.completion = completion
        phase = .done

        if let sessionLogID, let startedAt {
            try? await store.finishSessionLog(
                id: sessionLogID,
                endedAt: max(now(), startedAt),
                completed: completion == .completed,
                lastStep: state?.step,
                guardrailReplacedCount: guardrailReplacedCount
            )
        }
    }

    /// M4 まで来た朝（短縮版を含む）だけが `Commitment` を作る。
    private func persistCommitmentIfNeeded() async {
        guard let current = state,
              let declaration = pendingDeclaration,
              commitment == nil,
              let action = current.microAction
        else { return }

        let parsed = current.plannedAnswer.map {
            JapaneseTimeParser().parse($0, now: now(), calendar: calendar)
        }
        plannedPlace = parsed?.place ?? ""
        let voiceless = current.isVoicelessDay || current.isDeclarationDeferred || declaration.audioPath == nil
        isVoiceless = voiceless

        let draft = CommitmentDraft(
            avoidanceTitle: current.avoidance,
            domain: classifiedDomain,
            reason: current.reason ?? classifiedReason,
            microAction: action,
            plannedAt: parsed?.date,
            // 本人が言った場所を捨てない（統合判断 D1 / retention R11）。
            plannedPlace: plannedPlace.isEmpty ? nil : plannedPlace,
            declarationAudioPath: declaration.audioPath,
            declarationTranscript: declaration.text,
            declarationDurationSec: declaration.duration,
            isVoiceless: voiceless,
            sessionType: current.sessionType,
            createdAt: now()
        )
        commitment = try? await store.createCommitment(draft)
        pendingDeclaration = nil

        // 声で宣言していない日は `createCommitment` が宣言の `VoiceEntry` を作らないので、
        // ここで文字だけの 1 件を足す。入力方式に依らず当日 3 件そろえる（task_008 done_definition）。
        if declaration.audioPath == nil, let id = commitment?.id {
            _ = try? await store.appendVoiceEntry(
                VoiceEntryDraft(
                    recordedAt: now(),
                    sessionType: current.sessionType,
                    kind: .declaration,
                    audioPath: nil,
                    transcript: declaration.text,
                    durationSec: 0,
                    commitmentID: id
                )
            )
        }
    }

    /// 昼 N3 で本人が言い直した行動を `Commitment` に書く（`shrinkCount` が 1 増える）。
    private func persistShrinkIfNeeded() async {
        guard let current = state,
              current.step == .noonShrink,
              let action = current.microAction,
              let id = commitment?.id,
              action.text != commitment?.microAction.text
        else { return }
        commitment = try? await store.shrink(
            commitmentID: id,
            to: action.text,
            estimatedMinutes: action.estimatedMinutes,
            at: now()
        )
    }

    /// 夜 E1 の答えを翌朝の M0 に渡す（実装計画 §7.2）。
    private func persistCarryoverIfNeeded() async {
        guard let current = state,
              current.sessionType == .night || current.step.sessionType == .night,
              let text = current.tomorrow,
              !text.isEmpty,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: now())
        else { return }
        _ = try? await store.saveCarryover(forDay: tomorrow, text: text, sourceEntryID: nil, at: now())
    }
}
