import UserNotifications
import XCTest

import SaydoCore

@testable import Saydo

/// 通知の `userInfo` からの復元（task_009 のアプリ側・実装計画 §7.4）。
final class DeepLinkTests: XCTestCase {

    // MARK: - 素材

    private let day = Date(timeIntervalSince1970: 1_772_600_400) // 2026-03-04 09:00 UTC

    private func registration(
        slot: NotificationSlot,
        copyKey: NotificationCopyKey
    ) -> NotificationRegistration {
        NotificationRegistration(
            identifier: NotificationPlan.identifier(for: slot, day: day, calendar: .current),
            fireDate: day,
            slot: slot,
            copyKey: copyKey
        )
    }

    // MARK: - 組み立て

    func testUserInfoCarriesSessionTypeSlotAndCopyKey() {
        let info = DeepLink.userInfo(for: registration(slot: .morning, copyKey: .morning))

        XCTAssertEqual(info[NotificationUserInfoKey.sessionType], SessionType.morning.rawValue)
        XCTAssertEqual(info[NotificationUserInfoKey.slot], NotificationSlot.morning.rawValue)
        XCTAssertEqual(info[NotificationUserInfoKey.copyKey], NotificationCopyKey.morning.rawValue)
        XCTAssertNil(info[NotificationUserInfoKey.commitmentID])
    }

    func testUserInfoOmitsCommitmentIDWhenAbsent() {
        let info = DeepLink.userInfo(for: registration(slot: .night, copyKey: .night), commitmentID: nil)

        XCTAssertNil(info[NotificationUserInfoKey.commitmentID])
    }

    func testActionSlotUsesNoonSessionType() {
        let info = DeepLink.userInfo(for: registration(slot: .action, copyKey: .action))

        XCTAssertEqual(info[NotificationUserInfoKey.sessionType], SessionType.noon.rawValue)
        XCTAssertEqual(info[NotificationUserInfoKey.slot], NotificationSlot.action.rawValue)
    }

    // MARK: - 往復

    func testRoundTripKeepsEveryField() throws {
        let commitmentID = UUID()
        let info = DeepLink.userInfo(
            for: registration(slot: .action, copyKey: .action),
            commitmentID: commitmentID
        )

        let link = try XCTUnwrap(
            DeepLink.parse(userInfo: info, actionIdentifier: UNNotificationDefaultActionIdentifier)
        )

        XCTAssertEqual(link.sessionType, .noon)
        XCTAssertEqual(link.slot, .action)
        XCTAssertEqual(link.copyKey, .action)
        XCTAssertEqual(link.commitmentID, commitmentID)
        XCTAssertEqual(link.action, .open)
    }

    // MARK: - アクション種別

    func testDefaultActionIdentifierIsOpen() {
        XCTAssertEqual(DeepLink.action(forActionIdentifier: UNNotificationDefaultActionIdentifier), .open)
    }

    func testRestActionIdentifierIsRest() {
        XCTAssertEqual(
            DeepLink.action(forActionIdentifier: NotificationCopy.restTodayActionIdentifier),
            .rest
        )
    }

    func testDismissActionStartsNothing() {
        XCTAssertNil(DeepLink.action(forActionIdentifier: UNNotificationDismissActionIdentifier))

        let info = DeepLink.userInfo(for: registration(slot: .morning, copyKey: .morning))
        XCTAssertNil(
            DeepLink.parse(userInfo: info, actionIdentifier: UNNotificationDismissActionIdentifier)
        )
    }

    func testUnknownActionStartsNothing() {
        let info = DeepLink.userInfo(for: registration(slot: .morning, copyKey: .morning))

        XCTAssertNil(DeepLink.parse(userInfo: info, actionIdentifier: "saydo.notification.action.unknown"))
    }

    func testRestActionKeepsSessionTypeAndCommitmentID() throws {
        let commitmentID = UUID()
        let info = DeepLink.userInfo(
            for: registration(slot: .noon, copyKey: .noonRemember),
            commitmentID: commitmentID
        )

        let link = try XCTUnwrap(
            DeepLink.parse(userInfo: info, actionIdentifier: NotificationCopy.restTodayActionIdentifier)
        )

        XCTAssertEqual(link.action, .rest)
        XCTAssertEqual(link.sessionType, .noon)
        XCTAssertEqual(link.commitmentID, commitmentID)
    }

    // MARK: - 壊れた userInfo

    func testMissingSessionTypeIsNotOurNotification() {
        let info: [AnyHashable: Any] = [NotificationUserInfoKey.slot: NotificationSlot.morning.rawValue]

        XCTAssertNil(DeepLink.parse(userInfo: info, action: .open))
    }

    func testUnknownSessionTypeIsNotOurNotification() {
        let info: [AnyHashable: Any] = [NotificationUserInfoKey.sessionType: "brunch"]

        XCTAssertNil(DeepLink.parse(userInfo: info, action: .open))
    }

    func testEmptySessionTypeIsNotOurNotification() {
        let info: [AnyHashable: Any] = [NotificationUserInfoKey.sessionType: "   "]

        XCTAssertNil(DeepLink.parse(userInfo: info, action: .open))
    }

    func testNonStringValuesAreIgnored() throws {
        let info: [AnyHashable: Any] = [
            NotificationUserInfoKey.sessionType: SessionType.night.rawValue,
            NotificationUserInfoKey.slot: 3,
            NotificationUserInfoKey.commitmentID: 7,
        ]

        let link = try XCTUnwrap(DeepLink.parse(userInfo: info, action: .open))

        XCTAssertEqual(link.sessionType, .night)
        XCTAssertNil(link.slot)
        XCTAssertNil(link.commitmentID)
    }

    func testBrokenCommitmentIDDoesNotDropTheLink() throws {
        var info = DeepLink.userInfo(for: registration(slot: .noon, copyKey: .noonAvoiding))
        info[NotificationUserInfoKey.commitmentID] = "not-a-uuid"

        let link = try XCTUnwrap(DeepLink.parse(userInfo: info, action: .open))

        XCTAssertEqual(link.sessionType, .noon)
        XCTAssertNil(link.commitmentID)
    }

    func testUnknownSlotAndCopyKeyDoNotDropTheLink() throws {
        let info: [AnyHashable: Any] = [
            NotificationUserInfoKey.sessionType: SessionType.morning.rawValue,
            NotificationUserInfoKey.slot: "dawn",
            NotificationUserInfoKey.copyKey: "greeting",
        ]

        let link = try XCTUnwrap(DeepLink.parse(userInfo: info, action: .open))

        XCTAssertEqual(link.sessionType, .morning)
        XCTAssertNil(link.slot)
        XCTAssertNil(link.copyKey)
    }

    // MARK: - 識別子の管理範囲

    func testManagedPrefixesCoverEverySlot() {
        for slot in NotificationSlot.allCases {
            let identifier = NotificationPlan.identifier(for: slot, day: day, calendar: .current)
            XCTAssertTrue(NotificationIdentifier.isManaged(identifier), identifier)
        }
    }

    func testForeignIdentifierIsNotManaged() {
        XCTAssertFalse(NotificationIdentifier.isManaged("someone-else-20260304"))
    }

    func testMatchesOnlyTheGivenDay() {
        let calendar = Calendar.current
        let stamp = NotificationPlan.dayStamp(for: day, calendar: calendar)
        let today = NotificationPlan.identifier(for: .noon, day: day, calendar: calendar)
        let tomorrow = NotificationPlan.identifier(
            for: .noon,
            day: calendar.date(byAdding: .day, value: 1, to: day) ?? day,
            calendar: calendar
        )

        XCTAssertTrue(NotificationIdentifier.matches(dayStamp: stamp, identifier: today))
        XCTAssertFalse(NotificationIdentifier.matches(dayStamp: stamp, identifier: tomorrow))
    }
}
