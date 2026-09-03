import Foundation
import UserNotifications

import SaydoCore

// MARK: - userInfo のキー

/// 通知の `userInfo` に入れるキー（実装計画 §7.4）。
///
/// 値はすべて `String` にする。`UNMutableNotificationContent.userInfo` はプロパティリスト
/// 互換の値しか受け付けないうえ、`[String: String]` なら Swift 6 の Sendable 検査を
/// そのまま通せるため。
public enum NotificationUserInfoKey {
    /// `SessionType.rawValue`。通知タップで始まるフローを決める。
    public static let sessionType = "saydo.sessionType"
    /// `NotificationSlot.rawValue`。どの枠の通知だったか。
    public static let slot = "saydo.slot"
    /// `UUID.uuidString`。当日の宣言がまだ無い通知には入れない。
    public static let commitmentID = "saydo.commitmentID"
    /// `NotificationCopyKey.rawValue`。どの文言で届いたか。
    public static let copyKey = "saydo.copyKey"
}

// MARK: - DeepLink

/// 通知から復元した起動要求。
///
/// `UNUserNotificationCenterDelegate.didReceive` はこの値だけを `AppRouter`
/// （`SessionLauncher`）へ渡す。`UNNotificationResponse` そのものは渡さない
/// （Sendable でない型をアクター境界に持ち込まないため）。
public struct DeepLink: Sendable, Hashable {

    /// 通知に対して本人が取った操作。
    public enum Action: String, Sendable, Hashable, CaseIterable {
        /// 通知本体をタップした（既定アクション）。会話を始める。
        case open
        /// 通知を長押しして「今日は休む」を選んだ（retention-strategy R3）。
        ///
        /// 会話は始めず、当日を休みとして終える。記録上の失敗にはしない。
        case rest
    }

    /// タップで始めるセッション。行動時刻通知は昼と同じフローに入る（`NotificationSlot.sessionType`）。
    public let sessionType: SessionType
    /// どの枠の通知だったか。旧い形式の通知には入っていない可能性があるので optional。
    public let slot: NotificationSlot?
    /// 当日の宣言の識別子。朝の宣言前に届く通知には入っていない。
    public let commitmentID: UUID?
    /// 届いた文言。分析とデバッグ用で、フローの分岐には使わない。
    public let copyKey: NotificationCopyKey?
    /// 本人が取った操作。
    public let action: Action

    public init(
        sessionType: SessionType,
        slot: NotificationSlot? = nil,
        commitmentID: UUID? = nil,
        copyKey: NotificationCopyKey? = nil,
        action: Action
    ) {
        self.sessionType = sessionType
        self.slot = slot
        self.commitmentID = commitmentID
        self.copyKey = copyKey
        self.action = action
    }
}

// MARK: - 組み立て

extension DeepLink {

    /// 登録する通知に載せる `userInfo`。
    ///
    /// - Parameters:
    ///   - registration: `NotificationPlan` が計算した 1 本ぶん。
    ///   - commitmentID: 当日の宣言の識別子。宣言前なら nil を渡す。
    public static func userInfo(
        for registration: NotificationRegistration,
        commitmentID: UUID? = nil
    ) -> [String: String] {
        var info: [String: String] = [
            NotificationUserInfoKey.sessionType: registration.sessionType.rawValue,
            NotificationUserInfoKey.slot: registration.slot.rawValue,
            NotificationUserInfoKey.copyKey: registration.copyKey.rawValue,
        ]
        if let commitmentID {
            info[NotificationUserInfoKey.commitmentID] = commitmentID.uuidString
        }
        return info
    }
}

// MARK: - 解析

extension DeepLink {

    /// `UNNotificationResponse.actionIdentifier` を操作の種別に直す。
    ///
    /// スワイプで消しただけ（`UNNotificationDismissActionIdentifier`）と未知の識別子は nil。
    /// nil のときは何も起動しない。
    public static func action(forActionIdentifier identifier: String) -> Action? {
        switch identifier {
        case UNNotificationDefaultActionIdentifier:
            .open
        case NotificationCopy.restTodayActionIdentifier:
            .rest
        default:
            nil
        }
    }

    /// `userInfo` と `actionIdentifier` から起動要求を復元する。
    ///
    /// `sessionType` が無い／読めない通知は SAYDO の通知ではないとみなして nil を返す。
    public static func parse(userInfo: [AnyHashable: Any], actionIdentifier: String) -> DeepLink? {
        guard let action = action(forActionIdentifier: actionIdentifier) else { return nil }
        return parse(userInfo: userInfo, action: action)
    }

    /// 操作の種別が確定している場合の解析。
    public static func parse(userInfo: [AnyHashable: Any], action: Action) -> DeepLink? {
        guard let rawSessionType = text(userInfo[NotificationUserInfoKey.sessionType]),
              let sessionType = SessionType(rawValue: rawSessionType)
        else { return nil }

        return DeepLink(
            sessionType: sessionType,
            slot: text(userInfo[NotificationUserInfoKey.slot]).flatMap(NotificationSlot.init(rawValue:)),
            commitmentID: text(userInfo[NotificationUserInfoKey.commitmentID]).flatMap(UUID.init(uuidString:)),
            copyKey: text(userInfo[NotificationUserInfoKey.copyKey]).flatMap(NotificationCopyKey.init(rawValue:)),
            action: action
        )
    }

    /// 空文字と空白だけの値は「無い」と同じに扱う。
    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - UNNotificationResponse からの復元

extension DeepLink {

    /// 受け取った応答から復元する。SAYDO の通知でない場合と、何も起動しない操作の場合は nil。
    public init?(response: UNNotificationResponse) {
        guard let link = DeepLink.parse(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier
        ) else { return nil }
        self = link
    }
}
