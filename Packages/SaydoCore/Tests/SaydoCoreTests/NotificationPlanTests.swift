import Foundation
import XCTest

@testable import SaydoCore

/// `NotificationPlan` の純計算のテスト。
///
/// 基準日は 2026-09-04（金）。曜日が効く週末オフのテストだけ日付を動かす。
final class NotificationPlanTests: XCTestCase {

    // MARK: - 固定の道具

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else {
            fatalError("invalid date components")
        }
        return date
    }

    private func settings(
        mode: NotificationMode,
        morning: TimeOfDay = TimeOfDay(hour: 7, minute: 0),
        noon: TimeOfDay = TimeOfDay(hour: 12, minute: 30),
        night: TimeOfDay = TimeOfDay(hour: 21, minute: 0),
        weekendEnabled: Bool = true
    ) -> NotificationSettings {
        NotificationSettings(
            morning: morning,
            noon: noon,
            night: night,
            mode: mode,
            weekendEnabled: weekendEnabled
        )
    }

    private func identifiers(_ plan: NotificationPlan) -> [String] {
        plan.registrations.map(\.identifier)
    }

    // MARK: - モード別の日数

    func testPlanningDayCountIsThirtyForTwiceMode() {
        XCTAssertEqual(NotificationMode.twice.fixedNotificationsPerDay, 1)
        XCTAssertEqual(NotificationPlan.planningDayCount(for: .twice), 30)
    }

    func testPlanningDayCountIsSixteenForThriceMode() {
        XCTAssertEqual(NotificationMode.thrice.fixedNotificationsPerDay, 3)
        XCTAssertEqual(NotificationPlan.planningDayCount(for: .thrice), 16)
    }

    func testTwiceModeRegistersThirtyMorningNotifications() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 5, 0),
            settings: settings(mode: .twice),
            today: .noCommitment,
            calendar: calendar
        )

        XCTAssertEqual(plan.registrations.count, 30)
        XCTAssertTrue(plan.registrations.allSatisfy { $0.slot == .morning })
        XCTAssertEqual(identifiers(plan).first, "morning-20260904")
        XCTAssertEqual(identifiers(plan).last, "morning-20261003")
    }

    func testThriceModeRegistersSixteenDaysOfThreeNotifications() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 5, 0),
            settings: settings(mode: .thrice),
            today: .noCommitment,
            calendar: calendar
        )

        XCTAssertEqual(plan.registrations.count, 48)
        XCTAssertEqual(Array(identifiers(plan).prefix(3)), ["morning-20260904", "noon-20260904", "night-20260904"])
        XCTAssertEqual(identifiers(plan).last, "night-20260919")
    }

    func testRegistrationCountStaysWithinPendingBudget() {
        for mode in NotificationMode.allCases {
            let plan = NotificationPlan.make(
                now: date(2026, 9, 4, 5, 0),
                settings: settings(mode: mode),
                today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0)),
                calendar: calendar
            )
            XCTAssertLessThanOrEqual(
                plan.registrations.count,
                NotificationPlan.pendingBudget,
                "mode: \(mode.rawValue)"
            )
        }
    }

    // MARK: - 翌日繰り越し

    func testPastSlotsAreNotRegisteredAndPlanStartsTomorrow() {
        // 22:00。当日の朝・昼・夜はすべて過ぎている。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 22, 0),
            settings: settings(mode: .thrice),
            today: .noCommitment,
            calendar: calendar
        )

        XCTAssertFalse(identifiers(plan).contains { $0.hasSuffix("20260904") })
        XCTAssertEqual(identifiers(plan).first, "morning-20260905")
        // 先読みは 16 日ぶんのまま。当日は 0 本なので 15 日 × 3 本。
        XCTAssertEqual(plan.registrations.count, 45)
    }

    func testTodayRemainingSlotsAreKeptWhenPlanningMidday() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 13, 0),
            settings: settings(mode: .thrice),
            today: .noCommitment,
            calendar: calendar
        )

        XCTAssertFalse(identifiers(plan).contains("morning-20260904"))
        XCTAssertFalse(identifiers(plan).contains("noon-20260904"))
        XCTAssertTrue(identifiers(plan).contains("night-20260904"))
    }

    // MARK: - 時刻変更

    func testChangingTimesMovesFireDates() {
        let now = date(2026, 9, 4, 5, 0)
        let early = NotificationPlan.make(
            now: now,
            settings: settings(mode: .thrice, morning: TimeOfDay(hour: 6, minute: 15)),
            today: .noCommitment,
            calendar: calendar
        )
        let late = NotificationPlan.make(
            now: now,
            settings: settings(mode: .thrice, morning: TimeOfDay(hour: 9, minute: 45)),
            today: .noCommitment,
            calendar: calendar
        )

        let earlyMorning = early.registrations.first { $0.identifier == "morning-20260904" }
        let lateMorning = late.registrations.first { $0.identifier == "morning-20260904" }
        XCTAssertEqual(earlyMorning?.fireDate, date(2026, 9, 4, 6, 15))
        XCTAssertEqual(lateMorning?.fireDate, date(2026, 9, 4, 9, 45))
        XCTAssertEqual(early.registrations.count, late.registrations.count)
    }

    func testMorningTimeLaterThanNowIsStillRegisteredToday() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 6, 30),
            settings: settings(mode: .twice, morning: TimeOfDay(hour: 7, minute: 0)),
            today: .noCommitment,
            calendar: calendar
        )
        XCTAssertEqual(identifiers(plan).first, "morning-20260904")
    }

    // MARK: - 昼と行動時刻の重複

    func testNoonSkippedWhenWithinThirtyMinutesOfPlannedTime() {
        // 行動時刻 12:00 は過ぎている（now 12:10）。昼 12:30 との差は 30 分ちょうど。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 12, 10),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 12, 0)),
            calendar: calendar
        )

        XCTAssertFalse(identifiers(plan).contains("noon-20260904"))
        XCTAssertTrue(plan.cancelledIdentifiers.contains("noon-20260904"))
        XCTAssertTrue(identifiers(plan).contains("night-20260904"))
    }

    func testNoonKeptWhenPlannedTimeIsPastAndFarFromNoon() {
        // 行動時刻 11:00 は過ぎており、昼 12:30 とは 90 分離れている。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 11, 10),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 11, 0)),
            calendar: calendar
        )

        XCTAssertTrue(identifiers(plan).contains("noon-20260904"))
        XCTAssertFalse(plan.cancelledIdentifiers.contains("noon-20260904"))
    }

    func testNoonSkippedWhilePlannedTimeIsStillAhead() {
        // 朝の宣言直後。行動時刻 15:00 はまだ来ていないので、昼は出さず行動時刻通知だけにする。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 7, 30),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0)),
            calendar: calendar
        )

        XCTAssertFalse(identifiers(plan).contains("noon-20260904"))
        XCTAssertTrue(plan.cancelledIdentifiers.contains("noon-20260904"))
        XCTAssertTrue(identifiers(plan).contains("action-20260904"))
        // 翌日以降の昼は残る。
        XCTAssertTrue(identifiers(plan).contains("noon-20260905"))
    }

    func testNoonKeptWhenPlannedTimeIsBeforeNoonEvenIfStillAhead() {
        // 朝の宣言直後（now 7:30）で行動時刻 10:00 はまだ先だが、昼 12:30 より前に来る。
        // 昼は「行動時刻通知を見送った人への確認」として残す。計画時点の now で判定すると
        // ここで昼が消え、行動時刻通知を無視した日に「どうだった？」が一度も届かない。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 7, 30),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 10, 0)),
            calendar: calendar
        )

        XCTAssertTrue(identifiers(plan).contains("noon-20260904"))
        XCTAssertFalse(plan.cancelledIdentifiers.contains("noon-20260904"))
        XCTAssertTrue(identifiers(plan).contains("action-20260904"))
    }

    func testNoonSkipDependsOnNoonFireTimeNotPlanningTime() {
        // 純関数で直接: 昼 12:30、行動時刻 15:00 は昼が先に鳴るので出さない。
        XCTAssertTrue(
            NotificationPlan.shouldSkipTodayNoon(
                noonFireDate: date(2026, 9, 4, 12, 30),
                plannedAt: date(2026, 9, 4, 15, 0)
            )
        )
        // 行動時刻 10:00 は昼より前なので昼は出す（計画時点の時刻は判定に使わない）。
        XCTAssertFalse(
            NotificationPlan.shouldSkipTodayNoon(
                noonFireDate: date(2026, 9, 4, 12, 30),
                plannedAt: date(2026, 9, 4, 10, 0)
            )
        )
    }

    func testNoonKeptOnDaysWithoutCommitment() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 5, 0),
            settings: settings(mode: .thrice),
            today: .noCommitment,
            calendar: calendar
        )
        XCTAssertTrue(identifiers(plan).contains("noon-20260904"))
        XCTAssertTrue(plan.cancelledIdentifiers.isEmpty)
    }

    // MARK: - 行動時刻通知

    func testActionNotificationRegisteredOnlyAfterDeclaration() {
        let before = NotificationPlan.make(
            now: date(2026, 9, 4, 7, 30),
            settings: settings(mode: .twice),
            today: .noCommitment,
            calendar: calendar
        )
        XCTAssertFalse(identifiers(before).contains { $0.hasPrefix("action-") })

        let after = NotificationPlan.make(
            now: date(2026, 9, 4, 7, 30),
            settings: settings(mode: .twice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0)),
            calendar: calendar
        )
        let action = after.registrations.first { $0.identifier == "action-20260904" }
        XCTAssertEqual(action?.fireDate, date(2026, 9, 4, 15, 0))
        XCTAssertEqual(action?.copyKey, .action)
        XCTAssertEqual(action?.sessionType, .noon)
    }

    func testActionNotificationSkippedWhenPlannedTimeAlreadyPassed() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 16, 0),
            settings: settings(mode: .twice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0)),
            calendar: calendar
        )
        XCTAssertFalse(identifiers(plan).contains("action-20260904"))
    }

    // MARK: - done / partial の取り消し

    func testDoneCancelsTodayNoonAndAction() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 12, 0),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0), outcome: .done),
            calendar: calendar
        )

        XCTAssertEqual(plan.cancelledIdentifiers, ["noon-20260904", "action-20260904"])
        XCTAssertFalse(identifiers(plan).contains("noon-20260904"))
        XCTAssertFalse(identifiers(plan).contains("action-20260904"))
        // 夜と翌日以降は残す。
        XCTAssertTrue(identifiers(plan).contains("night-20260904"))
        XCTAssertTrue(identifiers(plan).contains("noon-20260905"))
    }

    func testPartialCancelsTodayNoonAndAction() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 12, 0),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0), outcome: .partial),
            calendar: calendar
        )

        XCTAssertEqual(plan.cancelledIdentifiers, ["noon-20260904", "action-20260904"])
        XCTAssertFalse(identifiers(plan).contains("action-20260904"))
    }

    func testNotYetKeepsTodayActionNotification() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 12, 0),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0), outcome: .notYet),
            calendar: calendar
        )

        XCTAssertFalse(plan.cancelledIdentifiers.contains("action-20260904"))
        XCTAssertTrue(identifiers(plan).contains("action-20260904"))
    }

    // MARK: - 週末オフ

    func testWeekendOffRemovesSaturdayAndSundayFixedNotifications() {
        // 2026-09-04 は金曜。翌日 5 日が土曜、6 日が日曜。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 5, 0),
            settings: settings(mode: .thrice, weekendEnabled: false),
            today: .noCommitment,
            calendar: calendar
        )

        XCTAssertTrue(identifiers(plan).contains("morning-20260904"))
        XCTAssertFalse(identifiers(plan).contains { $0.hasSuffix("20260905") })
        XCTAssertFalse(identifiers(plan).contains { $0.hasSuffix("20260906") })
        XCTAssertTrue(identifiers(plan).contains("morning-20260907"))
    }

    func testWeekendOffStillDeliversActionNotificationOnSaturday() {
        // 2026-09-05（土）に本人が行動時刻を決めた場合は、その 1 本だけ出す。
        let plan = NotificationPlan.make(
            now: date(2026, 9, 5, 8, 0),
            settings: settings(mode: .twice, weekendEnabled: false),
            today: DayCommitment(plannedAt: date(2026, 9, 5, 10, 0)),
            calendar: calendar
        )

        XCTAssertTrue(identifiers(plan).contains("action-20260905"))
        XCTAssertFalse(identifiers(plan).contains("morning-20260905"))
    }

    // MARK: - 識別子と userInfo

    func testIdentifierFormat() {
        let day = date(2026, 9, 4, 0, 0)
        XCTAssertEqual(NotificationPlan.dayStamp(for: day, calendar: calendar), "20260904")
        XCTAssertEqual(NotificationPlan.identifier(for: .morning, day: day, calendar: calendar), "morning-20260904")
        XCTAssertEqual(NotificationPlan.identifier(for: .noon, day: day, calendar: calendar), "noon-20260904")
        XCTAssertEqual(NotificationPlan.identifier(for: .night, day: day, calendar: calendar), "night-20260904")
        XCTAssertEqual(NotificationPlan.identifier(for: .action, day: day, calendar: calendar), "action-20260904")
    }

    func testSessionTypeCarriedInUserInfo() {
        XCTAssertEqual(NotificationSlot.morning.sessionType, .morning)
        XCTAssertEqual(NotificationSlot.noon.sessionType, .noon)
        XCTAssertEqual(NotificationSlot.night.sessionType, .night)
        // 行動時刻通知は「宣言を再生して状態を聞く」ので昼と同じフローに入る。
        XCTAssertEqual(NotificationSlot.action.sessionType, .noon)
    }

    // MARK: - 「今は話せない」の再登録（設計判断 D6）

    func testSnoozeIntervalIsSixtyMinutes() {
        XCTAssertEqual(NotificationPlan.snoozeInterval, 60 * 60)
    }

    func testMaxSnoozesPerDayIsTwo() {
        XCTAssertEqual(NotificationPlan.maxSnoozesPerDay, 2)
    }

    func testSnoozeIdentifierFormat() {
        XCTAssertEqual(
            NotificationPlan.snoozeIdentifier(base: "noon-20260904", attempt: 1),
            "noon-20260904-snooze1"
        )
        XCTAssertEqual(
            NotificationPlan.snoozeIdentifier(base: "action-20260904", attempt: 2),
            "action-20260904-snooze2"
        )
    }

    func testSnoozeAttemptReadsTheAttemptBack() {
        XCTAssertEqual(NotificationPlan.snoozeAttempt(in: "noon-20260904-snooze1"), 1)
        XCTAssertEqual(NotificationPlan.snoozeAttempt(in: "noon-20260904-snooze2"), 2)
    }

    func testSnoozeAttemptIsNilForNonSnoozeIdentifiers() {
        XCTAssertNil(NotificationPlan.snoozeAttempt(in: "noon-20260904"))
        XCTAssertNil(NotificationPlan.snoozeAttempt(in: "noon-20260904-snooze"))
        XCTAssertNil(NotificationPlan.snoozeAttempt(in: "noon-20260904-snoozeX"))
        XCTAssertNil(NotificationPlan.snoozeAttempt(in: "noon-20260904-snooze0"))
        XCTAssertNil(NotificationPlan.snoozeAttempt(in: "noon-20260904-snooze-1"))
        XCTAssertNil(NotificationPlan.snoozeAttempt(in: "-snooze1"))
    }

    func testBaseIdentifierStripsOnlyTheSnoozeSuffix() {
        XCTAssertEqual(NotificationPlan.baseIdentifier(of: "noon-20260904-snooze2"), "noon-20260904")
        XCTAssertEqual(NotificationPlan.baseIdentifier(of: "noon-20260904"), "noon-20260904")
        XCTAssertEqual(NotificationPlan.baseIdentifier(of: "noon-20260904-snoozeX"), "noon-20260904-snoozeX")
    }

    func testFirstSnoozeIsAttemptOne() {
        let base = NotificationPlan.identifier(for: .noon, day: date(2026, 9, 4, 0, 0), calendar: calendar)

        XCTAssertEqual(NotificationPlan.nextSnoozeAttempt(base: base, pending: []), 1)
    }

    func testSecondSnoozeIsAttemptTwo() {
        let base = "noon-20260904"

        XCTAssertEqual(
            NotificationPlan.nextSnoozeAttempt(base: base, pending: ["noon-20260904-snooze1"]),
            2
        )
    }

    func testThirdSnoozeIsRefused() {
        let base = "noon-20260904"
        let pending = ["noon-20260904-snooze1", "noon-20260904-snooze2"]

        XCTAssertNil(NotificationPlan.nextSnoozeAttempt(base: base, pending: pending))
    }

    func testSnoozeLimitCountsTheHighestAttemptEvenIfEarlierOnesAlreadyFired() {
        // snooze1 は発火済みで保留から消えている。それでも 3 回目は登録しない。
        XCTAssertNil(
            NotificationPlan.nextSnoozeAttempt(base: "noon-20260904", pending: ["noon-20260904-snooze2"])
        )
    }

    func testUnrelatedIdentifiersDoNotConsumeTheSnoozeLimit() {
        let pending = [
            "morning-20260904",
            "morning-20260904-snooze1",
            "noon-20260905-snooze1",
            "noon-20260904",
            "someone-else-20260904-snooze2",
        ]

        XCTAssertEqual(NotificationPlan.nextSnoozeAttempt(base: "noon-20260904", pending: pending), 1)
    }

    func testSnoozeLimitIsPerSlotAndPerDay() {
        let pending = ["noon-20260904-snooze1", "noon-20260904-snooze2"]

        XCTAssertNil(NotificationPlan.nextSnoozeAttempt(base: "noon-20260904", pending: pending))
        XCTAssertEqual(NotificationPlan.nextSnoozeAttempt(base: "action-20260904", pending: pending), 1)
        XCTAssertEqual(NotificationPlan.nextSnoozeAttempt(base: "noon-20260905", pending: pending), 1)
    }

    func testRegistrationsAreSortedByFireDate() {
        let plan = NotificationPlan.make(
            now: date(2026, 9, 4, 5, 0),
            settings: settings(mode: .thrice),
            today: DayCommitment(plannedAt: date(2026, 9, 4, 15, 0)),
            calendar: calendar
        )
        let fireDates = plan.registrations.map(\.fireDate)
        XCTAssertEqual(fireDates, fireDates.sorted())
    }
}
