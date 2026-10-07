import UserNotifications
import XCTest

@testable import Saydo

/// 旧い版が登録した通知の見分け方（後始末の対象と、タップの判定）。
final class LegacyNotificationTests: XCTestCase {

    func testEveryOldSlotIdentifierIsManaged() {
        for slot in ["morning", "noon", "night", "action"] {
            XCTAssertTrue(NotificationIdentifier.isManaged("\(slot)-20260304"), slot)
        }
    }

    /// 「今は話せない」の再登録の識別子も、後始末の対象になる。
    func testSnoozeIdentifierIsManaged() {
        XCTAssertTrue(NotificationIdentifier.isManaged("noon-20260304-snooze1"))
        XCTAssertTrue(NotificationIdentifier.isManaged("noon-20260304-snooze2"))
    }

    func testForeignIdentifierIsNotManaged() {
        XCTAssertFalse(NotificationIdentifier.isManaged("someone-else-20260304"))
        XCTAssertFalse(NotificationIdentifier.isManaged("someone-else-20260304-snooze1"))
    }

    func testTapOnAnOldNotificationBodyIsATap() {
        XCTAssertTrue(
            LegacyNotificationTap.isTap(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                requestIdentifier: "morning-20260304"
            )
        )
    }

    func testDismissingOrAnotherActionIsNotATap() {
        XCTAssertFalse(
            LegacyNotificationTap.isTap(
                actionIdentifier: UNNotificationDismissActionIdentifier,
                requestIdentifier: "morning-20260304"
            )
        )
        XCTAssertFalse(
            LegacyNotificationTap.isTap(actionIdentifier: "saydo.rest", requestIdentifier: "morning-20260304")
        )
    }

    func testTapOnAForeignNotificationIsNotATap() {
        XCTAssertFalse(
            LegacyNotificationTap.isTap(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                requestIdentifier: "someone-else-20260304"
            )
        )
    }
}
