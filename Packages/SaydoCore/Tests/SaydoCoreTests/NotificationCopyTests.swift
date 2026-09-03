import Foundation
import XCTest

@testable import SaydoCore

/// `NotificationCopy` の文言テスト。
///
/// 禁止句は `Guardrails`（task_005）が唯一の定義。ここにリストを複製しない。
/// 通知文言は平叙文・質問が混ざるので、形式規則を課さない `.statement` で検査する
/// （`Guardrails.check` の禁止句・断定形・N 日連続・URL・日本語必須はこの種別でも効く）。
final class NotificationCopyTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        guard let date = calendar.date(from: components) else {
            fatalError("invalid date components")
        }
        return date
    }

    // MARK: - 責めない

    func testNoNotificationTextViolatesGuardrails() {
        for text in NotificationCopy.allTexts {
            XCTAssertEqual(
                Guardrails.check(text, form: .statement),
                [],
                "通知文言が Guardrails に違反している: 「\(text)」"
            )
        }
    }

    func testEveryCopyKeyHasNonEmptyBody() {
        for key in NotificationCopyKey.allCases {
            XCTAssertFalse(NotificationCopy.body(for: key).isEmpty, "空の文言: \(key.rawValue)")
        }
        XCTAssertEqual(NotificationCopy.allTexts.count, NotificationCopyKey.allCases.count + 1)
    }

    // MARK: - 企画メモ §15 の文言

    func testFixedSessionBodiesMatchConceptMemo() {
        XCTAssertEqual(NotificationCopy.body(for: .morning), "今日、何から逃げそう？")
        XCTAssertEqual(NotificationCopy.body(for: .noonRemember), "朝、自分で言ったこと覚えてる？")
        XCTAssertEqual(NotificationCopy.body(for: .noonAvoiding), "例のやつ、まだ避けてる？")
        XCTAssertEqual(NotificationCopy.body(for: .night), "今日、逃げなかったことをひとつ声に出して。")
    }

    func testActionBodyIsTheMorningSelf() {
        XCTAssertEqual(NotificationCopy.body(for: .action), "朝のあなたからです。")
    }

    func testRestTodayActionTitle() {
        XCTAssertEqual(NotificationCopy.restTodayActionTitle, "今日は休む")
        XCTAssertFalse(NotificationCopy.restTodayActionIdentifier.isEmpty)
    }

    func testDeclarationReminderBody() {
        XCTAssertEqual(NotificationCopy.body(for: .declarationReminder), "30 秒だけ、声で約束して")
    }

    // MARK: - 昼の日替わり

    func testNoonCopyAlternatesEveryDay() {
        let firstDay = day(2026, 9, 4)
        var keys: [NotificationCopyKey] = []
        for offset in 0..<6 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return XCTFail("date(byAdding:) failed")
            }
            keys.append(NotificationCopy.noonKey(for: date, calendar: calendar))
        }

        // 隣り合う日は必ず違う文言になる。
        for index in 1..<keys.count {
            XCTAssertNotEqual(keys[index], keys[index - 1], "day offset \(index)")
        }
        // 2 種類しか使わない。
        XCTAssertEqual(Set(keys), Set([.noonRemember, .noonAvoiding]))
    }

    func testNoonCopyIsStableForTheSameDay() {
        let date = day(2026, 9, 4)
        let first = NotificationCopy.noonKey(for: date, calendar: calendar)
        let second = NotificationCopy.noonKey(for: date, calendar: calendar)
        XCTAssertEqual(first, second)

        // 同じ暦日なら時刻が違っても同じ文言。
        guard let noon = calendar.date(byAdding: .hour, value: 12, to: date) else {
            return XCTFail("date(byAdding:) failed")
        }
        XCTAssertEqual(NotificationCopy.noonKey(for: noon, calendar: calendar), first)
    }

    func testPlanUsesAlternatingNoonCopy() {
        let plan = NotificationPlan.make(
            now: calendar.date(byAdding: .hour, value: 5, to: day(2026, 9, 4)) ?? day(2026, 9, 4),
            settings: NotificationSettings(
                morning: TimeOfDay(hour: 7, minute: 0),
                noon: TimeOfDay(hour: 12, minute: 30),
                night: TimeOfDay(hour: 21, minute: 0),
                mode: .thrice
            ),
            today: .noCommitment,
            calendar: calendar
        )

        let noonKeys = plan.registrations
            .filter { $0.slot == .noon }
            .map(\.copyKey)
        XCTAssertEqual(noonKeys.count, 16)
        for index in 1..<noonKeys.count {
            XCTAssertNotEqual(noonKeys[index], noonKeys[index - 1], "index \(index)")
        }
    }
}
