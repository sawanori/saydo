import Foundation
import UserNotifications

// MARK: - 識別子

/// 旧い版が登録した通知の識別子の規約。
///
/// 旧い版は `<枠>-yyyyMMdd`（枠は morning / noon / night / action）、「今は話せない」の再登録は
/// `<枠>-yyyyMMdd-snooze<n>` で通知を登録していた。いまの版は通知を登録しない（朝・昼・晩はアラームで追う。
/// 実装計画 §17.9）。ここには「この識別子は旧い版のものか」の判定だけを置く。
/// アクター隔離を持たせない（保留通知のコールバックは MainActor 外で走るため）。
enum NotificationIdentifier {

    /// 旧い版が登録・取り消しの対象にしていた接頭辞（朝・昼・夜・行動時刻）。
    static let managedPrefixes: [String] = ["morning-", "noon-", "night-", "action-"]

    /// 旧い版が登録した識別子か。再登録の識別子も接頭辞は同じなので真になる。
    static func isManaged(_ identifier: String) -> Bool {
        managedPrefixes.contains { identifier.hasPrefix($0) }
    }
}

// MARK: - 旧い通知のタップ

/// 旧い版が登録した通知のタップを見分ける。
///
/// 通知を長押しして選ぶ操作（「今日は休む」「今は話せない」）は、いまの版は用意しない。
/// すでに通知センターに届いている旧い通知の、本体のタップだけを扱う。
enum LegacyNotificationTap {

    /// 旧い版の通知の本体をタップしたか。スワイプで消しただけ・SAYDO 以外の通知は false。
    static func isTap(actionIdentifier: String, requestIdentifier: String) -> Bool {
        actionIdentifier == UNNotificationDefaultActionIdentifier
            && NotificationIdentifier.isManaged(requestIdentifier)
    }
}

// MARK: - スケジューラ

/// 旧い版が登録した保留中の通知の後始末（`UNUserNotificationCenter` のラッパ）。
///
/// いまの版は通知を登録しない。起動・前面復帰のたびに、旧い版が残した保留中の通知を取り消すだけ。
@MainActor
final class NotificationScheduler {

    static let shared = NotificationScheduler()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// 旧い版が登録した保留中の通知を、すべて取り消す。
    func removeAllManagedPending() async {
        let identifiers = await pendingIdentifiers().filter(NotificationIdentifier.isManaged)
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// 保留通知の識別子（SAYDO 以外も含む）。
    private func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }
}
