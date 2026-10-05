import AVFoundation
import Foundation
import SaydoCore
import Speech
import XCTest

@testable import Saydo

// MARK: - インメモリの保存

/// `SessionStore` のインメモリ実装。`Repository` と同じ規則
/// （1 日 1 件の `Commitment`、宣言音声があれば宣言の `VoiceEntry` も作る）だけを写す。
actor InMemorySessionStore: SessionStore {
    struct SessionLogRecord: Sendable, Equatable {
        var id: UUID
        var sessionType: SessionType
        var startedAt: Date
        var endedAt: Date?
        var completed: Bool
        var tier: DialogueTier
        var lastStep: FlowStep?
        var guardrailReplacedCount: Int
    }

    private(set) var commitments: [CommitmentSnapshot] = []
    private(set) var entries: [VoiceEntrySnapshot] = []
    private(set) var carryovers: [CarryoverSnapshot] = []
    private(set) var logs: [SessionLogRecord] = []
    private(set) var avoidanceStatuses: [UUID: AvoidanceStatus] = [:]

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: 事前に積む

    func seed(_ commitment: CommitmentSnapshot) {
        commitments.append(commitment)
    }

    func seed(_ carryover: CarryoverSnapshot) {
        carryovers.append(carryover)
    }

    // MARK: SessionStore

    func todayCommitment(on date: Date) throws -> CommitmentSnapshot? {
        let key = DayKey.make(from: date, calendar: calendar)
        return commitments.first { $0.dayKey == key }
    }

    func createCommitment(_ draft: CommitmentDraft) throws -> CommitmentSnapshot {
        let key = DayKey.make(from: draft.createdAt, calendar: calendar)
        if commitments.contains(where: { $0.dayKey == key }) {
            throw RepositoryError.commitmentAlreadyExists(dayKey: key)
        }
        let snapshot = CommitmentSnapshot(
            id: draft.id,
            dayKey: key,
            microAction: draft.microAction,
            plannedAt: draft.plannedAt,
            plannedPlace: draft.plannedPlace,
            declarationAudioPath: draft.declarationAudioPath,
            declarationTranscript: draft.declarationTranscript,
            isVoiceless: draft.isVoiceless,
            outcome: .pending,
            reason: draft.reason,
            progressNote: nil,
            createdAt: draft.createdAt,
            avoidanceID: UUID(),
            avoidanceTitle: draft.avoidanceTitle,
            domain: draft.domain
        )
        commitments.append(snapshot)

        // `Repository.createCommitment` と同じく、宣言音声があれば宣言の `VoiceEntry` も作る。
        if let audioPath = draft.declarationAudioPath {
            entries.append(
                VoiceEntrySnapshot(
                    id: UUID(),
                    recordedAt: draft.createdAt,
                    sessionType: draft.sessionType,
                    kind: .declaration,
                    audioPath: audioPath,
                    transcript: draft.declarationTranscript,
                    durationSec: draft.declarationDurationSec,
                    commitmentID: snapshot.id
                )
            )
        }
        return snapshot
    }

    func updateOutcome(
        commitmentID: UUID,
        outcome: CommitmentOutcome,
        progressNote: String?,
        at date: Date
    ) throws -> CommitmentSnapshot {
        guard let index = commitments.firstIndex(where: { $0.id == commitmentID }) else {
            throw RepositoryError.commitmentNotFound(id: commitmentID)
        }
        commitments[index].outcome = outcome
        if let progressNote {
            commitments[index].progressNote = progressNote
        }
        return commitments[index]
    }

    func shrink(
        commitmentID: UUID,
        to text: String,
        estimatedMinutes: Int,
        at date: Date
    ) throws -> CommitmentSnapshot {
        guard let index = commitments.firstIndex(where: { $0.id == commitmentID }) else {
            throw RepositoryError.commitmentNotFound(id: commitmentID)
        }
        commitments[index].microAction = commitments[index].microAction
            .shrunk(to: text, estimatedMinutes: estimatedMinutes)
        return commitments[index]
    }

    func updateAvoidanceStatus(commitmentID: UUID, status: AvoidanceStatus, at date: Date) throws {
        guard commitments.contains(where: { $0.id == commitmentID }) else {
            throw RepositoryError.commitmentNotFound(id: commitmentID)
        }
        avoidanceStatuses[commitmentID] = status
    }

    func appendVoiceEntry(_ draft: VoiceEntryDraft) throws -> VoiceEntrySnapshot {
        let snapshot = VoiceEntrySnapshot(
            id: draft.id,
            recordedAt: draft.recordedAt,
            sessionType: draft.sessionType,
            kind: draft.kind,
            audioPath: draft.audioPath,
            transcript: draft.transcript,
            durationSec: draft.durationSec,
            commitmentID: draft.commitmentID
        )
        entries.append(snapshot)
        return snapshot
    }

    func deleteVoiceEntry(id: UUID) throws {
        entries.removeAll { $0.id == id }
    }

    func entries(for day: Date) throws -> [VoiceEntrySnapshot] {
        let key = DayKey.make(from: day, calendar: calendar)
        return entries
            .filter { DayKey.make(from: $0.recordedAt, calendar: calendar) == key }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func carryover(for day: Date) throws -> CarryoverSnapshot? {
        let key = DayKey.make(from: day, calendar: calendar)
        return carryovers.last { $0.forDayKey == key }
    }

    func saveCarryover(
        forDay day: Date,
        text: String,
        sourceEntryID: UUID?,
        at date: Date
    ) throws -> CarryoverSnapshot {
        let key = DayKey.make(from: day, calendar: calendar)
        carryovers.removeAll { $0.forDayKey == key }
        let snapshot = CarryoverSnapshot(
            id: UUID(),
            forDayKey: key,
            text: text,
            sourceEntryID: sourceEntryID,
            createdAt: date
        )
        carryovers.append(snapshot)
        return snapshot
    }

    func lastEntryDate() throws -> Date? {
        entries.map(\.recordedAt).max()
    }

    func startSessionLog(sessionType: SessionType, startedAt: Date, tier: DialogueTier) throws -> UUID {
        let record = SessionLogRecord(
            id: UUID(),
            sessionType: sessionType,
            startedAt: startedAt,
            endedAt: nil,
            completed: false,
            tier: tier,
            lastStep: nil,
            guardrailReplacedCount: 0
        )
        logs.append(record)
        return record.id
    }

    func finishSessionLog(
        id: UUID,
        endedAt: Date,
        completed: Bool,
        lastStep: FlowStep?,
        guardrailReplacedCount: Int
    ) throws {
        guard let index = logs.firstIndex(where: { $0.id == id }) else { return }
        logs[index].endedAt = endedAt
        logs[index].completed = completed
        logs[index].lastStep = lastStep
        logs[index].guardrailReplacedCount = guardrailReplacedCount
    }
}

// MARK: - 通知のモック

actor SpyNotificationScheduler: NotificationScheduling {
    struct Scheduled: Sendable, Equatable {
        var kind: NotificationRequest.Kind
        var timePhrase: String?
        var onlyOnce: Bool
        var fireDate: Date?
        var commitmentID: UUID?
    }

    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelled: [NotificationRequest.Kind] = []

    func schedule(_ request: NotificationRequest, fireDate: Date?, commitmentID: UUID?, on day: Date) throws {
        scheduled.append(
            Scheduled(
                kind: request.kind,
                timePhrase: request.timePhrase,
                onlyOnce: request.onlyOnce,
                fireDate: fireDate,
                commitmentID: commitmentID
            )
        )
    }

    func cancel(_ kind: NotificationRequest.Kind, on day: Date) throws {
        cancelled.append(kind)
    }
}

// MARK: - 音声のモック

/// 読み上げのモック。実物（`SpeechSynthesisService`）と同じ 2 つの性質を持つ。
///
/// - `holdsCompletion` が true のあいだ、`speak()` はテストが `completeNext()` で完了を解放するまで戻らない。
/// - 呼び出し元のタスクが止められていると、完了を待たずにすぐ戻る（`for await` で待つため）。
///   このとき音は鳴り続けている扱いにし、`unfinishedCount` には残す。
///
/// 既定（`holdsCompletion == false`）は呼ばれた時点で読み終えた扱いにする。
@MainActor
final class MockSynthesizer: Synthesizing {
    private(set) var spokenLines: [String] = []
    private(set) var stopCount = 0
    var isSpeaking: Bool { !unfinished.isEmpty }
    var hasHighQualityJapaneseVoice = true
    var voiceQuality: SynthesisVoiceQuality = .enhanced

    /// true にすると、読み上げの完了をテストが解放するまで遅らせる。
    var holdsCompletion = false
    /// まだ鳴り終わっていない読み上げ。
    private var unfinished: [AsyncStream<Void>.Continuation] = []
    var unfinishedCount: Int { unfinished.count }

    func speak(_ text: String, preferReceiver: Bool) async {
        spokenLines.append(text)
        guard holdsCompletion else { return }
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        unfinished.append(continuation)
        for await _ in completion {}
    }

    /// いちばん古い読み上げを読み終えさせる。
    func completeNext() {
        guard !unfinished.isEmpty else { return }
        unfinished.removeFirst().finish()
    }

    func stop() {
        stopCount += 1
        releaseAll()
    }

    /// テストの後始末。待っているタスクを残さない。
    func releaseAll() {
        for continuation in unfinished {
            continuation.finish()
        }
        unfinished = []
    }
}

/// テストが開けるまで待たせる門。録音の準備や確定の `await` を途中で止めるのに使う。
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var waitingCount: Int { waiters.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

/// テストが発火させるまで待ち続けるタイマー。止められたら実物と同じく投げる。
actor ManualTimer {
    private var sleepers: [(duration: Duration, wake: AsyncStream<Void>.Continuation)] = []

    func sleep(_ duration: Duration) async throws {
        let (woken, wake) = AsyncStream<Void>.makeStream()
        sleepers.append((duration, wake))
        for await _ in woken {}
        try Task.checkCancellation()
    }

    func isWaiting(for duration: Duration) -> Bool {
        sleepers.contains { $0.duration == duration }
    }

    func fire(_ duration: Duration) {
        for sleeper in sleepers where sleeper.duration == duration {
            sleeper.wake.finish()
        }
        sleepers.removeAll { $0.duration == duration }
    }
}

@MainActor
final class MockPlayer: Playing {
    private(set) var playedURLs: [URL] = []
    /// 受話口で鳴らすよう頼まれたか（retention R8 の「耳に当てて聞く」）。
    private(set) var preferReceiverFlags: [Bool] = []
    private(set) var stopCount = 0
    var isPlaying = false
    var currentURL: URL?

    func play(_ url: URL, preferReceiver: Bool) async throws {
        playedURLs.append(url)
        preferReceiverFlags.append(preferReceiver)
        currentURL = url
    }

    func stop() {
        stopCount += 1
        isPlaying = false
    }
}

/// 再生前の配慮（retention R8）の判定だけを差し替えるモック。`AVAudioSession` には触らない。
@MainActor
final class MockAudioSession: AudioSessionControlling {
    let events: AsyncStream<AudioSessionEvent>
    private let continuation: AsyncStream<AudioSessionEvent>.Continuation

    private(set) var isActive = false
    var isAccessoryConnected = false
    var outputVolume: Float = 0.8
    var requiresAudiblePlaybackConfirmation: Bool
    private(set) var appliedRoutes: [AudioOutputRoute] = []

    init(requiresConfirmation: Bool) {
        let (stream, continuation) = AsyncStream<AudioSessionEvent>.makeStream()
        events = stream
        self.continuation = continuation
        requiresAudiblePlaybackConfirmation = requiresConfirmation
    }

    func activate(mode: AudioSessionMode) throws {
        isActive = true
    }

    func deactivate() {
        isActive = false
        continuation.finish()
    }

    @discardableResult
    func applyOutputRoute(preferReceiver: Bool) -> AudioOutputRoute {
        let route: AudioOutputRoute = preferReceiver
            ? .receiver
            : (isAccessoryConnected ? .accessory : .speaker)
        appliedRoutes.append(route)
        return route
    }
}

/// 文言の使用履歴をメモリに置く実装。`UserDefaults` を汚さずに保存の効き目を見る。
@MainActor
final class InMemoryCopyHistoryStore: CopyHistoryStoring {
    private(set) var stored: [CopyPicker.Use] = []

    func load(currentDay: Int) -> [CopyPicker.Use] {
        UserDefaultsCopyHistoryStore.pruned(stored, currentDay: currentDay)
    }

    func save(_ uses: [CopyPicker.Use]) {
        stored = uses
    }
}

/// 「話し始めて、無音で終わる」1 回分の RMS 列を流す録音。
/// 実際の `AVAudioEngine` には触らない。
///
/// 既定では録音を始めるたびに自動で流す。`autoSilenceStarts` を決めると、その回数を超えた録音は
/// 何も流さずに開いたままにする（テストが `speakThenFallSilent()` を呼ぶか、`stop()` されるまで）。
@MainActor
final class MockVoiceCapture: VoiceCapturing {
    private(set) var isCapturing = false
    var recordingURL: URL?
    var limit: VoiceCaptureLimit = .utterance

    /// 何回目の録音まで自動で「話して、無音で終わる」を流すか。nil は毎回。
    var autoSilenceStarts: Int?
    /// 録音を始めた瞬間に呼ぶ。読み上げと重なっていないかを見るのに使う。
    var onStart: (() -> Void)?

    private(set) var startCount = 0
    /// 開始を呼ばれた回数（失敗した分も数える）。`startCount` は成功した回数。
    private(set) var attemptCount = 0
    /// 何回目の開始呼び出しを失敗させるか（1 始まり）。マイクの権限はあるのに一時的に失敗する場面を作る。
    var failingAttempts: Set<Int> = []
    private var eventContinuation: AsyncStream<VoiceCaptureEvent>.Continuation?

    func start(writingTo url: URL, analyzerFormat: AVAudioFormat?) throws -> VoiceCaptureSession {
        attemptCount += 1
        if failingAttempts.contains(attemptCount) { throw VoiceCaptureFault.inputUnavailable }
        // 実物と同じく、録音中の二重開始は失敗にする。
        guard !isCapturing else { throw VoiceCaptureFault.alreadyCapturing }
        startCount += 1
        isCapturing = true
        recordingURL = url
        onStart?()

        let (events, continuation) = AsyncStream<VoiceCaptureEvent>.makeStream()
        eventContinuation = continuation
        if autoSilenceStarts.map({ startCount <= $0 }) ?? true {
            speakThenFallSilent()
        }

        let (analyzerInput, analyzerContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        analyzerContinuation.finish()

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        return VoiceCaptureSession(
            recordingURL: url,
            events: events,
            analyzerInput: analyzerInput,
            inputFormat: AudioFormatSummary(format),
            analyzerFormat: AudioFormatSummary(format)
        )
    }

    /// 発話 1 秒 → 無音 2.5 秒。`SilenceDetector` の 1.5 秒（宣言は 2.0 秒）を必ず越える。
    /// 止めた後の録音には何も流れない（実物も `stop()` でストリームを閉じる）。
    func speakThenFallSilent() {
        guard let continuation = eventContinuation else { return }
        for _ in 0..<10 {
            continuation.yield(.level(rms: 0.4, duration: 0.1))
        }
        continuation.yield(.level(rms: 0.0, duration: 2.5))
        continuation.finish()
        eventContinuation = nil
    }

    func stop() {
        isCapturing = false
        eventContinuation?.finish()
        eventContinuation = nil
    }
}

/// あらかじめ決めた文字起こしを順に返す。
@MainActor
final class MockTranscriber: Transcribing {
    var script: [String]
    var volatileText = ""
    private(set) var finalText = ""
    var assetState: TranscriptionAssetState = .installed
    var isRunning = false

    init(script: [String]) {
        self.script = script
    }

    /// 置くと、録音の準備（`prepare()`）がこの門が開くまで戻らない。
    var prepareGate: Gate?
    /// 置くと、確定（`finish()`）がこの門が開くまで戻らない。
    var finishGate: Gate?

    func prepare() async throws -> AVAudioFormat {
        await prepareGate?.wait()
        return AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    }

    /// 開始を呼ばれた回数（失敗した分も数える）。
    private(set) var startAttemptCount = 0
    /// 何回目の開始呼び出しを失敗させるか（1 始まり）。
    var failingStarts: Set<Int> = []
    /// 置くと、開始（`start`）がこの門が開くまで戻らない。
    var startGate: Gate?

    func start(inputSequence: AsyncStream<AnalyzerInput>) async throws {
        startAttemptCount += 1
        let attempt = startAttemptCount
        await startGate?.wait()
        if failingStarts.contains(attempt) { throw VoiceCaptureFault.converterUnavailable }
        isRunning = true
    }

    func finish() async -> String {
        isRunning = false
        await finishGate?.wait()
        finalText = script.isEmpty ? "" : script.removeFirst()
        return finalText
    }

    func cancel() {
        isRunning = false
        volatileText = ""
        finalText = ""
    }

    func reset() {
        volatileText = ""
        finalText = ""
    }
}

// MARK: - テスト本体

@MainActor
final class SessionViewModelTests: XCTestCase {

    /// タイマーは張るが決して発火しない。時間経過そのものはテストが直接与える。
    private static let frozenTimer = SessionTimer(sleep: { _ in throw CancellationError() })

    private var root: URL!
    private var audioFiles: AudioFileStore!
    private var store: InMemorySessionStore!
    private var notifications: SpyNotificationScheduler!
    private var synthesizer: MockSynthesizer!
    private var capture: MockVoiceCapture!
    private var player: MockPlayer!

    private let reference = Date(timeIntervalSince1970: 1_757_000_000) // 2026-09-04 頃

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appending(path: "SessionViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        audioFiles = AudioFileStore(rootDirectory: root)
        store = InMemorySessionStore()
        notifications = SpyNotificationScheduler()
        synthesizer = MockSynthesizer()
        capture = MockVoiceCapture()
        player = MockPlayer()
    }

    override func tearDown() async throws {
        // 読み上げの完了を待ったままのタスクを残さない。
        synthesizer?.releaseAll()
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
        try await super.tearDown()
    }

    private func makeViewModel(
        transcript script: [String] = [],
        transcriber: MockTranscriber? = nil,
        timer: SessionTimer = SessionViewModelTests.frozenTimer,
        audioSession: (any AudioSessionControlling)? = nil,
        copyHistory: (any CopyHistoryStoring)? = nil,
        at moment: Date? = nil
    ) -> (SessionViewModel, MockTranscriber) {
        let mock = transcriber ?? MockTranscriber(script: script)
        let now = moment ?? reference
        let viewModel = SessionViewModel(
            store: store,
            synthesizer: synthesizer,
            capture: capture,
            transcriber: mock,
            player: player,
            notifications: notifications,
            engine: TemplateDialogueEngine(),
            audioFiles: audioFiles,
            audioSession: audioSession,
            // 既定はインメモリ。テストが `UserDefaults.standard` を汚さないようにする。
            copyHistory: copyHistory ?? InMemoryCopyHistoryStore(),
            timer: timer,
            tier: .b,
            calendar: .current,
            now: { now }
        )
        return (viewModel, mock)
    }

    /// 録音の非同期な取り込みが落ち着くまで待つ。実時間は使わない。
    private func settle(until predicate: () -> Bool, limit: Int = 2_000) async {
        for _ in 0..<limit {
            if predicate() { return }
            await Task.yield()
        }
    }

    /// 背景の Task（見張りタイマーなど）に一度は走らせる。
    private func drain(_ times: Int = 64) async {
        for _ in 0..<times {
            await Task.yield()
        }
    }

    // MARK: - 朝フロー（声で完走）

    func testMorningFlowCompletesAndSavesCommitmentWithThreeVoiceEntries() async throws {
        // M0 → M1（声）→ M2 → M3 → M4 をすべて声で答える。
        let (viewModel, _) = makeViewModel(transcript: [
            "見積書を送るのが嫌だ",
            "気まずいから",
            "見積書のファイルを開く",
            "14時に自宅で",
            "今日、14時に見積書のファイルを開く",
        ])

        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.completion != nil })

        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(viewModel.phase, .done)

        let commitment = try XCTUnwrap(viewModel.commitment)
        XCTAssertEqual(commitment.avoidanceTitle, "見積書を送るのが嫌だ")
        XCTAssertEqual(commitment.microAction.text, "見積書のファイルを開く")
        XCTAssertFalse(commitment.isVoiceless)
        XCTAssertNotNil(commitment.declarationAudioPath)
        XCTAssertNotNil(commitment.plannedAt)

        // 当日の VoiceEntry は avoidance / reason / declaration の 3 件。
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.kind)), [.avoidance, .reason, .declaration])
        // 宣言の音声は Commitment と同一ファイルを指す。
        let declaration = try XCTUnwrap(entries.first { $0.kind == .declaration })
        XCTAssertEqual(declaration.audioPath, commitment.declarationAudioPath)

        // SessionLog に開始・終了・完走・tier・lastStep が残る。
        let logs = await store.logs
        XCTAssertEqual(logs.count, 1)
        let log = try XCTUnwrap(logs.first)
        XCTAssertEqual(log.sessionType, .morning)
        XCTAssertEqual(log.startedAt, reference)
        XCTAssertNotNil(log.endedAt)
        XCTAssertTrue(log.completed)
        XCTAssertEqual(log.tier, .b)
        XCTAssertEqual(log.lastStep, .morningDeclaration)
        XCTAssertEqual(log.guardrailReplacedCount, 0)

        // 行動時刻の通知が、作った Commitment の id 付きで登録される。
        let scheduled = await notifications.scheduled
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.kind, .actionTime)
        XCTAssertEqual(scheduled.first?.commitmentID, commitment.id)
        XCTAssertNotNil(scheduled.first?.fireDate)
    }

    /// マイク拒否（テキストで完走）でも `VoiceEntry` は 3 件、`Commitment` は「声なし」。
    func testMorningFlowWithoutMicrophoneStillSavesThreeVoiceEntries() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)

        XCTAssertEqual(viewModel.notice, .micDenied)
        await viewModel.submit(text: "請求書を出すのが嫌だ")
        await viewModel.select(Choice(.reason(.awkward)))
        await viewModel.submit(text: "請求書の雛形を開く")
        await viewModel.submit(text: "15時に会社で")
        // 「話せない時」経路では M4 で「今、声で言う / 後で声で」を選ぶ。
        await viewModel.select(Choice(.declareLater))
        await viewModel.submit(text: "今日、15時に請求書の雛形を開く")

        XCTAssertEqual(viewModel.completion, .completed)
        let commitment = try XCTUnwrap(viewModel.commitment)
        XCTAssertTrue(commitment.isVoiceless)
        XCTAssertNil(commitment.declarationAudioPath)
        XCTAssertEqual(commitment.reason, .awkward)

        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.kind)), [.avoidance, .reason, .declaration])
        XCTAssertTrue(entries.allSatisfy { $0.audioPath == nil })

        // 宣言を後回しにしたので、1 回だけの再通知が登録される（retention R1）。
        let deferred = await notifications.scheduled
        XCTAssertTrue(deferred.contains { $0.kind == .declarationReminder && $0.onlyOnce })
    }

    /// M0 の文字起こしは 1 行だけ出て、1 回だけ録り直せる（retention R7）。
    func testAvoidanceTranscriptCanBeRetakenOnce() async throws {
        let (viewModel, transcriber) = makeViewModel(transcript: ["見積書を送るのが嫌だ"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { !viewModel.avoidanceTranscript.isEmpty })

        XCTAssertEqual(viewModel.avoidanceTranscript, "見積書を送るのが嫌だ")
        XCTAssertTrue(viewModel.canRetakeAvoidance)
        let beforeRetake = try await store.entries(for: reference)
        XCTAssertEqual(beforeRetake.filter { $0.kind == .avoidance }.count, 1)

        transcriber.script = ["見積書を送るのが怖い"]
        await viewModel.retakeAvoidance()
        await settle(until: { viewModel.avoidanceTranscript == "見積書を送るのが怖い" })

        XCTAssertEqual(viewModel.avoidanceTranscript, "見積書を送るのが怖い")
        // 録り直しは 1 回だけ。
        XCTAssertFalse(viewModel.canRetakeAvoidance)
        // 誤認識のほうは残さない。
        let afterRetake = try await store.entries(for: reference)
        XCTAssertEqual(afterRetake.filter { $0.kind == .avoidance }.count, 1)
        XCTAssertEqual(afterRetake.first { $0.kind == .avoidance }?.transcript, "見積書を送るのが怖い")
    }

    // MARK: - 昼フローの入口 3 状態（fix-decisions P2.6）

    /// 当日の `Commitment` が無ければ短縮版の朝フロー（M0 → M2 → M4）を開き、M1 は出さない。
    func testNoonWithoutCommitmentOpensShortMorningFlow() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.submit(text: "経費精算を出すのが嫌だ")
        // M1 を飛ばして M2 に来ている。
        await viewModel.submit(text: "経費精算の画面を開く")
        await viewModel.select(Choice(.declareLater))
        await viewModel.submit(text: "今日、経費精算の画面を開く")

        XCTAssertEqual(viewModel.completion, .completed)
        let commitment = try XCTUnwrap(viewModel.commitment)
        // 理由を聞かない日は `reason` を持たない。
        XCTAssertNil(commitment.reason)
        // 宣言の再生（N0）は起きない。
        XCTAssertTrue(player.playedURLs.isEmpty)

        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .reason }.count, 0)
        XCTAssertEqual(Set(entries.map(\.kind)), [.avoidance, .declaration])
    }

    /// すでに `done` なら固定の昼通知と行動時刻通知を取り消して終わる。
    func testNoonAfterDoneCancelsNotificationsAndEnds() async throws {
        await store.seed(makeCommitment(outcome: .done, plannedAt: reference.addingTimeInterval(-3_600)))

        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        XCTAssertEqual(viewModel.completion, .completed)
        let cancelled = await notifications.cancelled
        XCTAssertEqual(cancelled, [.noonFixed, .actionTime])
        XCTAssertTrue(player.playedURLs.isEmpty)
    }

    /// 行動時刻より前なら「どうだった？」を出さず、約束の確認だけで終わる。
    func testNoonBeforePlannedTimeAsksPromiseOnly() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(3_600)))

        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        XCTAssertEqual(viewModel.phase, .choosing)
        XCTAssertEqual(viewModel.choices.map(\.id), [.promiseAlive, .changeTime])
        XCTAssertTrue(player.playedURLs.isEmpty)

        await viewModel.select(Choice(.promiseAlive))
        XCTAssertEqual(viewModel.completion, .completed)
    }

    // MARK: - 昼 N1 の 3 分岐

    func testNoonStatusDoneEndsWithoutBlocker() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600)))
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        // N0 の再生が終わって N1 に来ている。
        XCTAssertEqual(player.playedURLs.count, 1)
        await viewModel.select(Choice(.status(.done)))

        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(viewModel.commitment?.outcome, .done)
        let cancelled = await notifications.cancelled
        XCTAssertTrue(cancelled.contains(.actionTime))

        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .status }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .blocker }.count, 0)
    }

    /// 「少しやった」も前進。N2 に進まず `partial` で終わる（fix-decisions P2.5）。
    func testNoonStatusPartialIsTreatedAsProgress() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600)))
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.select(Choice(.status(.partial)))

        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(viewModel.commitment?.outcome, .partial)
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .blocker }.count, 0)
    }

    /// 「まだ」は N2（止めているもの）→ N3（再縮小）へ進む。
    func testNoonStatusNotYetGoesToBlockerAndShrink() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600)))
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.select(Choice(.status(.notYet)))
        await viewModel.submit(text: "何から書けばいいかわからない")
        await viewModel.submit(text: "宛先だけ書く")

        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(viewModel.commitment?.outcome, .notYet)
        // 本人の言い直した行動に置き換わり、shrinkCount が 1 増える（check_003）。
        XCTAssertEqual(viewModel.commitment?.microAction.text, "宛先だけ書く")
        XCTAssertEqual(viewModel.commitment?.microAction.shrinkCount, 1)

        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .status }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .blocker }.count, 1)
    }

    // MARK: - 選択に応じた AvoidanceItem.status（task_011 scope）

    /// N3 で「今日は捨てる」を選ぶと逃げている対象が dropped になる。
    func testNoonDropTodayMarksTheAvoidanceDropped() async throws {
        let seeded = makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600))
        await store.seed(seeded)
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.select(Choice(.status(.notYet)))
        await viewModel.submit(text: "何から書けばいいかわからない")
        await viewModel.select(Choice(.dropToday))

        XCTAssertEqual(viewModel.completion, .completed)
        let statuses = await store.avoidanceStatuses
        XCTAssertEqual(statuses[seeded.id], .dropped)
    }

    /// N3 で「明日に回す」を選ぶと carriedOver になる。
    func testNoonMoveToTomorrowMarksTheAvoidanceCarriedOver() async throws {
        let seeded = makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600))
        await store.seed(seeded)
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.select(Choice(.status(.notYet)))
        await viewModel.submit(text: "何から書けばいいかわからない")
        await viewModel.select(Choice(.moveToTomorrow))

        XCTAssertEqual(viewModel.completion, .completed)
        let statuses = await store.avoidanceStatuses
        XCTAssertEqual(statuses[seeded.id], .carriedOver)
    }

    /// N1 の「やった」で対象は done になる。「まだ」→ 言い直しの経路では状態を変えない。
    func testNoonDoneMarksTheAvoidanceDoneAndShrinkLeavesItOpen() async throws {
        let seeded = makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600))
        await store.seed(seeded)
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.select(Choice(.status(.done)))

        XCTAssertEqual(viewModel.completion, .completed)
        let statuses = await store.avoidanceStatuses
        XCTAssertEqual(statuses[seeded.id], .done)
    }

    func testNoonShrinkLeavesTheAvoidanceStatusUntouched() async throws {
        let seeded = makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600))
        await store.seed(seeded)
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.select(Choice(.status(.notYet)))
        await viewModel.submit(text: "何から書けばいいかわからない")
        await viewModel.submit(text: "宛先だけ書く")

        XCTAssertEqual(viewModel.completion, .completed)
        let statuses = await store.avoidanceStatuses
        XCTAssertNil(statuses[seeded.id])
    }

    /// 夜 E0 で前進が無く「明日に回す」を選ぶと carriedOver になる。
    func testNightMoveToTomorrowMarksTheAvoidanceCarriedOver() async throws {
        let seeded = makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600))
        await store.seed(seeded)
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .night, microphoneGranted: false)

        await viewModel.submit(text: "何もできなかった")
        await viewModel.select(Choice(.moveToTomorrow))
        await viewModel.submit(text: "午前中に送る")

        XCTAssertEqual(viewModel.completion, .completed)
        let statuses = await store.avoidanceStatuses
        XCTAssertEqual(statuses[seeded.id], .carriedOver)
    }

    // MARK: - 夜 → 翌朝の引き継ぎ

    func testNightTomorrowBecomesNextMorningCarryover() async throws {
        let (night, _) = makeViewModel()
        await night.start(sessionType: .night, microphoneGranted: false)

        await night.submit(text: "見積書の宛先だけ書いた")
        await night.submit(text: "午前中に送る")

        XCTAssertEqual(night.completion, .completed)
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .progress }.count, 1)
        XCTAssertEqual(entries.filter { $0.kind == .tomorrow }.count, 1)

        // 翌朝の M0 は引き継ぎ確認から始まる。
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: reference))
        let saved = try await store.carryover(for: tomorrow)
        XCTAssertEqual(saved?.text, "午前中に送る")

        let nextMorning = SessionViewModel(
            store: store,
            synthesizer: synthesizer,
            capture: capture,
            transcriber: MockTranscriber(script: []),
            player: player,
            notifications: notifications,
            engine: TemplateDialogueEngine(),
            audioFiles: audioFiles,
            copyHistory: InMemoryCopyHistoryStore(),
            timer: Self.frozenTimer,
            tier: .b,
            calendar: .current,
            now: { tomorrow }
        )
        await nextMorning.start(sessionType: .morning, microphoneGranted: false)

        XCTAssertEqual(nextMorning.phase, .choosing)
        XCTAssertEqual(nextMorning.choices.map(\.id), [.carryoverKeep, .carryoverChange])
        XCTAssertTrue(nextMorning.spokenLine.contains("午前中に送る"))
    }

    /// 夜に前進が無い日のチップは 2 つだけ（fix-decisions P2.4）。
    func testNightWithoutProgressShowsTwoChoices() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .night, microphoneGranted: false)

        await viewModel.submit(text: "何もできなかった")

        XCTAssertEqual(viewModel.phase, .choosing)
        XCTAssertEqual(viewModel.choices.map(\.id), [.shrinkMore, .moveToTomorrow])
    }

    // MARK: - タイムアウト経路

    /// 沈黙 5 秒で催促を 1 回だけ挟む。必須の M0 は、さらに 10 秒黙っても次へ進まず、
    /// その質問だけ文字の入力待ちに落ちる（実装計画 §16.7）。
    func testSilenceNudgesOnceThenARequiredQuestionFallsBackToText() async throws {
        let recorder = DurationRecorder()
        let timer = SessionTimer(sleep: { duration in
            await recorder.record(duration)
            // 待ち時間そのものは進めない。時間経過はテストが直接与える。
            throw CancellationError()
        })
        capture.autoSilenceStarts = 0
        let (viewModel, _) = makeViewModel(timer: timer)

        await viewModel.start(sessionType: .morning)
        await settle(until: { self.capture.isCapturing })
        await drain()

        // タイムボックス（朝 3 分）と M0 の沈黙（5 秒）の 2 本が張られる。
        var durations = await recorder.durations
        XCTAssertTrue(durations.contains(.seconds(180)))
        XCTAssertTrue(durations.contains(.seconds(FlowMachine.firstSilenceSeconds)))

        // 5 秒沈黙 → 催促を 1 回だけ挟み、次は 10 秒待つ。
        let linesBefore = synthesizer.spokenLines.count
        await viewModel.silenceElapsed()
        await settle(until: { self.capture.startCount == 2 })
        await drain()
        durations = await recorder.durations
        XCTAssertTrue(durations.contains(.seconds(FlowMachine.secondSilenceSeconds)))
        XCTAssertEqual(synthesizer.spokenLines.count, linesBefore + 1)
        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)
        XCTAssertNil(viewModel.completion)

        // さらに 10 秒沈黙 → 逃げたいことが空のまま M1 へは進まない。この質問だけ文字で待つ。
        let watchesBefore = durations.count
        await viewModel.silenceElapsed()
        await drain()
        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)
        XCTAssertNil(viewModel.completion)
        XCTAssertTrue(viewModel.acceptsTextInput)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(capture.startCount, 2)
        XCTAssertFalse(viewModel.isVoiceless, "その日を声なしに固定しない")
        let prompts = Set(DialogueCopy.variants(.requiredTextPrompt).map(\.text))
        XCTAssertTrue(prompts.contains(synthesizer.spokenLines.last ?? ""))
        // 文字の入力待ちでは沈黙の見張りを張らない。
        durations = await recorder.durations
        XCTAssertEqual(durations.count, watchesBefore)

        // 文字で答えると次の質問へ進み、そこでは声に戻る。
        await viewModel.submit(text: "見積書を送るのが嫌だ")
        await settle(until: { self.capture.startCount == 3 })
        XCTAssertEqual(viewModel.currentStep, .morningReason)
        XCTAssertFalse(viewModel.acceptsTextInput)
        XCTAssertTrue(capture.isCapturing)

        await viewModel.interrupt()
    }

    /// 必須でない質問（M1）は、従来どおり沈黙 2 回で次へ進む。
    func testSilenceTwiceOnAQuestionThatIsNotRequiredStillAdvances() async throws {
        capture.autoSilenceStarts = 1
        let (viewModel, _) = makeViewModel(transcript: ["見積書を送るのが嫌だ"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.currentStep == .morningReason && self.capture.startCount == 2 })

        await viewModel.silenceElapsed()
        await settle(until: { self.capture.startCount == 3 })
        XCTAssertEqual(viewModel.currentStep, .morningReason)

        await viewModel.silenceElapsed()
        await settle(until: { self.capture.startCount == 4 })
        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)
        XCTAssertNil(viewModel.completion)

        await viewModel.interrupt()
    }

    /// M2 は沈黙 2 回でも M3 へ進まず、押せる例のチップを出す。押せばその行動で先へ進む。
    func testSilenceTwiceAtMicroActionOffersTheActionChips() async throws {
        capture.autoSilenceStarts = 2
        let (viewModel, _) = makeViewModel(transcript: ["見積書を送るのが嫌だ", "気まずいから"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.currentStep == .morningMicroAction && self.capture.startCount == 3 })

        await viewModel.silenceElapsed()
        await settle(until: { self.capture.startCount == 4 })
        await viewModel.silenceElapsed()
        await drain()

        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)
        XCTAssertEqual(viewModel.phase, .choosing)
        XCTAssertEqual(viewModel.choices.map(\.id), DialogueCopy.exampleActionIDs)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertNil(viewModel.completion)

        await viewModel.select(Choice(.exampleOpen))
        await settle(until: { viewModel.currentStep == .morningPlannedTime })
        XCTAssertEqual(viewModel.currentStep, .morningPlannedTime)

        await viewModel.interrupt()
    }

    /// 文字の入力待ちでは沈黙の見張りを起動しない。20 秒経っても催促は読まれず、段階も変わらない。
    func testTextInputWaitIsNeverNudgedOrAdvanced() async throws {
        let manual = ManualTimer()
        let (viewModel, _) = makeViewModel(timer: SessionTimer(sleep: { try await manual.sleep($0) }))

        await viewModel.start(sessionType: .morning, microphoneGranted: false)
        await drain()
        XCTAssertTrue(viewModel.acceptsTextInput)
        XCTAssertEqual(viewModel.phase, .listening)
        // タイマーそのものは配線されている（時間切れの見張りは待っている）。
        for _ in 0..<2_000 {
            if await manual.isWaiting(for: .seconds(180)) { break }
            await Task.yield()
        }
        let timeboxIsArmed = await manual.isWaiting(for: .seconds(180))
        XCTAssertTrue(timeboxIsArmed)

        let linesBefore = synthesizer.spokenLines
        let firstWatch = await manual.isWaiting(for: .seconds(FlowMachine.firstSilenceSeconds))
        XCTAssertFalse(firstWatch, "文字の入力待ちで沈黙の見張りが張られている")

        // 5 秒、10 秒、20 秒が過ぎる。
        for seconds in [FlowMachine.firstSilenceSeconds, FlowMachine.secondSilenceSeconds, FlowMachine.listenMaxSeconds] {
            await manual.fire(.seconds(seconds))
            await drain()
        }

        XCTAssertEqual(synthesizer.spokenLines, linesBefore, "催促も次の質問も読まれない")
        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertTrue(viewModel.acceptsTextInput)
        XCTAssertNil(viewModel.completion)

        await viewModel.interrupt()
    }

    // MARK: - 成立しなかった会話（task_033）

    /// 必須の質問を飛ばした会話は、約束を作らずに終わる。受け取ったとは言わず、SessionLog には未完で残る。
    func testSkippingTheFirstRequiredQuestionEndsAbandonedWithoutACommitment() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)

        await viewModel.skip()

        XCTAssertEqual(viewModel.completion, .abandoned)
        XCTAssertEqual(viewModel.phase, .done)
        XCTAssertNil(viewModel.commitment)
        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 0)
        let entries = try await store.entries(for: reference)
        XCTAssertTrue(entries.isEmpty)
        let scheduled = await notifications.scheduled
        XCTAssertTrue(scheduled.isEmpty)

        let closings = Set(DialogueCopy.variants(.sessionAbandoned).map(\.text))
        XCTAssertTrue(closings.contains(synthesizer.spokenLines.last ?? ""))
        XCTAssertTrue(synthesizer.spokenLines.allSatisfy { !$0.contains("受け取りました") })

        let logs = await store.logs
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.completed, false)
        XCTAssertNotNil(logs.first?.endedAt)
        XCTAssertEqual(logs.first?.lastStep, .morningAvoidance)
    }

    /// 行動（M2）を飛ばした会話も、時刻と宣言へは進まず、約束は 0 件のまま終わる。そこまでの声は残る。
    func testSkippingTheMicroActionEndsAbandonedWithoutACommitment() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)
        await viewModel.submit(text: "見積書を送るのが嫌だ")
        await viewModel.select(Choice(.reason(.awkward)))
        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)

        await viewModel.skip()

        XCTAssertEqual(viewModel.completion, .abandoned)
        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)
        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 0)
        XCTAssertNil(viewModel.commitment)
        let scheduled = await notifications.scheduled
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertTrue(synthesizer.spokenLines.allSatisfy { !$0.contains("受け取りました") })
        // 途中までの記録（逃げたいこと・理由）は消さない。
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(Set(entries.map(\.kind)), [.avoidance, .reason])

        let logs = await store.logs
        XCTAssertEqual(logs.first?.completed, false)
        XCTAssertEqual(logs.first?.lastStep, .morningMicroAction)
    }

    /// 完了画面の締めは、成立しなかった会話にも 1 文を持つ。受け取ったとは言わない。
    func testClosingCopyCoversTheAbandonedSession() {
        let closing = SessionCopy.closing(for: .abandoned)
        XCTAssertFalse(closing.isEmpty)
        XCTAssertFalse(closing.contains("受け取り"))
        XCTAssertTrue(Guardrails.isClean(closing, form: .statement), closing)
    }

    // MARK: - 聞いている途中の時間切れ（task_033）

    /// 聞き取り中に時間切れになっても、その場では打ち切らない。答えが確定してから、次の質問を始めずに終える。
    func testTimeboxWhileListeningWaitsForTheAnswerToSettle() async throws {
        capture.autoSilenceStarts = 0
        let (viewModel, _) = makeViewModel(transcript: ["見積書を送るのが嫌だ"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { self.capture.isCapturing })
        XCTAssertEqual(viewModel.phase, .listening)

        await viewModel.timeboxElapsed()
        await drain()

        // まだ聞いている。会話は終わっていない。
        XCTAssertNil(viewModel.completion)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)

        // 話し終える。答えは保存され、そこで時間切れとして終わる。
        capture.speakThenFallSilent()
        await settle(until: { viewModel.completion != nil })
        await drain()

        XCTAssertEqual(viewModel.completion, .timeboxExceeded)
        XCTAssertEqual(viewModel.phase, .done)
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .avoidance }.map(\.transcript), ["見積書を送るのが嫌だ"])
        XCTAssertNotNil(entries.first { $0.kind == .avoidance }?.audioPath)
        // 次の質問は読まず、聞き取りも始めない。
        let nextQuestions = Set(DialogueCopy.variants(.morningReasonQuestion).map(\.text))
        XCTAssertTrue(synthesizer.spokenLines.allSatisfy { !nextQuestions.contains($0) })
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertFalse(capture.isCapturing)
        let timeboxLines = Set(DialogueCopy.variants(.timeboxExceeded).map(\.text))
        XCTAssertTrue(timeboxLines.contains(synthesizer.spokenLines.last ?? ""))

        let logs = await store.logs
        XCTAssertEqual(logs.first?.completed, false)
        XCTAssertEqual(logs.first?.lastStep, .morningReason)
    }

    /// 宣言の録音中に時間切れになっても、録音を切らない。言い終えた宣言で約束が成立する。
    func testTimeboxWhileRecordingTheDeclarationLetsThePromiseComplete() async throws {
        capture.autoSilenceStarts = 4
        let (viewModel, _) = makeViewModel(transcript: [
            "見積書を送るのが嫌だ",
            "気まずいから",
            "見積書のファイルを開く",
            "14時に自宅で",
            "今日、14時に見積書のファイルを開く",
        ])
        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.phase == .recordingDeclaration })
        XCTAssertTrue(capture.isCapturing)

        await viewModel.timeboxElapsed()
        await drain()

        XCTAssertNil(viewModel.completion)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(viewModel.phase, .recordingDeclaration)

        capture.speakThenFallSilent()
        await settle(until: { viewModel.completion != nil })

        XCTAssertEqual(viewModel.completion, .completed)
        let commitment = try XCTUnwrap(viewModel.commitment)
        XCTAssertNotNil(commitment.declarationAudioPath)
        XCTAssertEqual(commitment.declarationTranscript, "今日、14時に見積書のファイルを開く")
    }

    /// タイムボックス超過はそこまでの入力を保存して終わる。
    func testTimeboxExceededEndsSessionAndRecordsLastStep() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)
        await viewModel.submit(text: "見積書を送るのが嫌だ")

        await viewModel.timeboxElapsed()

        XCTAssertEqual(viewModel.completion, .timeboxExceeded)
        XCTAssertEqual(viewModel.phase, .done)
        // 途中まででも M0 の記録は残る。
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .avoidance }.count, 1)
        // Commitment は作らない（M4 まで来ていない）。
        XCTAssertNil(viewModel.commitment)

        let logs = await store.logs
        XCTAssertEqual(logs.first?.completed, false)
        XCTAssertEqual(logs.first?.lastStep, .morningReason)
    }

    /// 中断（着信・Siri・経路変更）は途中状態を残して閉じ、同じステップから再開できる。
    func testInterruptionSuspendsAndResumesFromSameStep() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)
        await viewModel.submit(text: "見積書を送るのが嫌だ")

        await viewModel.interrupt()

        XCTAssertEqual(viewModel.completion, .suspended)
        let suspended = try XCTUnwrap(viewModel.suspendedState)
        XCTAssertEqual(suspended.step, .morningReason)
        XCTAssertEqual(suspended.avoidance, "見積書を送るのが嫌だ")

        let (resumed, _) = makeViewModel()
        await resumed.start(sessionType: .morning, microphoneGranted: false, resume: suspended)
        XCTAssertEqual(resumed.currentStep, .morningReason)
        // 録音済みの記録は失われない。
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .avoidance }.count, 1)
    }

    // MARK: - 場所の保存（統合判断 D1 / retention R11）

    /// 「何時に、どこで？」の後半を捨てない。`Commitment.plannedPlace` に残る。
    func testPlannedPlaceIsSavedWithTheCommitment() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)

        await viewModel.submit(text: "見積書を送るのが嫌だ")
        await viewModel.select(Choice(.reason(.awkward)))
        await viewModel.submit(text: "見積書のファイルを開く")
        await viewModel.submit(text: "14時に自宅で")
        await viewModel.select(Choice(.declareLater))
        await viewModel.submit(text: "今日、14時に見積書のファイルを開く")

        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(viewModel.plannedPlace, "自宅")
        XCTAssertEqual(viewModel.commitment?.plannedPlace, "自宅")
    }

    /// 場所を言わなかった日は nil のままにする（空文字を作らない）。
    func testPlannedPlaceIsNilWhenNoPlaceWasSaid() async throws {
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .morning, microphoneGranted: false)

        await viewModel.submit(text: "見積書を送るのが嫌だ")
        await viewModel.select(Choice(.reason(.awkward)))
        await viewModel.submit(text: "見積書のファイルを開く")
        await viewModel.submit(text: "14時")
        await viewModel.select(Choice(.declareLater))
        await viewModel.submit(text: "今日、14時に見積書のファイルを開く")

        XCTAssertNil(viewModel.commitment?.plannedPlace)
    }

    // MARK: - 文言の使用履歴（統合判断 D2 / retention R5）

    /// 履歴が端末に残るので、セッションをまたいでも同じ日に同じ文言を繰り返さない。
    func testCopyHistoryPersistsAcrossViewModels() async throws {
        let history = InMemoryCopyHistoryStore()

        let (first, _) = makeViewModel(copyHistory: history)
        await first.start(sessionType: .morning, microphoneGranted: false)
        let firstQuestion = first.spokenLine
        XCTAssertFalse(firstQuestion.isEmpty)
        XCTAssertFalse(history.stored.isEmpty)

        let (second, _) = makeViewModel(copyHistory: history)
        await second.start(sessionType: .morning, microphoneGranted: false)

        XCTAssertNotEqual(second.spokenLine, firstQuestion)
        XCTAssertTrue(DialogueCopy.variants(.morningAvoidanceQuestion).map(\.text).contains(second.spokenLine))
    }

    /// 3 日より古い記録は読み込み時に捨てる。
    func testCopyHistoryDropsRecordsOlderThanThreeDays() throws {
        let uses = [
            CopyPicker.Use(key: .morningAvoidanceQuestion, index: 0, day: 100),
            CopyPicker.Use(key: .morningAvoidanceQuestion, index: 1, day: 104),
        ]

        let kept = UserDefaultsCopyHistoryStore.pruned(uses, currentDay: 105)

        XCTAssertEqual(kept.map(\.day), [104])
    }

    // MARK: - 再生前の配慮（retention R8）

    /// イヤホン未接続かつ音量が大きい日は、TTS も再生も始めずに聞き方を尋ねる。
    func testListenModeIsAskedBeforeAnySoundStarts() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600)))
        let session = MockAudioSession(requiresConfirmation: true)
        let (viewModel, _) = makeViewModel(audioSession: session)

        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        XCTAssertTrue(viewModel.listenModePrompt)
        XCTAssertEqual(viewModel.phase, .playback)
        XCTAssertTrue(synthesizer.spokenLines.isEmpty)
        XCTAssertTrue(player.playedURLs.isEmpty)
        XCTAssertEqual(viewModel.currentStep, .noonPlayback)
    }

    /// 配慮が要らない状況（イヤホン接続・音量が小さい）では尋ねずに鳴らす。
    func testListenModeIsNotAskedWhenConfirmationIsNotRequired() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600)))
        let session = MockAudioSession(requiresConfirmation: false)
        let (viewModel, _) = makeViewModel(audioSession: session)

        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        XCTAssertFalse(viewModel.listenModePrompt)
        XCTAssertEqual(player.playedURLs.count, 1)
        XCTAssertEqual(player.preferReceiverFlags, [false])
        XCTAssertEqual(viewModel.currentStep, .noonStatus)
    }

    /// 「文字で読む」でも体験は成立する。音は一切鳴らさず、宣言テキストを出して N1 へ進む。
    func testReadTextModePlaysNothingAndShowsTheDeclaration() async throws {
        let commitment = makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600))
        await store.seed(commitment)
        let session = MockAudioSession(requiresConfirmation: true)
        let (viewModel, _) = makeViewModel(audioSession: session)
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.chooseListenMode(.readText)

        XCTAssertFalse(viewModel.listenModePrompt)
        XCTAssertTrue(player.playedURLs.isEmpty)
        let intro = try XCTUnwrap(DialogueCopy.variants(.noonIntro).first?.text)
        XCTAssertFalse(synthesizer.spokenLines.contains(intro))
        XCTAssertEqual(viewModel.declarationTextToShow, commitment.declarationTranscript)
        // 会話は止まらない。N1 の「どうだった？」まで進む。
        XCTAssertEqual(viewModel.currentStep, .noonStatus)
        XCTAssertEqual(viewModel.choices.map(\.id), [.status(.done), .status(.partial), .status(.notYet)])
    }

    /// 「耳に当てて聞く」は受話口へ回してから鳴らす。
    func testReceiverModeRoutesToTheReceiverBeforePlaying() async throws {
        await store.seed(makeCommitment(outcome: .pending, plannedAt: reference.addingTimeInterval(-3_600)))
        let session = MockAudioSession(requiresConfirmation: true)
        let (viewModel, _) = makeViewModel(audioSession: session)
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        await viewModel.chooseListenMode(.receiver)

        XCTAssertEqual(player.playedURLs.count, 1)
        XCTAssertEqual(player.preferReceiverFlags, [true])
        XCTAssertTrue(session.appliedRoutes.contains(.receiver))
        XCTAssertEqual(viewModel.currentStep, .noonStatus)
    }

    /// 「声なし」の日は確認も再生もせず、本人の言葉を画面に出す（fix-decisions P2.3）。
    func testVoicelessCommitmentShowsTextAndIsNeverAskedToChoose() async throws {
        let commitment = makeCommitment(
            outcome: .pending,
            plannedAt: reference.addingTimeInterval(-3_600),
            isVoiceless: true
        )
        await store.seed(commitment)
        let session = MockAudioSession(requiresConfirmation: true)
        let (viewModel, _) = makeViewModel(audioSession: session)

        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        XCTAssertFalse(viewModel.listenModePrompt)
        XCTAssertTrue(player.playedURLs.isEmpty)
        XCTAssertEqual(viewModel.declarationTextToShow, commitment.declarationTranscript)
        // 「朝のあなたからです。」だけを読み、本人の言葉は読み上げ直さない。
        let intro = try XCTUnwrap(DialogueCopy.variants(.noonIntro).first?.text)
        XCTAssertTrue(synthesizer.spokenLines.contains(intro))
        XCTAssertFalse(synthesizer.spokenLines.contains(commitment.declarationTranscript))
    }

    // MARK: - 昼に当日の宣言を復元する（統合判断 D9）

    func testNoonRestoresTodaysActionAndPlaceFromTheCommitment() async throws {
        await store.seed(
            makeCommitment(
                outcome: .pending,
                plannedAt: reference.addingTimeInterval(-3_600),
                plannedPlace: "机"
            )
        )
        let (viewModel, _) = makeViewModel()
        await viewModel.start(sessionType: .noon, microphoneGranted: false)

        XCTAssertEqual(viewModel.plannedPlace, "机")

        await viewModel.select(Choice(.status(.notYet)))
        await viewModel.submit(text: "何から書けばいいかわからない")

        // N3 の促しに、本人が朝に言った言葉が戻っている（空の「今は…しなくていい」にならない）。
        XCTAssertTrue(viewModel.spokenLine.contains("見積書を送るのが嫌だ"))

        await viewModel.submit(text: "宛先だけ書く")
        XCTAssertEqual(viewModel.commitment?.microAction.text, "宛先だけ書く")
        XCTAssertEqual(viewModel.commitment?.microAction.shrinkCount, 1)
    }

    // MARK: - 会話の進行は 1 本の直列の流れ（task_031）

    /// 無音検出で M0 から M4 まで進める。どの段階でも、読み上げの完了を解放する前に録音は始まらない。
    func testRecordingNeverStartsBeforeSpeechCompletesThroughMorningFlow() async throws {
        synthesizer.holdsCompletion = true
        let (viewModel, _) = makeViewModel(transcript: [
            "見積書を送るのが嫌だ",
            "気まずいから",
            "見積書のファイルを開く",
            "14時に自宅で",
            "今日、14時に見積書のファイルを開く",
        ])
        var overlaps: [String] = []
        capture.onStart = { [synthesizer] in
            if let synthesizer, synthesizer.unfinishedCount > 0 {
                overlaps.append(String(describing: viewModel.currentStep))
            }
        }

        let opening = Task { await viewModel.start(sessionType: .morning) }
        var stepsWithHeldSpeech: Set<FlowStep> = []
        for _ in 0..<40 where viewModel.completion == nil {
            await settle(until: { self.synthesizer.unfinishedCount > 0 || viewModel.completion != nil })
            guard synthesizer.unfinishedCount > 0 else { break }
            let step = viewModel.currentStep
            if let step { stepsWithHeldSpeech.insert(step) }

            // 読み上げが終わっていないあいだは、どれだけ待っても録音は始まらない。
            let startsBefore = capture.startCount
            await drain()
            XCTAssertEqual(capture.startCount, startsBefore, "読み上げの完了前に録音が始まった: \(String(describing: step))")
            XCTAssertFalse(capture.isCapturing, "読み上げ中に録音している: \(String(describing: step))")

            synthesizer.completeNext()
        }
        await settle(until: { viewModel.completion != nil })
        opening.cancel()

        XCTAssertEqual(overlaps, [])
        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(
            stepsWithHeldSpeech,
            [.morningAvoidance, .morningReason, .morningMicroAction, .morningPlannedTime, .morningDeclaration]
        )
        // M0〜M3 の聞き取り 4 回と、M4 の宣言の録音 1 回。
        XCTAssertEqual(capture.startCount, 5)
    }

    /// 沈黙の見張りが発火した後の催促でも、読み上げの完了前に録音は始まらない。
    func testRecordingWaitsForTheNudgeAfterSilenceWatchFires() async throws {
        synthesizer.holdsCompletion = true
        capture.autoSilenceStarts = 0
        let manual = ManualTimer()
        let (viewModel, _) = makeViewModel(timer: SessionTimer(sleep: { try await manual.sleep($0) }))
        var overlaps = 0
        capture.onStart = { [synthesizer] in
            if let synthesizer, synthesizer.unfinishedCount > 0 { overlaps += 1 }
        }

        let opening = Task { await viewModel.start(sessionType: .morning) }
        await settle(until: { self.synthesizer.unfinishedCount == 1 })
        synthesizer.completeNext()
        await settle(until: { self.capture.isCapturing })
        XCTAssertEqual(capture.startCount, 1)

        // 何も話さないまま 5 秒。沈黙の見張りが発火する。
        let firstSilence = Duration.seconds(FlowMachine.firstSilenceSeconds)
        for _ in 0..<2_000 {
            if await manual.isWaiting(for: firstSilence) { break }
            await Task.yield()
        }
        await manual.fire(firstSilence)
        await settle(until: { self.synthesizer.unfinishedCount == 1 })

        let nudges = Set(DialogueCopy.variants(.silenceNudge).map(\.text))
        XCTAssertTrue(nudges.contains(synthesizer.spokenLines.last ?? ""))
        // 催促を読み終えるまでは、聞き取りは止まったまま。
        await drain()
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertFalse(capture.isCapturing)

        synthesizer.completeNext()
        await settle(until: { self.capture.startCount == 2 })
        XCTAssertEqual(capture.startCount, 2)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(overlaps, 0)
        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)

        opening.cancel()
        await viewModel.interrupt()
    }

    /// 聞き取り中にチップを選んだら、その聞き取りの結果はもう使わない。聞き直しの文言は読まれない。
    func testChoosingAChipWhileListeningDoesNotLeadToARetryPrompt() async throws {
        // M0 だけ声で答える。M1 の聞き取りは開いたままにする。
        capture.autoSilenceStarts = 1
        let (viewModel, _) = makeViewModel(transcript: ["見積書を送るのが嫌だ"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.currentStep == .morningReason && self.capture.startCount == 2 })
        XCTAssertTrue(capture.isCapturing)

        synthesizer.holdsCompletion = true
        let choosing = Task { await viewModel.select(Choice(.reason(.awkward))) }
        await settle(until: { self.synthesizer.unfinishedCount == 1 })
        // 選んだ後で、古い聞き取りの無音検出が届く。
        capture.speakThenFallSilent()
        await drain()
        synthesizer.completeNext()
        await settle(until: { self.capture.startCount == 3 })
        choosing.cancel()

        let retryPrompts = Set(DialogueCopy.variants(.retryPrompt).map(\.text))
        XCTAssertTrue(synthesizer.spokenLines.allSatisfy { !retryPrompts.contains($0) })
        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)
        XCTAssertEqual(capture.startCount, 3)

        await viewModel.interrupt()
    }

    /// 文字起こしの確定を待っているあいだにチップを選んでも、確定した結果は流さない。
    func testChoosingAChipWhileFinalizingDiscardsTheTranscript() async throws {
        capture.autoSilenceStarts = 1
        let (viewModel, transcriber) = makeViewModel(transcript: ["見積書を送るのが嫌だ"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.currentStep == .morningReason && self.capture.startCount == 2 })

        // 無音を検出して確定に入ったところで止める。
        let finalizing = Gate()
        transcriber.finishGate = finalizing
        capture.speakThenFallSilent()
        await settle(until: { finalizing.waitingCount == 1 })

        let choosing = Task { await viewModel.select(Choice(.reason(.awkward))) }
        await drain()
        finalizing.open()
        await settle(until: { self.capture.startCount == 3 })
        // 確定を待っていた側が、門が開いた後に動く分まで待つ。
        await drain()
        choosing.cancel()

        let retryPrompts = Set(DialogueCopy.variants(.retryPrompt).map(\.text))
        XCTAssertTrue(synthesizer.spokenLines.allSatisfy { !retryPrompts.contains($0) })
        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)

        await viewModel.interrupt()
    }

    /// その質問に関係のないチップ（前の質問のものが残っていた場合）を押しても、聞き取りは止まったままにならない。
    func testAnIgnoredChipResumesListening() async throws {
        capture.autoSilenceStarts = 2
        let (viewModel, _) = makeViewModel(transcript: ["見積書を送るのが嫌だ", "気まずいから"])
        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.currentStep == .morningMicroAction && self.capture.startCount == 3 })
        XCTAssertTrue(capture.isCapturing)

        await viewModel.select(Choice(.reason(.awkward)))

        XCTAssertEqual(viewModel.currentStep, .morningMicroAction)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(viewModel.phase, .listening)

        await viewModel.interrupt()
    }

    /// 録音の準備を待っているあいだに会話を閉じたら、録音は始まらない。
    func testClosingWhileThePreparationIsPendingNeverStartsRecording() async throws {
        let preparing = Gate()
        let transcriber = MockTranscriber(script: [])
        transcriber.prepareGate = preparing
        let (viewModel, _) = makeViewModel(transcriber: transcriber)

        let opening = Task { await viewModel.start(sessionType: .morning) }
        await settle(until: { preparing.waitingCount == 1 })
        XCTAssertEqual(capture.startCount, 0)

        let closing = Task { await viewModel.interrupt() }
        await drain()
        preparing.open()
        await settle(until: { viewModel.completion != nil })
        await drain()
        opening.cancel()
        closing.cancel()

        XCTAssertEqual(capture.startCount, 0)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(viewModel.completion, .suspended)
        XCTAssertEqual(viewModel.phase, .done)
    }

    /// 読み上げ中に時間切れになったら、その読み上げは止まり、録音は始まらない。
    func testTimeboxDuringSpeechStopsTheSpeechAndNeverStartsRecording() async throws {
        synthesizer.holdsCompletion = true
        let (viewModel, _) = makeViewModel()

        let opening = Task { await viewModel.start(sessionType: .morning) }
        await settle(until: { self.synthesizer.unfinishedCount == 1 })
        XCTAssertEqual(synthesizer.spokenLines.count, 1)

        let expiring = Task { await viewModel.timeboxElapsed() }
        // 途中だった質問の読み上げが止まり、時間切れの一言だけが残る。
        await settle(until: { self.synthesizer.spokenLines.count == 2 })
        XCTAssertGreaterThanOrEqual(synthesizer.stopCount, 1)
        XCTAssertEqual(synthesizer.unfinishedCount, 1)
        XCTAssertEqual(capture.startCount, 0)

        synthesizer.completeNext()
        await settle(until: { viewModel.completion != nil })
        await drain()
        opening.cancel()
        expiring.cancel()

        XCTAssertEqual(viewModel.completion, .timeboxExceeded)
        XCTAssertEqual(viewModel.phase, .done)
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertFalse(capture.isCapturing)
        // 会話が終わった時点で、読み上げは残っていない。
        XCTAssertEqual(synthesizer.unfinishedCount, 0)
        XCTAssertFalse(synthesizer.isSpeaking)
        // 再生も止めている。
        XCTAssertGreaterThanOrEqual(player.stopCount, 1)
        XCTAssertFalse(player.isPlaying)
    }

    // MARK: - 録音開始の一時的な失敗（task_032）

    /// 権限があるのに録音の開始が 1 回失敗しても、やり直して声のまま進む。マイク拒否の掲示は出ない。
    func testATemporaryCaptureFailureIsRetriedAndListeningStarts() async throws {
        capture.failingAttempts = [1]
        capture.autoSilenceStarts = 0
        let (viewModel, _) = makeViewModel()

        await viewModel.start(sessionType: .morning)
        await settle(until: { self.capture.startCount == 1 })

        XCTAssertEqual(capture.attemptCount, 2)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertFalse(viewModel.acceptsTextInput)
        XCTAssertNil(viewModel.notice)
        XCTAssertFalse(viewModel.isVoiceless)

        await viewModel.interrupt()
    }

    /// 認識器の開始が失敗したときは、始まっていた録音を止めてからやり直す（止めないと二重開始になる）。
    func testATranscriberStartFailureStopsTheCaptureBeforeTheRetry() async throws {
        capture.autoSilenceStarts = 0
        let transcriber = MockTranscriber(script: [])
        transcriber.failingStarts = [1]
        let (viewModel, _) = makeViewModel(transcriber: transcriber)

        await viewModel.start(sessionType: .morning)
        await settle(until: { transcriber.startAttemptCount == 2 })
        await drain()

        XCTAssertEqual(capture.attemptCount, 2)
        XCTAssertEqual(capture.startCount, 2)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertTrue(transcriber.isRunning)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertNil(viewModel.notice)
        XCTAssertFalse(viewModel.isVoiceless)

        await viewModel.interrupt()
    }

    /// 2 回とも失敗したら、その質問だけ文字で受ける。その日を声なしにはせず、次の質問では声を試みる。
    func testTwoFailuresFallBackToTextForThatQuestionOnly() async throws {
        // 1 回目は録音の開始、2 回目は認識器の開始で失敗する。
        capture.failingAttempts = [1]
        capture.autoSilenceStarts = 0
        let transcriber = MockTranscriber(script: [])
        transcriber.failingStarts = [1]
        let (viewModel, _) = makeViewModel(transcriber: transcriber)

        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.acceptsTextInput })

        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)
        XCTAssertTrue(viewModel.acceptsTextInput)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertEqual(viewModel.notice, .captureFailed)
        XCTAssertNotEqual(viewModel.notice, .micDenied)
        XCTAssertFalse(viewModel.isVoiceless)
        // 失敗の後始末。録音は止まっている。
        XCTAssertFalse(capture.isCapturing)
        XCTAssertFalse(transcriber.isRunning)
        XCTAssertEqual(capture.attemptCount, 2)

        // 文字で答えると、次の質問は声の聞き取りに戻る。
        await viewModel.submit(text: "見積書を送るのが嫌だ")
        await settle(until: { self.capture.startCount == 1 })

        XCTAssertEqual(viewModel.currentStep, .morningReason)
        XCTAssertEqual(capture.attemptCount, 3)
        XCTAssertTrue(capture.isCapturing)
        XCTAssertFalse(viewModel.acceptsTextInput)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertNil(viewModel.notice)
        XCTAssertFalse(viewModel.isVoiceless)

        await viewModel.interrupt()
        // 声なしの日として保存されない。
        XCTAssertFalse(viewModel.commitment?.isVoiceless ?? false)
    }

    /// 認識器の開始を待っているあいだに会話を閉じ、その開始が失敗で戻っても、やり直しの録音は始めない。
    func testClosingWhileTheFirstStartIsPendingNeverStartsTheRetry() async throws {
        capture.autoSilenceStarts = 0
        let starting = Gate()
        let transcriber = MockTranscriber(script: [])
        transcriber.startGate = starting
        transcriber.failingStarts = [1]
        let (viewModel, _) = makeViewModel(transcriber: transcriber)

        let opening = Task { await viewModel.start(sessionType: .morning) }
        await settle(until: { starting.waitingCount == 1 })
        XCTAssertEqual(capture.startCount, 1)

        let closing = Task { await viewModel.interrupt() }
        await drain()
        starting.open()
        await settle(until: { viewModel.completion != nil })
        await drain()
        opening.cancel()
        closing.cancel()

        XCTAssertEqual(capture.attemptCount, 1)
        XCTAssertEqual(transcriber.startAttemptCount, 1)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertFalse(transcriber.isRunning)
        XCTAssertNil(viewModel.notice)
    }

    // MARK: - 宣言の録音開始の失敗（task_033。task_032 の残り）

    /// 宣言の録音の開始が 1 回失敗しても、やり直して声の宣言のまま成立する。
    func testATemporaryDeclarationRecordingFailureIsRetried() async throws {
        // 1〜4 回目は M0〜M3 の聞き取り。5 回目が宣言の録音。
        capture.failingAttempts = [5]
        let (viewModel, _) = makeViewModel(transcript: [
            "見積書を送るのが嫌だ",
            "気まずいから",
            "見積書のファイルを開く",
            "14時に自宅で",
            "今日、14時に見積書のファイルを開く",
        ])

        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.completion != nil })

        XCTAssertEqual(viewModel.completion, .completed)
        XCTAssertEqual(capture.attemptCount, 6)
        XCTAssertNil(viewModel.notice)
        let commitment = try XCTUnwrap(viewModel.commitment)
        XCTAssertNotNil(commitment.declarationAudioPath)
        XCTAssertFalse(commitment.isVoiceless)
        let scheduled = await notifications.scheduled
        XCTAssertFalse(scheduled.contains { $0.kind == .declarationReminder })
    }

    /// 2 回とも失敗したら、宣言だけ文字で受ける。マイク拒否の掲示は出さず、声なしにも後回しにも固定しない。
    func testTwoDeclarationRecordingFailuresFallBackToTextForTheDeclarationOnly() async throws {
        capture.failingAttempts = [5, 6]
        let (viewModel, _) = makeViewModel(transcript: [
            "見積書を送るのが嫌だ",
            "気まずいから",
            "見積書のファイルを開く",
            "14時に自宅で",
        ])

        await viewModel.start(sessionType: .morning)
        await settle(until: { viewModel.acceptsTextInput })

        XCTAssertEqual(viewModel.currentStep, .morningDeclaration)
        XCTAssertEqual(viewModel.phase, .listening)
        XCTAssertEqual(viewModel.notice, .captureFailed)
        XCTAssertFalse(viewModel.isVoiceless)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(capture.attemptCount, 6)
        XCTAssertNil(viewModel.completion)

        await viewModel.submit(text: "今日、14時に見積書のファイルを開く")

        XCTAssertEqual(viewModel.completion, .completed)
        let commitment = try XCTUnwrap(viewModel.commitment)
        XCTAssertEqual(commitment.declarationTranscript, "今日、14時に見積書のファイルを開く")
        // 文字で受けた宣言に、前の質問（M3）の録音を付けない。
        XCTAssertNil(commitment.declarationAudioPath)
        let entries = try await store.entries(for: reference)
        XCTAssertEqual(entries.filter { $0.kind == .declaration }.count, 1)
        XCTAssertNil(entries.first { $0.kind == .declaration }?.audioPath)
        // 「後で声で」を選んだわけではないので、宣言の再通知は登録しない。
        let scheduled = await notifications.scheduled
        XCTAssertFalse(scheduled.contains { $0.kind == .declarationReminder })
    }

    // MARK: - 補助

    private func makeCommitment(
        outcome: CommitmentOutcome,
        plannedAt: Date?,
        plannedPlace: String? = nil,
        isVoiceless: Bool = false
    ) -> CommitmentSnapshot {
        CommitmentSnapshot(
            id: UUID(),
            dayKey: DayKey.make(from: reference),
            microAction: MicroAction(text: "見積書のファイルを開く"),
            plannedAt: plannedAt,
            plannedPlace: plannedPlace,
            declarationAudioPath: isVoiceless ? nil : "2026/09/declaration.m4a",
            declarationTranscript: "今日、14時に見積書のファイルを開く",
            isVoiceless: isVoiceless,
            outcome: outcome,
            reason: .awkward,
            progressNote: nil,
            createdAt: reference,
            avoidanceID: UUID(),
            avoidanceTitle: "見積書を送るのが嫌だ",
            domain: .paperwork
        )
    }
}

/// `SessionTimer` に渡した待ち時間を集める。
actor DurationRecorder {
    private(set) var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }
}
