import Foundation
import XCTest

@testable import SaydoCore

/// `NotificationCopy` の文言テスト。
///
/// 禁止句リストは実装計画 §7.5 の初期値をこのファイルに直接持つ。
/// `Guardrails`（task_005）は別ブランチで実装中のため、そこへの依存を作らない。
/// task_005 が入ったら `Guardrails` 側のリストと突き合わせて重複を解消する。
final class NotificationCopyTests: XCTestCase {

    /// 実装計画 §7.5 の禁止語リスト（初期値）。同じテストターゲットの他のテストからも使う。
    static let forbiddenPhrases = [
        "未達成",
        "連続",
        "サボ",
        "怠",
        "ダメ",
        "なぜやらない",
        "失敗",
        "遅い",
        "甘え",
        "言い訳",
        "また逃げ"
    ]

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

    func testNoNotificationTextContainsForbiddenPhrase() {
        for text in NotificationCopy.allTexts {
            for phrase in Self.forbiddenPhrases {
                XCTAssertFalse(
                    text.contains(phrase),
                    "通知文言に禁止句が入っている: 「\(text)」 に 「\(phrase)」"
                )
            }
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
