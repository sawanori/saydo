import AVFoundation
import Foundation
import Observation
import OSLog
import SaydoCore

// MARK: - 画面の状態

/// 約束する画面の段階（実装計画 §17.3）。
enum PromiseStage: Sendable, Equatable {
    /// 「今日の約束は？」
    case promise
    /// 「そのために、最初にやることは？」
    case action
    /// 聞き取った 2 行と「約束する」。
    case confirm
    /// 保存した後の、完了の 1 行。
    case done
}

/// 2 つの質問。
enum PromiseQuestion: Sendable, Equatable, Hashable, CaseIterable {
    case promise
    case action

    var text: String {
        switch self {
        case .promise: PromiseCopy.promiseQuestion
        case .action: PromiseCopy.firstActionQuestion
        }
    }

    var stage: PromiseStage {
        switch self {
        case .promise: .promise
        case .action: .action
        }
    }
}

/// 質問 1 つぶんの答え。声で答えたときだけ録音のパスを持つ。
struct PromiseAnswer: Sendable, Equatable {
    var text: String
    /// 録音の相対パス（`AudioFileStore`）。文字で答えたときは nil。
    var audioPath: String?
    var durationSec: Double
    var recordedAt: Date
}

/// 画面に出す 1 行の案内。責める言い方にしない（企画原則 §22-1）。
enum PromiseNotice: Sendable, Equatable {
    /// 押していた時間が短かった。
    case holdLonger
    /// 言葉を聞き取れなかった。
    case notHeard
    /// 録音を始められなかった。その質問は文字で受ける。
    case captureUnavailable
    /// 約束を保存できなかった。
    case saveUnavailable

    var text: String {
        switch self {
        case .holdLonger: PromiseCopy.holdLonger
        case .notHeard: PromiseCopy.notHeard
        case .captureUnavailable: PromiseCopy.captureUnavailable
        case .saveUnavailable: PromiseCopy.saveUnavailable
        }
    }
}

// MARK: - ViewModel

/// 約束する画面の頭脳（実装計画 §17.4）。`FlowMachine` は通さず、2 つの録音と 1 回のタップを直接持つ。
///
/// - 録音は、ボタンを押している間だけ動く。離した瞬間に止める。無音の判定は使わない。
/// - 質問は読み上げない（読み上げの部品を持たない）。
/// - 文言は持たない。画面に出す言葉はすべて `PromiseCopy` から来る。
/// - 録音の開始と確定は 1 本の列で順に処理し、世代番号で古い録音の結果を捨てる。
@MainActor
@Observable
final class PromiseViewModel {

    // MARK: 定数

    /// これより短い押下は無視する（実装計画 §17.3）。
    static let minimumHold: TimeInterval = 0.5
    /// 1 回の録音の上限。30 秒で自動的に止める。
    static let captureLimit: VoiceCaptureLimit = .declaration

    // MARK: 公開する状態

    private(set) var stage: PromiseStage = .promise
    /// 質問ごとの答え。
    private(set) var answers: [PromiseQuestion: PromiseAnswer] = [:]
    /// ボタンを押しているか。
    private(set) var isHolding = false
    /// 録音が動いているか。
    private(set) var isRecording = false
    /// 離した後、文字起こしの確定を待っているか。
    private(set) var isFinalizing = false
    /// 押している間に録れた長さ（秒）。
    private(set) var elapsed: TimeInterval = 0
    /// 波形の描画に使うレベル履歴。
    let waveform = WaveformSampler()
    /// いまの質問を文字で受けているか。
    private(set) var isTextInput = false
    /// マイクが使えるか。使えなければ最初から文字の入力になり、声には戻せない。
    private(set) var microphoneGranted = true
    private(set) var notice: PromiseNotice?
    /// 「今日はやめる」（その日の朝の回を止める）を出すか。約束の無い朝だけ。
    private(set) var showsStopToday = false
    /// 「今日はやめる」を押して、朝の回を止め終えたか。
    private(set) var didStopToday = false
    /// 「約束する」を押して、保存とアラームの登録を待っているか。
    private(set) var isSaving = false
    /// 保存した約束。
    private(set) var commitment: CommitmentSnapshot?
    /// アラームの登録の結果。
    private(set) var alarmOutcome: AlarmScheduleOutcome?
    /// 完了の 1 行。
    private(set) var completionLine: String?

    /// いま答えを待っている質問。確かめる段階と完了の後は nil。
    var currentQuestion: PromiseQuestion? {
        switch stage {
        case .promise: .promise
        case .action: .action
        case .confirm, .done: nil
        }
    }

    /// 「押して話す」を出すか。
    var showsTalkButton: Bool { currentQuestion != nil && !isTextInput && microphoneGranted }
    /// 文字の入力欄を出すか。
    var showsTextField: Bool { currentQuestion != nil && isTextInput }
    /// 声に戻すボタンを出せるか。
    var canUseVoice: Bool { microphoneGranted && isTextInput && currentQuestion != nil }
    /// 押している間の経過秒数。
    var elapsedSeconds: Int { Int(elapsed) }
    /// 「約束する」を押せるか。
    var canCommit: Bool {
        stage == .confirm && !isSaving && answers[.promise] != nil && answers[.action] != nil
    }

    // MARK: 依存

    private let store: any PromiseStore
    private let capture: any VoiceCapturing
    private let transcriber: any Transcribing
    private let chase: ChaseCoordinator
    private let joiner: any VoiceJoining
    private let audioFiles: AudioFileStore
    private let audioSession: (any AudioSessionControlling)?
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let logger = Logger(subsystem: "com.nonturn.saydo", category: "promise")

    // MARK: 内部状態

    /// 動いている（または確定を待っている）録音 1 回ぶん。
    private struct Take {
        var generation: Int
        var question: PromiseQuestion
        var relativePath: String
        var startedAt: Date
    }

    private var take: Take?
    /// 録音の世代。押すたび・止めるたび・捨てるたびに進める。`await` から戻ったときに
    /// これが変わっていたら、その録音はもう古い。
    private var takeGeneration = 0
    private var isClosed = false
    private var levelTask: Task<Void, Never>?
    /// 録音の開始と確定を順に処理する列の末尾。
    private var pendingWork: Task<Void, Never>?
    private var enqueuedCount = 0

    init(
        store: any PromiseStore,
        capture: any VoiceCapturing,
        transcriber: any Transcribing,
        chase: ChaseCoordinator,
        audioFiles: AudioFileStore,
        audioSession: (any AudioSessionControlling)? = nil,
        joiner: any VoiceJoining = VoiceJoiner(),
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.capture = capture
        self.transcriber = transcriber
        self.chase = chase
        self.audioFiles = audioFiles
        self.audioSession = audioSession
        self.joiner = joiner
        self.calendar = calendar
        self.now = now
    }

    // MARK: - 開く・閉じる

    /// 画面を開いたときに 1 回呼ぶ。マイクが使えなければ最初から文字の入力にする。
    func open(microphoneGranted: Bool = true) {
        self.microphoneGranted = microphoneGranted
        isTextInput = !microphoneGranted
        showsStopToday = chase.rules.canStopMorningPrompt(asOf: now())
        if microphoneGranted {
            _ = try? audioSession?.activate(mode: .standard)
        }
    }

    /// 閉じる。録音を止め、保存していない録音ファイルを消す。
    ///
    /// 「約束する」を押した後（保存中・完了後）は、録音は約束のものなので消さない。
    func close() {
        guard !isClosed else { return }
        abandonTake()
        isClosed = true
        if !isSaving && stage != .done {
            for answer in answers.values {
                deleteAudio(answer.audioPath)
            }
            answers = [:]
        }
        audioSession?.deactivate()
    }

    // MARK: - 押して話す

    /// ボタンを押した。録音と文字起こしを始める。
    func pressBegan() {
        guard let question = currentQuestion, showsTalkButton,
              !isHolding, !isFinalizing, !isSaving, !isClosed else { return }
        isHolding = true
        notice = nil
        elapsed = 0
        waveform.reset()
        takeGeneration += 1
        let generation = takeGeneration
        enqueue { [weak self] in
            await self?.beginTake(question: question, generation: generation)
        }
    }

    /// ボタンを離した。録音をその場で止め、文字起こしを確定する。
    func pressEnded() {
        guard isHolding else { return }
        endHold(releasedAt: now())
    }

    private func endHold(releasedAt: Date) {
        isHolding = false
        // 離した瞬間に録音を止める。確定はこの後で待つ。
        stopCapture()
        isFinalizing = true
        let generation = takeGeneration
        enqueue { [weak self] in
            await self?.finishTake(generation: generation, releasedAt: releasedAt)
        }
    }

    /// その録音がまだ有効か。
    private func isCurrent(_ generation: Int) -> Bool {
        generation == takeGeneration && !isClosed
    }

    private func beginTake(question: PromiseQuestion, generation: Int) async {
        guard isCurrent(generation), isHolding else { return }
        var allocatedPath: String?
        do {
            let format = try await transcriber.prepare()
            // 準備を待つあいだに離された・止められた。録音は始めない。
            guard isCurrent(generation), isHolding else { return }
            let allocation = try audioFiles.allocate(recordedAt: now(), calendar: calendar)
            allocatedPath = allocation.relativePath
            capture.limit = Self.captureLimit
            let session = try capture.start(writingTo: allocation.url, analyzerFormat: format)
            take = Take(
                generation: generation,
                question: question,
                relativePath: allocation.relativePath,
                startedAt: now()
            )
            isRecording = true
            observe(session, generation: generation)
            try await transcriber.start(inputSequence: session.analyzerInput)
            if !isCurrent(generation) {
                // 認識の開始を待つあいだに止められた。止めた側は開始前の認識器しか片づけていない。
                transcriber.cancel()
            }
        } catch {
            logger.error("take start failed: \(error.localizedDescription, privacy: .public)")
            guard isCurrent(generation) else {
                // 止めた側が録音とファイルを片づけている。始まり切らなかった認識だけ片づける。
                transcriber.cancel()
                if take == nil { deleteAudio(allocatedPath) }
                return
            }
            deleteAudio(allocatedPath)
            failTake()
        }
    }

    /// 録音の見張り。`VoiceCapture` が `@MainActor` に届けた値だけを見る。
    private func observe(_ session: VoiceCaptureSession, generation: Int) {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            for await event in session.events {
                guard let self, !Task.isCancelled,
                      self.isRecording, self.take?.generation == generation else { return }
                switch event {
                case .level(let rms, let duration):
                    self.waveform.append(rms: rms)
                    self.elapsed += duration
                case .reachedLimit:
                    // 上限の 30 秒。離したのと同じ扱いにする。
                    self.logger.info("take reached limit")
                    if self.isHolding {
                        self.endHold(releasedAt: self.now())
                    }
                    return
                case .failed(let fault):
                    self.logger.error("take failed: \(String(describing: fault), privacy: .public)")
                    self.failTake()
                    return
                }
            }
        }
    }

    private func finishTake(generation: Int, releasedAt: Date) async {
        defer { isFinalizing = false }
        // 離した後で止められた・始められなかった録音。片づけは止めた側が済ませている。
        guard isCurrent(generation) else { return }
        guard let take, take.generation == generation else {
            // 録音が始まる前に離した。
            takeGeneration += 1
            notice = .holdLonger
            return
        }
        let held = releasedAt.timeIntervalSince(take.startedAt)
        guard held >= Self.minimumHold else {
            discardTake()
            notice = .holdLonger
            return
        }
        let text = await transcriber.finish()
        guard isCurrent(generation) else {
            // 確定を待つあいだに止められた。結果は使わず、確定済みの文字列も残さない。
            transcriber.cancel()
            return
        }
        transcriber.reset()
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            discardTake()
            notice = .notHeard
            return
        }
        self.take = nil
        takeGeneration += 1
        try? audioFiles.applyProtection(toRelativePath: take.relativePath)
        logger.info("take accepted chars=\(heard.count, privacy: .public) held=\(held, privacy: .public)s")
        accept(
            PromiseAnswer(text: heard, audioPath: take.relativePath, durationSec: held, recordedAt: take.startedAt),
            for: take.question
        )
    }

    private func stopCapture() {
        levelTask?.cancel()
        levelTask = nil
        if capture.isCapturing {
            capture.stop()
        }
        isRecording = false
    }

    /// いまの録音を止めて捨て、世代を進める。開始や確定を待っている途中の処理は、
    /// 戻ってきたときに世代を見て自分で終わる。
    private func abandonTake() {
        takeGeneration += 1
        isHolding = false
        stopCapture()
        transcriber.cancel()
        if let take {
            deleteAudio(take.relativePath)
            self.take = nil
        }
        elapsed = 0
    }

    /// 段階を進めずに、いまの録音を捨てる。
    private func discardTake() {
        abandonTake()
    }

    /// 録音を続けられなかった。その質問は文字で受ける。
    private func failTake() {
        abandonTake()
        notice = .captureUnavailable
        isTextInput = true
    }

    // MARK: - 答えの扱い

    private func accept(_ answer: PromiseAnswer, for question: PromiseQuestion) {
        deleteAudio(answers[question]?.audioPath)
        answers[question] = answer
        notice = nil
        advance()
    }

    /// まだ答えていない質問へ進む。2 つとも答えていれば、聞き取った 2 行と「約束する」へ。
    private func advance() {
        if let next = PromiseQuestion.allCases.first(where: { answers[$0] == nil }) {
            stage = next.stage
            return
        }
        stage = .confirm
    }

    /// 「言い直す」。その質問の答えと録音を消して、もう一度聞く。
    func redo(_ question: PromiseQuestion) {
        guard stage != .done, !isSaving, !isClosed, let previous = answers[question] else { return }
        abandonTake()
        deleteAudio(previous.audioPath)
        answers[question] = nil
        notice = nil
        stage = question.stage
    }

    /// いまの質問を文字で受ける。
    func useTextInput() {
        guard currentQuestion != nil, !isTextInput else { return }
        abandonTake()
        notice = nil
        isTextInput = true
    }

    /// 声の入力に戻す。マイクが使えない端末では戻せない。
    func useVoiceInput() {
        guard canUseVoice else { return }
        notice = nil
        isTextInput = false
    }

    /// 文字で答える。空の答えは受けない。
    func submitText(_ text: String) {
        guard let question = currentQuestion, !isSaving, !isClosed else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }
        abandonTake()
        accept(PromiseAnswer(text: answer, audioPath: nil, durationSec: 0, recordedAt: now()), for: question)
    }

    // MARK: - 保存

    /// 「今日はやめる」。約束はせず、その日の朝の回（約束を促すアラーム）を止める。
    func stopToday() async {
        guard showsStopToday, !isSaving, !isClosed, stage != .done else { return }
        isSaving = true
        abandonTake()
        await chase.stopMorningPrompt()
        isSaving = false
        showsStopToday = false
        didStopToday = true
    }

    /// 「約束する」。アラームの権限を求め、約束を保存し、アラームの登録を頼む。
    func commit() async {
        guard canCommit, !isClosed,
              let promise = answers[.promise], let action = answers[.action] else { return }
        isSaving = true
        notice = nil

        // 権限は、このボタンを押した時点で求める。登録できたかどうかは登録の結果で見る。
        let authorized = await chase.alarms.requestAuthorization()

        let moment = now()
        // 追う回は、約束した時刻で決まる（約束より前の回は飛ばす。3 回とも過ぎていたら 30 分後に 1 回）。
        let rules = chase.rules
        let times = rules.times(on: moment)
        let rounds = AlarmPlan.rounds(
            promisedAt: moment,
            morning: times.morning,
            noon: times.noon,
            evening: times.evening
        )
        let voice = await joinedVoice(promise: promise, action: action, at: moment)

        var draft = CommitmentDraft(
            avoidanceTitle: promise.text,
            microAction: MicroAction(text: action.text)
        )
        // 最初に追う回の時刻。
        draft.plannedAt = rounds.first?.start
        draft.declarationAudioPath = voice?.relativePath
        draft.declarationTranscript = PromiseCopy.declarationTranscript(promise: promise.text, action: action.text)
        draft.declarationDurationSec = voice?.durationSec ?? 0
        draft.isVoiceless = voice == nil
        draft.createdAt = moment

        let saved: CommitmentSnapshot
        do {
            saved = try await store.createCommitment(draft)
        } catch {
            logger.error("promise save failed: \(error.localizedDescription, privacy: .public)")
            if let voice, voice.isJoinedFile {
                deleteAudio(voice.relativePath)
            }
            isSaving = false
            notice = .saveUnavailable
            return
        }
        commitment = saved

        // 約束とアクション、それぞれの言葉と録音を残す。ここで失敗しても約束は成立している。
        let entries: [(PromiseAnswer, VoiceEntryKind)] = [(promise, .avoidance), (action, .declaration)]
        for (answer, kind) in entries {
            let entry = VoiceEntryDraft(
                recordedAt: answer.recordedAt,
                sessionType: draft.sessionType,
                kind: kind,
                audioPath: answer.audioPath,
                transcript: answer.text,
                durationSec: answer.durationSec,
                commitmentID: saved.id
            )
            do {
                _ = try await store.appendVoiceEntry(entry)
            } catch {
                logger.error("promise entry save failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let outcome = await chase.promiseSaved(saved)
        logger.info("promise saved authorized=\(authorized, privacy: .public) alarm=\(String(describing: outcome), privacy: .public) voice=\(voice != nil, privacy: .public)")
        alarmOutcome = outcome
        completionLine = Self.completionLine(
            for: outcome,
            rounds: rounds.map(\.start),
            hasVoice: voice != nil,
            calendar: calendar
        )
        stage = .done
        isSaving = false
        audioSession?.deactivate()
    }

    /// 完了の 1 行。これから追う回の時刻を言う。追えないときは「追いかけます」と言わず、約束は残したことを伝える。
    static func completionLine(
        for outcome: AlarmScheduleOutcome,
        rounds: [Date],
        hasVoice: Bool,
        calendar: Calendar
    ) -> String {
        switch outcome {
        case .scheduled(let count) where count > 0 && !rounds.isEmpty:
            hasVoice
                ? PromiseCopy.completion(roundsAt: rounds, calendar: calendar)
                : PromiseCopy.completionWithoutVoice(roundsAt: rounds, calendar: calendar)
        case .notAuthorized:
            PromiseCopy.completionNotAuthorized
        case .scheduled, .failed:
            PromiseCopy.completionAlarmUnavailable
        }
    }

    private struct JoinedVoice {
        var relativePath: String
        var durationSec: Double
        /// つないで新しく作ったファイルか（片方だけ声のときは、その録音をそのまま使う）。
        var isJoinedFile: Bool
    }

    /// 約束、アクションの順に 1 つの音声ファイルにする。声が片方だけなら、ある方だけを使う。
    private func joinedVoice(promise: PromiseAnswer, action: PromiseAnswer, at moment: Date) async -> JoinedVoice? {
        let voiced = [promise, action].compactMap { answer in
            answer.audioPath.map { JoinedVoice(relativePath: $0, durationSec: answer.durationSec, isJoinedFile: false) }
        }
        guard let first = voiced.first else { return nil }
        guard voiced.count > 1 else { return first }

        var allocatedPath: String?
        do {
            let allocation = try audioFiles.allocate(recordedAt: moment, calendar: calendar)
            allocatedPath = allocation.relativePath
            let sources = voiced.map { audioFiles.url(forRelativePath: $0.relativePath) }
            let duration = try await joiner.join(sources, into: allocation.url)
            try? audioFiles.applyProtection(toRelativePath: allocation.relativePath)
            return JoinedVoice(relativePath: allocation.relativePath, durationSec: duration, isJoinedFile: true)
        } catch {
            // つなげなくても約束は残す。声は約束の録音だけを使う。
            logger.error("voice join failed: \(error.localizedDescription, privacy: .public)")
            deleteAudio(allocatedPath)
            return first
        }
    }

    // MARK: - 補助

    private func deleteAudio(_ relativePath: String?) {
        guard let relativePath else { return }
        do {
            try audioFiles.delete(relativePath: relativePath)
        } catch {
            logger.error("audio delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 録音の開始と確定を、押した順・離した順に 1 つずつ処理する。
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = pendingWork
        enqueuedCount += 1
        pendingWork = Task {
            await previous?.value
            await work()
        }
    }

    /// 押す・離すで始めた処理（録音の開始、文字起こしの確定）が済むまで待つ。
    func waitForPendingWork() async {
        var seen = -1
        while seen != enqueuedCount {
            seen = enqueuedCount
            await pendingWork?.value
        }
    }
}
