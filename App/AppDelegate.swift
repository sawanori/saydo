import UIKit
import UserNotifications

/// 旧い版が登録した通知のタップをアプリの入口へ渡す口。
///
/// 実体は `AppRouter`。`AppDelegate` はタップかどうかを見分けるところまでを担い、
/// どの画面をどう出すかは知らない（`AppRouter` が起動時と同じ判定で決める。実装計画 §17.3）。
@MainActor
protocol NotificationTapHandling: AnyObject {
    func handleLegacyNotificationTap()
}

/// 通知デリゲート。
///
/// いまの版は通知を登録しない（朝・昼・晩はアラームで追う。実装計画 §17.9）。ここで受けるのは、
/// 旧い版が登録して通知センターに残っている通知の本体のタップだけ。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// タップの受け手。`AppRouter` ができたら `setLauncher(_:)` で注入する。
    private weak var launcher: (any NotificationTapHandling)?

    /// 受け手が注入される前に届いたタップがあったか。
    ///
    /// 通知タップでのコールドスタートでは `didReceive` が画面より先に来るため、
    /// 1 件だけ持っておき、注入時に流す。
    private var hasPendingTap = false

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - 受け手の注入

    /// タップの受け手を差し込む。保留していたタップがあればここで流す。
    func setLauncher(_ launcher: (any NotificationTapHandling)?) {
        self.launcher = launcher
        guard let launcher, hasPendingTap else { return }
        hasPendingTap = false
        launcher.handleLegacyNotificationTap()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 通知が操作されたとき。
    ///
    /// `UNNotificationResponse` は Sendable でないので、この時点で 2 つの識別子（文字列）を
    /// 取り出して判定し、結果（Bool）だけを MainActor に渡す。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isTap = LegacyNotificationTap.isTap(
            actionIdentifier: response.actionIdentifier,
            requestIdentifier: response.notification.request.identifier
        )
        if isTap {
            Task { @MainActor [weak self] in
                self?.handleTap()
            }
        }
        completionHandler()
    }

    // MARK: - 内部

    private func handleTap() {
        guard let launcher else {
            hasPendingTap = true
            return
        }
        launcher.handleLegacyNotificationTap()
    }
}
