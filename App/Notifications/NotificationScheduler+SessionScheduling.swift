import Foundation
import UserNotifications

import SaydoCore

/// `FlowMachine` の通知命令（`SessionViewModel` の `NotificationScheduling`）を
/// `NotificationScheduler` に配線する。
///
/// 本体（`NotificationScheduler.swift`、task_009）は「計画をまるごと作り直す」ことを担い、
/// ここは会話が出す命令をそれに写す。会話が出す命令は `.actionTime`（行動時刻）と
/// `.declarationReminder`（宣言の後回し）、取り消しは `.actionTime` と `.noonFixed` の 4 種類しかない
/// （`MorningFlow` / `NoonFlow` を grep して確認）。
extension NotificationScheduler: NotificationScheduling {

    /// 宣言（M4）や再縮小（N3）で行動時刻が決まったら、その時刻を入れて今日からの計画を作り直し、
    /// 行動時刻の通知を登録できたかを返す（実装計画 §16.7）。
    ///
    /// - `.actionTime`: 行動時刻通知（`action-yyyyMMdd`、`.timeSensitive`）を加え、昼の固定通知が
    ///   行動時刻より前に鳴る日はそれを外す（`NotificationPlan` 規則 3(b)）。
    /// - 通知が許可されていなければ登録せず `.notAuthorized`、`fireDate` が `day`（呼び出し時点の
    ///   現在時刻）以前なら登録せず `.pastTime` を返す。
    /// - `fireDate` が無い（時刻を解決できなかった）ときは登録せず `.failed`。時刻の分からない
    ///   通知を出すより、行動時刻通知が無い日にする方が害が小さい。
    /// - `.declarationReminder`（宣言の後回し。R1）は識別子の規約（`NotificationSlot`）が未定のため
    ///   登録せず `.failed`。`docs/PROGRESS.md` の integration-2 エントリに継ぎ目として記録。
    func schedule(
        _ request: NotificationRequest,
        fireDate: Date?,
        commitmentID: UUID?,
        on day: Date
    ) async -> NotificationScheduleOutcome {
        guard request.kind == .actionTime, let fireDate else { return .failed }
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return .notAuthorized
        }
        guard fireDate > day else { return .pastTime }
        let settings = await MainActor.run { AppSettings.shared.notificationSettings }
        let registered = await registerActionTime(
            plannedAt: fireDate,
            now: day,
            settings: settings,
            commitmentID: commitmentID
        )
        return registered ? .scheduled : .failed
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
}
