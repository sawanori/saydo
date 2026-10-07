import Foundation
import SaydoCore
import XCTest

@testable import Saydo

/// 朝・昼・晩の 3 回で追う規則と、試験用の短縮（実装計画 §17.9、task_058）。
@MainActor
final class ChaseRulesTests: XCTestCase {

    private var defaults: UserDefaults!
    private var settings: AppSettings!
    private let calendar = Calendar.current

    override func setUp() async throws {
        try await super.setUp()
        defaults = try XCTUnwrap(UserDefaults(suiteName: "ChaseRulesTests-\(UUID().uuidString)"))
        settings = AppSettings(defaults: defaults)
    }

    override func tearDown() async throws {
        settings.reset()
        DebugRounds.clear(defaults: defaults)
        settings = nil
        defaults = nil
        try await super.tearDown()
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, second: Int = 0) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second)
            )
        )
    }

    private func commitment(createdAt: Date, outcome: CommitmentOutcome = .pending) -> CommitmentSnapshot {
        CommitmentSnapshot(
            id: UUID(),
            dayKey: DayKey.make(from: createdAt, calendar: calendar),
            microAction: MicroAction(text: "open"),
            plannedAt: nil,
            plannedPlace: nil,
            declarationAudioPath: "2026/10/voice.m4a",
            declarationTranscript: "invoice。open",
            isVoiceless: false,
            outcome: outcome,
            reason: nil,
            progressNote: nil,
            createdAt: createdAt,
            avoidanceID: nil,
            avoidanceTitle: "invoice",
            domain: .other
        )
    }

    // MARK: 設定の時刻

    func testRoundTimesComeFromTheSettings() throws {
        var rules = settings.chaseRules(calendar: calendar)
        var times = rules.times(on: try date(6, 15))
        XCTAssertEqual(times.morning, try date(6, 10), "既定は 10:00・14:00・19:00")
        XCTAssertEqual(times.noon, try date(6, 14))
        XCTAssertEqual(times.evening, try date(6, 19))
        XCTAssertEqual(rules.interval(on: try date(6, 15)), 180)

        settings.noonTime = TimeOfDay(hour: 12, minute: 30)
        rules = settings.chaseRules(calendar: calendar)
        times = rules.times(on: try date(6, 15))
        XCTAssertEqual(times.noon, try date(6, 12, 30))
    }

    func testPlanForADayWithAPromiseKeepsOnlyTheRoundsNotYetAnswered() throws {
        let promise = commitment(createdAt: try date(6, 7))
        settings.markRoundsAnswered([.morning], on: promise.dayKey)
        let rules = settings.chaseRules(calendar: calendar)

        let plan = rules.plan(for: try date(6, 12), commitment: promise)

        XCTAssertEqual(plan.map(\.round), [.noon, .evening])
        XCTAssertTrue(plan.allSatisfy { $0.purpose == .chase && $0.voiceRelativePath == "2026/10/voice.m4a" })
        // アラームの題は「最初にやること」の文字（実装計画 §17.10）。
        XCTAssertTrue(plan.allSatisfy { $0.title == "open" })
        XCTAssertEqual(rules.plan(for: try date(6, 12), commitment: commitment(createdAt: try date(6, 7), outcome: .done)), [])
    }

    func testPlanForADayWithoutAPromiseIsTheMorningPromptUnlessStopped() throws {
        var rules = settings.chaseRules(calendar: calendar)
        XCTAssertEqual(rules.plan(for: try date(6, 12), commitment: nil), [
            AlarmRoundRequest(round: .morning, start: try date(6, 10), voiceRelativePath: nil, purpose: .prompt),
        ])
        XCTAssertFalse(rules.isMorningPromptDue(asOf: try date(6, 9, 59)))
        XCTAssertTrue(rules.isMorningPromptDue(asOf: try date(6, 10)))
        XCTAssertTrue(rules.canStopMorningPrompt(asOf: try date(6, 9)))
        XCTAssertFalse(rules.canStopMorningPrompt(asOf: try date(6, 12)), "朝の回（2 時間）が鳴り終えた後は出さない")

        settings.morningPromptStoppedDayKey = DayKey.make(from: try date(6, 9), calendar: calendar)
        rules = settings.chaseRules(calendar: calendar)
        XCTAssertEqual(rules.plan(for: try date(6, 12), commitment: nil), [])
        XCTAssertFalse(rules.isMorningPromptDue(asOf: try date(6, 11)))
        // 翌日の朝の回には効かない。
        XCTAssertEqual(rules.plan(for: try date(7, 12), commitment: nil).map(\.round), [.morning])
    }

    func testAnsweredRoundsAreKeptPerDayAndOldDaysAreDropped() throws {
        settings.markRoundsAnswered([.noon], on: "2026-10-03")
        settings.markRoundsAnswered([.noon], on: "2026-10-04")
        settings.markRoundsAnswered([.evening], on: "2026-10-05")
        settings.markRoundsAnswered([.noon], on: "2026-10-06")
        settings.markRoundsAnswered([.evening], on: "2026-10-06")

        XCTAssertEqual(settings.answeredRounds(on: "2026-10-06"), [.noon, .evening])
        XCTAssertEqual(settings.answeredRounds(on: "2026-10-05"), [.evening])
        XCTAssertEqual(settings.answeredRounds(on: "2026-10-03"), [], "古い日の記録は捨てる")

        settings.clearAnsweredRounds(on: "2026-10-06")
        XCTAssertEqual(settings.answeredRounds(on: "2026-10-06"), [])
    }

    // MARK: 試験用の短縮（Debug ビルドの起動引数）

    func testLaunchArgumentsMoveTodaysRoundsToMinutesFromNow() throws {
        let launch = try date(6, 15, 0, second: 20)
        DebugRounds.applyLaunchArguments(
            ["Saydo", "-saydoRoundsInMinutes", "2,5,8", "-saydoRoundInterval", "60"],
            defaults: defaults,
            now: launch,
            calendar: calendar
        )

        let rules = settings.chaseRules(calendar: calendar)
        let times = rules.times(on: try date(6, 23))
        XCTAssertEqual(times.morning, launch.addingTimeInterval(120))
        XCTAssertEqual(times.noon, launch.addingTimeInterval(300))
        XCTAssertEqual(times.evening, launch.addingTimeInterval(480))
        XCTAssertEqual(rules.interval(on: launch), 60)

        // 設定の時刻は書き換えない。翌日は通常の時刻と間隔。
        XCTAssertEqual(settings.morningTime, TimeOfDay(hour: 10, minute: 0))
        XCTAssertEqual(rules.times(on: try date(7, 12)).morning, try date(7, 10))
        XCTAssertEqual(rules.interval(on: try date(7, 12)), 180)

        // 約束は、差し替えた時刻で追う。
        let promise = commitment(createdAt: launch.addingTimeInterval(60))
        XCTAssertEqual(rules.rounds(for: promise).map(\.start), [
            launch.addingTimeInterval(120), launch.addingTimeInterval(300), launch.addingTimeInterval(480),
        ])
    }

    func testTheOverrideSurvivesARelaunchWithoutArgumentsAndIsClearedByReset() throws {
        let launch = try date(6, 15)
        DebugRounds.applyLaunchArguments(
            ["Saydo", "-saydoRoundsInMinutes", "2,5,8"], defaults: defaults, now: launch, calendar: calendar
        )

        // 引数なしで開き直しても、同じ時刻のまま（基準の時刻は最初の起動で固定）。
        DebugRounds.applyLaunchArguments(
            ["Saydo"], defaults: defaults, now: launch.addingTimeInterval(200), calendar: calendar
        )
        XCTAssertEqual(
            settings.chaseRules(calendar: calendar).times(on: launch).morning,
            launch.addingTimeInterval(120)
        )
        XCTAssertNil(settings.roundOverride?.interval)

        DebugRounds.applyLaunchArguments(
            ["Saydo", "-saydoRoundsReset"], defaults: defaults, now: launch.addingTimeInterval(300), calendar: calendar
        )
        XCTAssertNil(settings.roundOverride)
        XCTAssertEqual(settings.chaseRules(calendar: calendar).times(on: launch).morning, try date(6, 10))
    }

    func testMalformedArgumentsAreIgnored() throws {
        let launch = try date(6, 15)
        for arguments in [
            ["Saydo", "-saydoRoundsInMinutes"],
            ["Saydo", "-saydoRoundsInMinutes", "2,5"],
            ["Saydo", "-saydoRoundsInMinutes", "8,5,2"],
            ["Saydo", "-saydoRoundsInMinutes", "a,b,c"],
            ["Saydo", "-saydoRoundInterval", "0"],
        ] {
            DebugRounds.applyLaunchArguments(arguments, defaults: defaults, now: launch, calendar: calendar)
            XCTAssertNil(settings.roundOverride, "\(arguments)")
        }
        XCTAssertEqual(DebugRounds.parseMinutes("2, 5, 8"), [2, 5, 8])
    }

    func testWithoutArgumentsNothingIsOverridden() throws {
        DebugRounds.applyLaunchArguments(["Saydo"], defaults: defaults, now: try date(6, 15), calendar: calendar)
        XCTAssertNil(settings.roundOverride)
    }
}
