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

@MainActor
final class MockSynthesizer: Synthesizing {
    private(set) var spokenLines: [String] = []
    private(set) var stopCount = 0
    var isSpeaking = false
    var hasHighQualityJapaneseVoice = true
    var voiceQuality: SynthesisVoiceQuality = .enhanced

    func speak(_ text: String, preferReceiver: Bool) async {
        spokenLines.append(text)
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
final class MockPlayer: Playing {
    private(set) var playedURLs: [URL] = []
    var isPlaying = false
    var currentURL: URL?

    func play(_ url: URL, preferReceiver: Bool) async throws {
        playedURLs.append(url)
        currentURL = url
    }

    func stop() {
        isPlaying = false
    }
}

/// 「話し始めて、無音で終わる」1 回分の RMS 列を流すだけの録音。
/// 実際の `AVAudioEngine` には触らない。
@MainActor
final class MockVoiceCapture: VoiceCapturing {
    var isCapturing = false
    var recordingURL: URL?
    var limit: VoiceCaptureLimit = .utterance

    private(set) var startCount = 0

    func start(writingTo url: URL, analyzerFormat: AVAudioFormat?) throws -> VoiceCaptureSession {
        startCount += 1
        isCapturing = true
        recordingURL = url

        let (events, continuation) = AsyncStream<VoiceCaptureEvent>.makeStream()
        // 発話 1 秒 → 無音 2.5 秒。`SilenceDetector` の 1.5 秒（宣言は 2.0 秒）を必ず越える。
        for _ in 0..<10 {
            continuation.yield(.level(rms: 0.4, duration: 0.1))
        }
        continuation.yield(.level(rms: 0.0, duration: 2.5))
        continuation.finish()

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

    func stop() {
        isCapturing = false
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

    func prepare() async throws -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    }

    func start(inputSequence: AsyncStream<AnalyzerInput>) async throws {
        isRunning = true
    }

    func finish() async -> String {
        isRunning = false
        finalText = script.isEmpty ? "" : script.removeFirst()
        return finalText
    }

    func cancel() {
        isRunning = false
    }

    func reset() {
        volatileText = ""
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

    /// 沈黙 5 秒で催促を 1 回だけ挟み、さらに 10 秒でその質問をスキップする（実装計画 §7.2）。
    func testSilenceNudgesOnceThenSkipsTheQuestion() async throws {
        let recorder = DurationRecorder()
        let timer = SessionTimer(sleep: { duration in
            await recorder.record(duration)
            // 待ち時間そのものは進めない。時間経過はテストが直接与える。
            throw CancellationError()
        })
        let (viewModel, _) = makeViewModel(timer: timer)

        await viewModel.start(sessionType: .morning, microphoneGranted: false)
        await drain()

        // タイムボックス（朝 3 分）と M0 の沈黙（5 秒）の 2 本が張られる。
        var durations = await recorder.durations
        XCTAssertTrue(durations.contains(.seconds(180)))
        XCTAssertTrue(durations.contains(.seconds(FlowMachine.firstSilenceSeconds)))

        // 5 秒沈黙 → 催促を 1 回だけ挟み、次は 10 秒待つ。
        let linesBefore = synthesizer.spokenLines.count
        await viewModel.silenceElapsed()
        await drain()
        durations = await recorder.durations
        XCTAssertTrue(durations.contains(.seconds(FlowMachine.secondSilenceSeconds)))
        XCTAssertEqual(synthesizer.spokenLines.count, linesBefore + 1)
        XCTAssertEqual(viewModel.currentStep, .morningAvoidance)
        XCTAssertNil(viewModel.completion)

        // さらに 10 秒沈黙 → この質問は飛ばして次のステップへ進む。
        await viewModel.silenceElapsed()
        XCTAssertEqual(viewModel.currentStep, .morningReason)
        XCTAssertNil(viewModel.completion)
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

    // MARK: - 補助

    private func makeCommitment(outcome: CommitmentOutcome, plannedAt: Date?) -> CommitmentSnapshot {
        CommitmentSnapshot(
            id: UUID(),
            dayKey: DayKey.make(from: reference),
            microAction: MicroAction(text: "見積書のファイルを開く"),
            plannedAt: plannedAt,
            declarationAudioPath: "2026/09/declaration.m4a",
            declarationTranscript: "今日、14時に見積書のファイルを開く",
            isVoiceless: false,
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
