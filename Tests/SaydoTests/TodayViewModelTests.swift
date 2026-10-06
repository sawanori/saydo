import Foundation
import SaydoCore
import SwiftData
import XCTest

@testable import Saydo

/// `AlarmScheduling` の記録するだけの実装。`outcomes` を先頭から順に返し、尽きたら登録できたことにする。
private actor ScriptedAlarms: AlarmScheduling {
    struct Scheduled: Equatable {
        var start: Date
        var voice: String?
    }

    private var outcomes: [AlarmScheduleOutcome]
    private(set) var scheduled: [Scheduled] = []
    private(set) var cancelledDays: [Date] = []

    init(outcomes: [AlarmScheduleOutcome] = []) {
        self.outcomes = outcomes
    }

    func requestAuthorization() async -> Bool { true }

    func scheduleChain(start: Date, voiceRelativePath: String?) async -> AlarmScheduleOutcome {
        scheduled.append(Scheduled(start: start, voice: voiceRelativePath))
        return outcomes.isEmpty ? .scheduled(count: AlarmPlan.defaultCount) : outcomes.removeFirst()
    }

    func cancelChain(startedOn day: Date) async {
        cancelledDays.append(day)
    }
}

@MainActor
private final class SilentPlayer: Playing {
    private(set) var isPlaying = false
    private(set) var currentURL: URL?

    func play(_ url: URL, preferReceiver: Bool) async throws {}
    func stop() {}
}

/// 今日の画面の段階と「時間を変える」（実装計画 §17.3「今日」、task_056）。
@MainActor
final class TodayViewModelTests: XCTestCase {

    private var repository: Repository!
    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        repository = Repository(modelContainer: try SaydoModelContainer.make(inMemory: true))
    }

    override func tearDown() async throws {
        repository = nil
        try await super.tearDown()
    }

    // MARK: 補助

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))
        )
    }

    private func makeViewModel(now: Date, alarms: ScriptedAlarms) -> TodayViewModel {
        TodayViewModel(
            repository: repository,
            alarms: alarms,
            player: SilentPlayer(),
            audioFiles: nil,
            calendar: calendar,
            now: { now }
        )
    }

    @discardableResult
    private func makeCommitment(
        createdAt: Date,
        plannedAt: Date,
        audioPath: String? = nil
    ) async throws -> CommitmentSnapshot {
        try await repository.createCommitment(
            CommitmentDraft(
                avoidanceTitle: "invoice",
                microAction: MicroAction(text: "open"),
                plannedAt: plannedAt,
                declarationAudioPath: audioPath,
                declarationTranscript: "invoice。open",
                createdAt: createdAt
            )
        )
    }

    // MARK: 段階

    func testStageFollowsThePromise() async throws {
        let alarms = ScriptedAlarms()

        let empty = makeViewModel(now: try date(6, 9), alarms: alarms)
        XCTAssertEqual(empty.stage, .loading)
        await empty.load()
        XCTAssertEqual(empty.stage, .noPromise)

        let saved = try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 10))

        let before = makeViewModel(now: try date(6, 9, 30), alarms: alarms)
        await before.load()
        XCTAssertEqual(before.stage, .beforeChase)
        XCTAssertEqual(before.commitment?.id, saved.id)

        let chasing = makeViewModel(now: try date(6, 10, 30), alarms: alarms)
        await chasing.load()
        XCTAssertEqual(chasing.stage, .awaitingAnswer)

        try await repository.updateOutcome(commitmentID: saved.id, outcome: .done)
        let answered = makeViewModel(now: try date(6, 11), alarms: alarms)
        await answered.load()
        XCTAssertEqual(answered.stage, .answered)
    }

    // MARK: 時間を変える

    /// チップで選び直すと、新しい時刻で連鎖を登録し直し、`plannedAt` を更新する。
    func testChangingTheTimeReschedulesTheChainAndUpdatesPlannedAt() async throws {
        let now = try date(6, 9, 30)
        let saved = try await makeCommitment(
            createdAt: try date(6, 9),
            plannedAt: try date(6, 10),
            audioPath: "2026/10/voice.m4a"
        )
        let alarms = ScriptedAlarms()
        let viewModel = makeViewModel(now: now, alarms: alarms)
        await viewModel.load()

        viewModel.beginChoosingTime()
        XCTAssertTrue(viewModel.isChoosingTime)
        XCTAssertTrue(viewModel.timeOptions.contains { $0.chip == .inThirtyMinutes })

        await viewModel.changeTime(to: .inThirtyMinutes)

        let expected = now.addingTimeInterval(PromiseTime.thirtyMinutes)
        let scheduled = await alarms.scheduled
        XCTAssertEqual(scheduled, [ScriptedAlarms.Scheduled(start: expected, voice: "2026/10/voice.m4a")])
        // 同じ日の中での変更は、登録の中で取り消される。別に取り消しは頼まない。
        let cancelled = await alarms.cancelledDays
        XCTAssertTrue(cancelled.isEmpty)
        XCTAssertEqual(viewModel.commitment?.plannedAt, expected)
        XCTAssertFalse(viewModel.isChoosingTime)
        XCTAssertNil(viewModel.notice)
        let stored = try await repository.commitment(id: saved.id)
        XCTAssertEqual(stored?.plannedAt, expected)
    }

    /// 登録できなかったときは時刻を変えず、元の時刻で登録し直して 1 行で伝える。
    func testFailedRescheduleKeepsTheOldTime() async throws {
        let oldStart = try date(6, 10)
        let saved = try await makeCommitment(createdAt: try date(6, 9), plannedAt: oldStart)
        let alarms = ScriptedAlarms(outcomes: [.failed])
        let viewModel = makeViewModel(now: try date(6, 9, 30), alarms: alarms)
        await viewModel.load()
        viewModel.beginChoosingTime()

        await viewModel.changeTime(to: .inThirtyMinutes)

        let scheduled = await alarms.scheduled
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(scheduled.last?.start, oldStart)
        XCTAssertEqual(viewModel.commitment?.plannedAt, oldStart)
        XCTAssertEqual(viewModel.notice, PromiseCopy.changeTimeUnavailable)
        let stored = try await repository.commitment(id: saved.id)
        XCTAssertEqual(stored?.plannedAt, oldStart)
    }

    /// アラームの権限が無いときも時刻は変えない。
    func testRescheduleWithoutAuthorizationKeepsTheOldTime() async throws {
        let oldStart = try date(6, 10)
        try await makeCommitment(createdAt: try date(6, 9), plannedAt: oldStart)
        let alarms = ScriptedAlarms(outcomes: [.notAuthorized])
        let viewModel = makeViewModel(now: try date(6, 9, 30), alarms: alarms)
        await viewModel.load()
        viewModel.beginChoosingTime()

        await viewModel.changeTime(to: .inThirtyMinutes)

        XCTAssertEqual(viewModel.commitment?.plannedAt, oldStart)
        XCTAssertEqual(viewModel.notice, PromiseCopy.completionNotAuthorized)
        let scheduled = await alarms.scheduled
        XCTAssertEqual(scheduled.count, 1)
    }

    /// 連鎖の識別子は開始日で決まる。日をまたいで変えたときは、元の日の連鎖を取り消す。
    func testChangingAcrossMidnightCancelsTheOldDay() async throws {
        let oldStart = try date(7, 0, 15)
        try await makeCommitment(createdAt: try date(6, 23), plannedAt: oldStart)
        let now = try date(6, 23, 10)
        let alarms = ScriptedAlarms()
        let viewModel = makeViewModel(now: now, alarms: alarms)
        await viewModel.load()
        XCTAssertEqual(viewModel.stage, .beforeChase)
        viewModel.beginChoosingTime()

        await viewModel.changeTime(to: .inThirtyMinutes)

        let cancelled = await alarms.cancelledDays
        XCTAssertEqual(cancelled, [oldStart])
        XCTAssertEqual(viewModel.commitment?.plannedAt, now.addingTimeInterval(PromiseTime.thirtyMinutes))
    }

    /// 追い始めた後は、時刻を変えられない。
    func testTimeCannotBeChangedAfterTheChaseStarted() async throws {
        try await makeCommitment(createdAt: try date(6, 9), plannedAt: try date(6, 10))
        let alarms = ScriptedAlarms()
        let viewModel = makeViewModel(now: try date(6, 10, 30), alarms: alarms)
        await viewModel.load()

        viewModel.beginChoosingTime()
        await viewModel.changeTime(to: .inOneHour)

        XCTAssertFalse(viewModel.isChoosingTime)
        let scheduled = await alarms.scheduled
        XCTAssertTrue(scheduled.isEmpty)
    }
}
