import Foundation
import UserNotifications

import SaydoCore

/// `FlowMachine` の通知命令（`SessionViewModel` の `NotificationScheduling`）を
/// `NotificationScheduler` に配線する。
///
/// 本体（`NotificationScheduler.swift`、task_009）は「計画をまるごと作り直す」ことを担い、
/// ここは会話の途中に 1 本だけ足す・消す操作だけを受ける。会話が出す命令は
/// `.actionTime`（行動時刻）と `.declarationReminder`（宣言の後回し）、
/// 取り消しは `.actionTime` と `.noonFixed` の 4 種類しかない
/// （`MorningFlow` / `NoonFlow` を grep して確認）。
extension NotificationScheduler: NotificationScheduling {

    /// 会話の途中で 1 本だけ登録する。
    ///
    /// - `.actionTime`: 本人が決めた時刻に「朝のあなたからです。」を出す。識別子は
    ///   `action-yyyyMMdd` で、`NotificationPlan` が作るものと同じ規約に従う。
    ///   集中モード中でも届かせるため `.timeSensitive`（エンタイトルメントは task_009 側）。
    /// - `fireDate` が無い（時刻を解決できなかった）ときは登録しない。時刻の分からない
    ///   通知を出すより、行動時刻通知が無い日にする方が害が小さい。
    /// - `.declarationReminder` は識別子の規約（`morning-` / `noon-` / `night-` / `action-` の
    ///   どれにも当てはまらない 1 回だけの通知）が未定のため、ここでは登録しない。
    ///   規約が決まるまでの継ぎ目として `docs/PROGRESS.md` に記録する。
    func schedule(
        _ request: NotificationRequest,
        fireDate: Date?,
        commitmentID: UUID?,
        on day: Date
    ) async throws {
        guard request.kind == .actionTime, let fireDate else { return }
        let registration = NotificationRegistration(
            identifier: NotificationPlan.identifier(for: .action, day: day, calendar: .current),
            fireDate: fireDate,
            slot: .action,
            copyKey: .action
        )
        try await add(registration, commitmentID: commitmentID)
    }

    /// その日の該当する通知を取り消す。
    func cancel(_ kind: NotificationRequest.Kind, on day: Date) async throws {
        guard let slot = Self.slot(for: kind) else { return }
        cancel(identifiers: [NotificationPlan.identifier(for: slot, day: day, calendar: .current)])
    }

    // MARK: - 内部

    private static func slot(for kind: NotificationRequest.Kind) -> NotificationSlot? {
        switch kind {
        case .actionTime: .action
        case .noonFixed: .noon
        case .night: .night
        case .declarationReminder: nil
        }
    }

    /// 1 本だけ登録する。本体の `apply(_:)` は保留通知を全部作り直すので、
    /// 会話の途中では使えない（登録済みの先の日ぶんまで消えてしまう）。
    private func add(_ registration: NotificationRegistration, commitmentID: UUID?) async throws {
        let content = UNMutableNotificationContent()
        content.body = NotificationCopy.body(for: registration.copyKey)
        content.sound = .default
        content.categoryIdentifier = NotificationCopy.categoryIdentifier
        content.userInfo = DeepLink.userInfo(for: registration, commitmentID: commitmentID)
        content.interruptionLevel = .timeSensitive

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: registration.fireDate
        )
        let request = UNNotificationRequest(
            identifier: registration.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        // 完了ハンドラ版を包む（`UNNotificationRequest` を隔離の境界に渡さないため。
        // 本体の `NotificationScheduler` と同じ理由・同じ形）。
        let center = UNUserNotificationCenter.current()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
