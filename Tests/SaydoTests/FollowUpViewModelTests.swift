import Foundation
import SaydoCore
import XCTest

@testable import Saydo

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
    private var alarms: RecordingRoundAlarms!
    private var settings: AppSettings!
    private var clock: ChaseTestClock!
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
        alarms = RecordingRoundAlarms(calendar: calendar)
        settings = AppSettings(
            defaults: try XCTUnwrap(UserDefaults(suiteName: "FollowUpViewModelTests-\(UUID().uuidString)"))
        )
        // 旧い識別子の後始末（最初の 1 回の全取り消し）は、ここでは見ない。
        settings.legacyAlarmsCleared = true
        settings.useRoundTimesOfTheAnswerTests()
        clock = ChaseTestClock(try date(6, 13, 10))
        player = HoldingPlayer()
        closeCount = 0
    }

    override func tearDown() async throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        settings?.reset()
        settings = nil
        clock = nil
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
    /// 追う回は約束の時刻で決まる（この試験群の時刻は 朝 8:00・昼 13:00・晩 21:00）。
    private func makeCommitment(
        createdAt: Date,
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
                declarationAudioPath: audioPath,
                declarationTranscript: audioPath == nil ? "" : "write the estimate. open the spreadsheet",
                declarationDurationSec: audioPath == nil ? 0 : 6,
                isVoiceless: audioPath == nil,
                createdAt: createdAt
            )
        )
    }

    private func makeChase() -> ChaseCoordinator {
        let repository = repository!
        let calendar = calendar
        let clock = clock!
        return ChaseCoordinator(
            alarms: alarms,
            settings: settings,
            calendar: calendar,
            now: { clock.now },
            commitmentOn: { day in try? await repository.todayCommitment(on: day, calendar: calendar) }
        )
    }

    private func makeViewModel(
        _ commitment: CommitmentSnapshot,
        store: (any FollowUpStore)? = nil,
        chase: ChaseCoordinator? = nil
    ) -> FollowUpViewModel {
        FollowUpViewModel(
            commitment: commitment,
            store: store ?? RepositoryFollowUpStore(repository),
            chase: chase ?? makeChase(),
            player: player,
            audioFileStore: audioFiles,
            calendar: calendar,
            onClose: { [weak self] in self?.closeCount += 1 }
        )
    }

    private var rules: ChaseRules { settings.chaseRules(calendar: calendar) }

    private func dayKey(_ date: Date) -> String {
        DayKey.make(from: date, calendar: calendar)
    }

    /// 再生のタスクが `play` に入るまで待つ。
    private func waitUntilPlaying() async throws {
        for _ in 0..<200 where !player.isPlaying {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(player.isPlaying)
    }

    // MARK: 答えのボタン（§17.9 の 3）

    /// 9 時に約束し、昼の回（13:00〜）が鳴っている 13:10 に答える。
    /// 「少しやった」「まだ」はその回だけを取り消し、晩の回が残る。押した後の 1 行は次の回の時刻を伝える。
    func testPartialAndNotYetCancelOnlyTheCurrentRoundAndKeepTheNextOne() async throws {
        let cases: [(answer: FollowUpAnswer, outcome: CommitmentOutcome)] = [
            (.partial, .partial),
            (.notYet, .notYet),
        ]
        for (offset, entry) in cases.enumerated() {
            // 1 日 1 件なので、ボタンごとに別の日の約束を使う。
            let day = 6 + offset
            let commitment = try await makeCommitment(createdAt: try date(day, 9))
            clock.set(try date(day, 13, 10))
            let alarms = RecordingRoundAlarms(calendar: calendar)
            self.alarms = alarms
            let chase = makeChase()
            await chase.refresh()
            let before = await alarms.rounds(on: clock.now)
            XCTAssertEqual(before, [.noon, .evening])
            await alarms.clearEvents()

            let viewModel = makeViewModel(commitment, chase: chase)
            XCTAssertEqual(viewModel.phase, .asking)
            await viewModel.answer(entry.answer)

            let saved = try await repository.commitment(id: commitment.id)
            XCTAssertEqual(saved?.outcome, entry.outcome, "\(entry.answer)")
            let events = await alarms.events
            XCTAssertEqual(events, [.cancelRound(dayKey: dayKey(clock.now), round: .noon)], "\(entry.answer)")
            let after = await alarms.rounds(on: clock.now)
            XCTAssertEqual(after, [.evening], "\(entry.answer)")
            XCTAssertEqual(settings.answeredRounds(on: commitment.dayKey), [.noon])

            let reply = PromiseCopy.reply(for: entry.answer, nextRoundAt: try date(day, 21), calendar: calendar)
            XCTAssertEqual(viewModel.phase, .answered(reply: reply))
            XCTAssertTrue(reply.contains("次は21時に"), reply)
            XCTAssertNil(viewModel.notice)

            // 翌日の朝の回は、登録されたまま。
            let tomorrow = await alarms.rounds(on: try date(day + 1, 12))
            XCTAssertEqual(tomorrow, [.morning])
        }
    }

    /// 「やった」「今日はやめる」は、その日の後追いをすべて取り消す。次の回は言わない。
    func testDoneAndStopTodayCancelTheWholeDay() async throws {
        let cases: [(answer: FollowUpAnswer, outcome: CommitmentOutcome, reply: String)] = [
            (.done, .done, PromiseCopy.doneReply),
            (.stopToday, .notYet, PromiseCopy.notTodayReply),
        ]
        for (offset, entry) in cases.enumerated() {
            let day = 6 + offset
            let commitment = try await makeCommitment(createdAt: try date(day, 9))
            clock.set(try date(day, 13, 10))
            let alarms = RecordingRoundAlarms(calendar: calendar)
            self.alarms = alarms
            let chase = makeChase()
            await chase.refresh()
            await alarms.clearEvents()

            let viewModel = makeViewModel(commitment, chase: chase)
            await viewModel.answer(entry.answer)

            let saved = try await repository.commitment(id: commitment.id)
            XCTAssertEqual(saved?.outcome, entry.outcome, "\(entry.answer)")
            let events = await alarms.events
            XCTAssertEqual(events, [.cancelDay(dayKey: dayKey(clock.now))], "\(entry.answer)")
            let after = await alarms.rounds(on: clock.now)
            XCTAssertEqual(after, [], "\(entry.answer)")
            XCTAssertEqual(viewModel.phase, .answered(reply: entry.reply))
            XCTAssertEqual(settings.answeredRounds(on: commitment.dayKey), Set(AlarmRound.allCases))

            // 晩の回の時刻を過ぎても、もう答えを待たない。
            let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(day, 21, 30), rules: rules)
            XCTAssertNil(awaiting, "\(entry.answer)")
            // 翌日の朝の回は、登録されたまま。
            let tomorrow = await alarms.rounds(on: try date(day + 1, 12))
            XCTAssertEqual(tomorrow, [.morning])
        }
    }

    /// 起動してからまだ登録し直していない状態で答えても、答えの後の姿で登録される
    /// （残る回と、翌日の朝の回）。
    func testAnsweringBeforeAnyRefreshRegistersTheRemainingRoundsAndTomorrowMorning() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), withVoice: true)
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.notYet)

        let today = await alarms.rounds(on: clock.now)
        XCTAssertEqual(today, [.evening])
        let evening = await alarms.request(.evening, on: clock.now)
        XCTAssertEqual(evening?.voiceRelativePath, commitment.declarationAudioPath)
        let tomorrow = await alarms.request(.morning, on: try date(7, 12))
        XCTAssertEqual(tomorrow?.start, try date(7, 8))
        XCTAssertEqual(tomorrow?.purpose, .prompt)
    }

    /// 最後の回（晩）に「少しやった」「まだ」と答えたら、次の回は無い。1 行は次の回を言わない。
    func testAnsweringTheLastRoundDoesNotMentionANextRound() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        clock.set(try date(6, 21, 10))
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.partial)

        XCTAssertEqual(viewModel.phase, .answered(reply: PromiseCopy.partialReply))
        // 答えないまま過ぎた昼の回も、晩の回と一緒に答えたことになる。
        XCTAssertEqual(settings.answeredRounds(on: commitment.dayKey), [.noon, .evening])
        let today = await alarms.rounds(on: clock.now)
        XCTAssertEqual(today, [])
    }

    /// 昼の回に「まだ」と答えた後、晩の回でまた答えを待ち、答え直せる（結果が書き換わる）。
    func testTheNextRoundAsksAgainAndTheAnswerCanBeChanged() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        await makeViewModel(commitment).answer(.notYet)

        let afternoon = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 14), rules: rules)
        XCTAssertNil(afternoon)
        let evening = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 21, 5), rules: rules)
        XCTAssertEqual(evening?.id, commitment.id)
        XCTAssertEqual(evening?.outcome, .notYet)

        clock.set(try date(6, 21, 5))
        let again = makeViewModel(try XCTUnwrap(evening))
        await again.answer(.done)

        let saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .done)
        XCTAssertEqual(again.phase, .answered(reply: PromiseCopy.doneReply))
    }

    func testTheScreenShowsThePromiseAndTheActionInTheUsersOwnWords() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))

        let viewModel = makeViewModel(commitment)

        XCTAssertEqual(viewModel.promiseText, "write the estimate")
        XCTAssertEqual(viewModel.actionText, "open the spreadsheet")
    }

    func testASecondTapDoesNotSaveOrCancelAgain() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.partial)
        let eventsAfterFirst = await alarms.events
        await viewModel.answer(.stopToday)

        let saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .partial)
        let events = await alarms.events
        XCTAssertEqual(events, eventsAfterFirst)
        XCTAssertEqual(settings.answeredRounds(on: commitment.dayKey), [.noon])
        let reply = PromiseCopy.reply(for: .partial, nextRoundAt: try date(6, 21), calendar: calendar)
        XCTAssertEqual(viewModel.phase, .answered(reply: reply))
    }

    // MARK: 保存の失敗

    func testAFailedSaveDoesNotCancelTheChain() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        let store = FlakyFollowUpStore(failures: 1, then: RepositoryFollowUpStore(repository))
        let viewModel = makeViewModel(commitment, store: store)

        await viewModel.answer(.done)

        var events = await alarms.events
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(settings.answeredRounds(on: commitment.dayKey), [])
        XCTAssertEqual(viewModel.phase, .asking)
        XCTAssertEqual(viewModel.notice, PromiseCopy.followUpSaveFailed)
        var saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .pending)

        // もう一度押せば保存され、そこで初めて取り消される。
        await viewModel.answer(.done)

        events = await alarms.events
        XCTAssertEqual(events.first, .cancelDay(dayKey: dayKey(clock.now)))
        XCTAssertNil(viewModel.notice)
        XCTAssertEqual(viewModel.phase, .answered(reply: PromiseCopy.doneReply))
        saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .done)
    }

    func testARepositoryErrorDoesNotCancelTheChain() async throws {
        // 保存先に無い約束（読んだ後に消された場合）。`Repository` 自身が失敗を返す。
        var commitment = try await makeCommitment(createdAt: try date(6, 9))
        commitment.id = UUID()
        let viewModel = makeViewModel(commitment)

        await viewModel.answer(.notYet)

        let events = await alarms.events
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(viewModel.notice, PromiseCopy.followUpSaveFailed)
        XCTAssertEqual(viewModel.phase, .asking)
    }

    // MARK: 本人の声

    func testTheVoiceButtonPlaysAndStopsTheUsersOwnVoice() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), withVoice: true)
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
        let events = await alarms.events
        XCTAssertTrue(events.isEmpty)
    }

    func testTheVoiceButtonReturnsToPlayWhenTheVoiceEnds() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9), withVoice: true)
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
        let commitment = try await makeCommitment(createdAt: try date(6, 9), withVoice: true)
        let viewModel = makeViewModel(commitment)
        viewModel.toggleVoice()
        try await waitUntilPlaying()

        await viewModel.answer(.done)

        XCTAssertFalse(viewModel.isPlayingVoice)
        XCTAssertEqual(player.stopCount, 1)
    }

    func testThereIsNoVoiceButtonWithoutAVoice() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        let viewModel = makeViewModel(commitment)

        XCTAssertFalse(viewModel.hasVoice)
        viewModel.toggleVoice()

        XCTAssertFalse(viewModel.isPlayingVoice)
        XCTAssertTrue(player.playedURLs.isEmpty)
    }

    // MARK: 閉じる

    func testClosingWithoutAnsweringKeepsTheChain() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        let viewModel = makeViewModel(commitment)

        viewModel.close()

        XCTAssertEqual(closeCount, 1)
        let events = await alarms.events
        XCTAssertTrue(events.isEmpty)
        let saved = try await repository.commitment(id: commitment.id)
        XCTAssertEqual(saved?.outcome, .pending)
    }

    // MARK: 答えを待っている約束（Repository+FollowUp）

    func testAwaitingAnswerOnlyAfterARoundHasStarted() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))

        let before = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 12, 59), rules: rules)
        let after = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 13, 1), rules: rules)

        XCTAssertNil(before)
        XCTAssertEqual(after?.id, commitment.id)
    }

    func testNotAwaitingOnceTheDayIsStopped() async throws {
        let commitment = try await makeCommitment(createdAt: try date(6, 9))
        await makeViewModel(commitment).answer(.stopToday)

        let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 21, 30), rules: rules)

        XCTAssertNil(awaiting)
    }

    /// 晩の回（21:00）を過ぎてからの約束は、その日は追わない（§17.10 の 2）。答える回が無いので、翌日にも出さない。
    func testAPromiseMadeAfterTheLastRoundIsNeverAwaited() async throws {
        _ = try await makeCommitment(createdAt: try date(6, 23, 45))

        let sameNight = try await repository.commitmentAwaitingAnswer(asOf: try date(6, 23, 50), rules: rules)
        let nextMorning = try await repository.commitmentAwaitingAnswer(asOf: try date(7, 0, 20), rules: rules)

        XCTAssertNil(sameNight)
        XCTAssertNil(nextMorning)
    }

    func testYesterdaysUnansweredPromiseIsNotBroughtBack() async throws {
        _ = try await makeCommitment(createdAt: try date(6, 9))

        let awaiting = try await repository.commitmentAwaitingAnswer(asOf: try date(7, 9), rules: rules)

        XCTAssertNil(awaiting)
    }
}
