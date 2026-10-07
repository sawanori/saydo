import Foundation
import SaydoCore
import SwiftData
import XCTest

@testable import Saydo

@MainActor
private final class SilentPlayer: Playing {
    private(set) var isPlaying = false
    private(set) var currentURL: URL?

    func play(_ url: URL, preferReceiver: Bool) async throws {}
    func stop() {}
}

/// 今日の画面の段階と、これから追う回の時刻（実装計画 §17.3「今日」/ §17.9、task_058）。
/// 回の時刻は 朝 8:00・昼 13:00・晩 21:00 にそろえてある（`useRoundTimesOfTheAnswerTests`）。
@MainActor
final class TodayViewModelTests: XCTestCase {

    private var repository: Repository!
    private var settings: AppSettings!
    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        repository = Repository(modelContainer: try SaydoModelContainer.make(inMemory: true))
        settings = AppSettings(
            defaults: try XCTUnwrap(UserDefaults(suiteName: "TodayViewModelTests-\(UUID().uuidString)"))
        )
        settings.useRoundTimesOfTheAnswerTests()
    }

    override func tearDown() async throws {
        settings.reset()
        settings = nil
        repository = nil
        try await super.tearDown()
    }

    // MARK: 補助

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))
        )
    }

    private func makeViewModel(now: Date) -> TodayViewModel {
        let repository = repository!
        let calendar = calendar
        let chase = ChaseCoordinator(
            alarms: RecordingRoundAlarms(calendar: calendar),
            settings: settings,
            calendar: calendar,
            now: { now },
            commitmentOn: { day in try? await repository.todayCommitment(on: day, calendar: calendar) }
        )
        return TodayViewModel(
            repository: repository,
            chase: chase,
            player: SilentPlayer(),
            audioFiles: nil,
            calendar: calendar,
            now: { now }
        )
    }

    @discardableResult
    private func makeCommitment(createdAt: Date) async throws -> CommitmentSnapshot {
        try await repository.createCommitment(
            CommitmentDraft(
                avoidanceTitle: "invoice",
                microAction: MicroAction(text: "open"),
                declarationTranscript: "invoice。open",
                createdAt: createdAt
            )
        )
    }

    // MARK: 段階

    func testStageFollowsThePromise() async throws {
        let empty = makeViewModel(now: try date(6, 9))
        XCTAssertEqual(empty.stage, .loading)
        await empty.load()
        XCTAssertEqual(empty.stage, .noPromise)
        XCTAssertNil(empty.nextRoundAt)

        let saved = try await makeCommitment(createdAt: try date(6, 9))

        // 9 時の約束。これから追うのは昼の回（13:00）。
        let before = makeViewModel(now: try date(6, 9, 30))
        await before.load()
        XCTAssertEqual(before.stage, .beforeChase)
        XCTAssertEqual(before.commitment?.id, saved.id)
        XCTAssertEqual(before.nextRoundAt, try date(6, 13))
        XCTAssertNil(before.chasingSince)

        let chasing = makeViewModel(now: try date(6, 13, 30))
        await chasing.load()
        XCTAssertEqual(chasing.stage, .awaitingAnswer)
        XCTAssertEqual(chasing.chasingSince, try date(6, 13))

        try await repository.updateOutcome(commitmentID: saved.id, outcome: .done)
        let answered = makeViewModel(now: try date(6, 14))
        await answered.load()
        XCTAssertEqual(answered.stage, .answered)
        XCTAssertNil(answered.nextRoundAt)
    }

    /// 昼の回に「少しやった」と答えた日は、結果を残したまま、次に追う回（晩）の時刻を見せる。
    func testAfterAPartialAnswerTheNextRoundIsShown() async throws {
        let saved = try await makeCommitment(createdAt: try date(6, 9))
        try await repository.updateOutcome(commitmentID: saved.id, outcome: .partial)
        settings.markRoundsAnswered([.noon], on: saved.dayKey)

        let afternoon = makeViewModel(now: try date(6, 14))
        await afternoon.load()
        XCTAssertEqual(afternoon.stage, .beforeChase)
        XCTAssertEqual(afternoon.commitment?.outcome, .partial)
        XCTAssertEqual(afternoon.nextRoundAt, try date(6, 21))

        // 晩の回の時刻を過ぎたら、また答えを待つ。
        let evening = makeViewModel(now: try date(6, 21, 10))
        await evening.load()
        XCTAssertEqual(evening.stage, .awaitingAnswer)

        // 晩の回にも答えたら、その日は終わり。
        settings.markRoundsAnswered([.evening], on: saved.dayKey)
        let night = makeViewModel(now: try date(6, 21, 20))
        await night.load()
        XCTAssertEqual(night.stage, .answered)
    }

    /// 「今日はやめる」と答えた日（全部の回を答えたことにする）は、これから追う回を見せない。
    func testAStoppedDayShowsNoNextRound() async throws {
        let saved = try await makeCommitment(createdAt: try date(6, 9))
        try await repository.updateOutcome(commitmentID: saved.id, outcome: .notYet)
        settings.markRoundsAnswered(Set(AlarmRound.allCases), on: saved.dayKey)

        let viewModel = makeViewModel(now: try date(6, 14))
        await viewModel.load()

        XCTAssertEqual(viewModel.stage, .answered)
        XCTAssertNil(viewModel.nextRoundAt)
    }
}
