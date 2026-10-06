import Foundation
import SaydoCore
import XCTest

@testable import Saydo

/// `AlarmScheduling` の記録するだけの実装。
private actor RecordingAlarmScheduling: AlarmScheduling {
    private(set) var cancelledDays: [Date] = []
    private(set) var scheduledStarts: [Date] = []

    func requestAuthorization() async -> Bool { true }

    func scheduleChain(start: Date, voiceRelativePath: String?) async -> AlarmScheduleOutcome {
        scheduledStarts.append(start)
        return .scheduled(count: AlarmPlan.defaultCount)
    }

    func cancelChain(startedOn day: Date) async {
        cancelledDays.append(day)
    }
}

/// 保存に失敗する `FollowUpStore`。`failuresLeft` 回だけ失敗し、その後は `inner` に書く。
private actor FlakyFollowUpStore: FollowUpStore {
    struct SaveFailed: Error {}

    private var failuresLeft: Int
    private let inner: (any FollowUpStore)?
    private(set) var attempts = 0

    init(failures: Int, then inner: (any FollowUpStore)? = nil) {
        self.failuresLeft = failures
        self.inner = inner
    }

    func saveOutcome(commitmentID: UUID, outcome: CommitmentOutcome) async throws {
        attempts += 1
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw SaveFailed()
        }
        try await inner?.saveOutcome(commitmentID: commitmentID, outcome: outcome)
    }
}

/// `Playing` の記録するだけの実装。再生は `stop()` されるか `finish()` されるまで終わらない。
@MainActor
private final class HoldingPlayer: Playing {
    private(set) var playedURLs: [URL] = []
    private(set) var stopCount = 0
    private(set) var isPlaying = false
    private(set) var currentURL: URL?
    private var waiting: [AsyncStream<Void>.Continuation] = []

    func play(_ url: URL, preferReceiver: Bool) async throws {
        playedURLs.append(url)
        currentURL = url
        isPlaying = true
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        waiting.append(continuation)
        for await _ in completion {}
    }

    func stop() {
        stopCount += 1
        finish()
    }

    /// 鳴り終えたことにする。
    func finish() {
        isPlaying = false
        for continuation in waiting {
            continuation.finish()
        }
        waiting = []
    }
}

@MainActor
final class FollowUpViewModelTests: XCTestCase {
    private var root: URL!
    private var audioFiles: AudioFileStore!
    private var repository: Repository!
    private var alarms: RecordingAlarmScheduling!
    private var player: HoldingPlayer!
    private var closeCount = 0

    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoFollowUpTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        audioFiles = AudioFileStore(rootDirectory: root)
        repository = Repository(modelContainer: try SaydoModelContainer.make(inMemory: true))
        await repository.configure(audioFileStore: audioFiles)
        alarms = RecordingAlarmScheduling()
        player = HoldingPlayer()
        closeCount = 0
    }

    override func tearDown() async throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        repository = nil
        audioFiles = nil
        alarms = nil
        player = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: 補助

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    /// 約束を 1 件作る。`withVoice` のときは声のファイルも置く。
    private func makeCommitment(
        createdAt: Date,
        plannedAt: Date?,
        withVoice: Bool = false
    ) async throws -> CommitmentSnapshot {
        var audioPath: String?
        if withVoice {
            let allocation = try audioFiles.allocate(recordedAt: createdAt)
            try Data([0x00, 0x01]).write(to: allocation.url)
            audioPath = allocation.relativePath
        }
        return try await repository.createCommitment(
            CommitmentDraft(
                avoidanceTitle: "write the estimate",
                microAction: MicroAction(text: "open the spreadsheet", estimatedMinutes: 5),
                plannedAt: plannedAt,
                declarationAudioPath: audioPath,
                declarationTranscript: audioPath == nil ? "" : "write the estimate. open the spreadsheet",
                declarationDurationSec: audioPath == nil ? 0 : 6,
                isVoiceless: audioPath == nil,
                createdAt: createdAt
            )
        )
    }

    private func makeViewModel(
        _ commitment: CommitmentSnapshot,
        store: (any FollowUpStore)? = nil
    ) -> FollowUpViewModel {
        FollowUpViewModel(
            commitment: commitment,
            store: store ?? RepositoryFollowUpStore(repository),
            alarms: alarms,
            player: player,
            audioFileStore: audioFiles,
            onClose: { [weak self] in self?.closeCount += 1 }
        )
    }

    /// 再生のタスクが `play` に入るまで待つ。
    private func waitUntilPlaying() async throws {
        for _ in 0..<200 where !player.isPlaying {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(player.isPlaying)
    }

    // MARK: 3 つのボタン

    func testEveryButtonSavesTheOutcomeAndCancelsTheChainOnce() async throws {
        let cases: [(outcome: CommitmentOutcome, reply: String)] = [
            (.done, PromiseCopy.doneReply),
            (.partial, PromiseCopy.partialReply),
            (.notYet, PromiseCopy.notTodayReply),
        ]
        for (offset, entry) in cases.enumerated() {
            // 1 日 1 件なので、ボタンごとに別の日の約束を使う。
            let plannedAt = try date(6 + offset, 16)
            let commitment = try await makeCommitment(createdAt: try date(6 + offset, 9), plannedAt: plannedAt)
            let alarms = RecordingAlarmScheduling()
            self.alarms = alarms
            let viewModel = makeViewModel(commitment)
            XCTAssertEqual(viewModel.phase, .asking)

            await viewModel.answer(entry.outcome)

            let saved = try await repository.commitment(id: commitment.id)
            XCTAssertEqual(saved?.outcome, entry.outcome, "\(entry.outcome)")
            let cancelled = await alarms.cancelledDays
            XCTAssertEqual(cancelled, [plannedAt], "\(entry.outcome)")
            XCTAssertEqual(viewModel.phase, .answered(reply: entry.reply))
            XCTAssertNil(viewModel.notice)
        }
    }

    func testTheScreenShowsThePromiseAndTheActionInTheUsersOwnWords() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))

        let viewModel = makeViewModel(commitment)

        XCTAssertEqual(viewModel.promiseText, "write the estimate")
        XCTAssertEqual(viewModel.actionText, "open the spreadsheet")
    }

    func testASecondTapDoesNotSaveOrCancelAgain() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.partial)
        await viewModel.answer(.notYet)

        let saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .partial)
        let cancelled = await alarms.cancelledDays
        XCTAssertEqual(cancelled.count, 1)
        XCTAssertEqual(viewModel.phase, .answered(reply: PromiseCopy.partialReply))
    }

    func testPendingIsNotAnAnswer() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.pending)

        XCTAssertEqual(viewModel.phase, .asking)
        let cancelled = await alarms.cancelledDays
        XCTAssertTrue(cancelled.isEmpty)
    }

    func testTheChainIsCancelledByItsStartDayEvenWhenItStartsTheNextDay() async throws {
        // 23:30 に「1時間後」で約束した日。追い始めるのは翌日の 0:30。
        let plannedAt = try date(7, 0, 30)
        let commitment = try await makeCommitment(createdAt: try date(6, 23, 30), plannedAt: plannedAt)
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.done)

        let cancelled = await alarms.cancelledDays
        XCTAssertEqual(cancelled, [plannedAt])
    }

    // MARK: 保存の失敗

    func testAFailedSaveDoesNotCancelTheChain() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        let store = FlakyFollowUpStore(failures: 1, then: RepositoryFollowUpStore(repository))
        let viewModel = makeViewModel(commitment, store: store)

        await viewModel.answer(.done)

        var cancelled = await alarms.cancelledDays
        XCTAssertTrue(cancelled.isEmpty)
        XCTAssertEqual(viewModel.phase, .asking)
        XCTAssertEqual(viewModel.notice, PromiseCopy.followUpSaveFailed)
        var saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .pending)

        // もう一度押せば保存され、そこで初めて取り消される。
        await viewModel.answer(.done)

        cancelled = await alarms.cancelledDays
        XCTAssertEqual(cancelled.count, 1)
        XCTAssertNil(viewModel.notice)
        XCTAssertEqual(viewModel.phase, .answered(reply: PromiseCopy.doneReply))
        saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .done)
    }

    func testARepositoryErrorDoesNotCancelTheChain() async throws {
        // 保存先に無い約束（読んだ後に消された場合）。`Repository` 自身が失敗を返す。
        var commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        commitment.id = UUID()
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.notYet)

        let cancelled = await alarms.cancelledDays
        XCTAssertTrue(cancelled.isEmpty)
        XCTAssertEqual(viewModel.notice, PromiseCopy.followUpSaveFailed)
        XCTAssertEqual(viewModel.phase, .asking)
    }

    // MARK: 本人の声

    func testTheVoiceButtonPlaysAndStopsTheUsersOwnVoice() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16), withVoice: true)
        let viewModel = makeViewModel(commitment)
        let path = try XCTUnwrap(commitment.declarationAudioPath)
        XCTAssertTrue(viewModel.hasVoice)
        XCTAssertFalse(viewModel.isPlayingVoice)

        viewModel.toggleVoice()
        XCTAssertTrue(viewModel.isPlayingVoice)
        try await waitUntilPlaying()
        XCTAssertEqual(player.playedURLs, [audioFiles.url(forRelativePath: path)])

        viewModel.toggleVoice()
        XCTAssertFalse(viewModel.isPlayingVoice)
        XCTAssertEqual(player.stopCount, 1)

        // 声を聞いただけでは、アラームは取り消さない。
        let cancelled = await alarms.cancelledDays
        XCTAssertTrue(cancelled.isEmpty)
    }

    func testTheVoiceButtonReturnsToPlayWhenTheVoiceEnds() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16), withVoice: true)
        let viewModel = makeViewModel(commitment)

        viewModel.toggleVoice()
        try await waitUntilPlaying()
        player.finish()
        for _ in 0..<200 where viewModel.isPlayingVoice {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertFalse(viewModel.isPlayingVoice)
        XCTAssertEqual(player.stopCount, 0)
    }

    func testAnsweringStopsTheVoice() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16), withVoice: true)
        let viewModel = makeViewModel(commitment)
        viewModel.toggleVoice()
        try await waitUntilPlaying()

        await viewModel.answer(.done)

        XCTAssertFalse(viewModel.isPlayingVoice)
        XCTAssertEqual(player.stopCount, 1)
    }

    func testThereIsNoVoiceButtonWithoutAVoice() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        let viewModel = makeViewModel(commitment)

        XCTAssertFalse(viewModel.hasVoice)
        viewModel.toggleVoice()

        XCTAssertFalse(viewModel.isPlayingVoice)
        XCTAssertTrue(player.playedURLs.isEmpty)
    }

    // MARK: 閉じる

    func testClosingWithoutAnsweringKeepsTheChain() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        let viewModel = makeViewModel(commitment)

        viewModel.close()

        XCTAssertEqual(closeCount, 1)
        let cancelled = await alarms.cancelledDays
        XCTAssertTrue(cancelled.isEmpty)
        let saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .pending)
    }

    // MARK: 答えがまだの約束（Repository+FollowUp）

    func testAwaitingAnswerOnlyAfterTheChainHasStarted() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))

        let before = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 15, 59), calendar: calendar)
        let after = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 16, 1), calendar: calendar)

        XCTAssertNil(before)
        XCTAssertEqual(after?.id, commitment.id)
    }

    func testNotAwaitingOnceAnswered() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))
        await makeViewModel(commitment).answer(.notYet)

        let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 17), calendar: calendar)

        XCTAssertNil(awaiting)
    }

    func testAwaitingAnswerFindsAPromiseMadeLateTheNightBefore() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 23, 30), plannedAt: try date(7, 0, 30))

        let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(7, 0, 40), calendar: calendar)

        XCTAssertEqual(awaiting?.id, commitment.id)
    }

    func testYesterdaysUnansweredPromiseIsNotBroughtBack() async throws {
        _ = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 16))

        let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(7, 9), calendar: calendar)

        XCTAssertNil(awaiting)
    }

    func testAPromiseWithoutAStartTimeIsNotFollowedUp() async throws {
        _ = try await makeCommitment(createdAt: try date(6, 9), plannedAt: nil)

        let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 20), calendar: calendar)

        XCTAssertNil(awaiting)
    }
}
