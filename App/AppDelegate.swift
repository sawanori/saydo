import UIKit
import UserNotifications

/// 通知から会話を開始する口。
///
/// 実体は `AppRouter`（未実装）。`AppDelegate` は `DeepLink` を作るところまでを担い、
/// どの画面をどう出すかは知らない。
@MainActor
public protocol SessionLauncher: AnyObject {
    func launch(_ link: DeepLink)
}

/// 通知デリゲート（実装計画 §7.4）。
///
/// - フォアグラウンド受信はバナーだけ。会話が二重に始まらないようにする。
/// - `didReceive` では `actionIdentifier` を見て、既定タップのときだけフローを開始する。
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// 起動要求の受け手。`AppRouter` ができたら `setLauncher(_:)` で注入する。
    private weak var launcher: (any SessionLauncher)?

    /// 受け手が注入される前に届いた起動要求。
    ///
    /// 通知タップでのコールドスタートでは `didReceive` が画面より先に来るため、
    /// 1 件だけ持っておき、注入時に流す。
    private var pendingLink: DeepLink?

    private let scheduler = NotificationScheduler.shared

    // MARK: - UIApplicationDelegate

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        scheduler.registerCategories()
        return true
    }

    // MARK: - 受け手の注入

    /// 起動要求の受け手を差し込む。保留していた要求があればここで流す。
    func setLauncher(_ launcher: (any SessionLauncher)?) {
        self.launcher = launcher
        guard let launcher, let link = pendingLink else { return }
        pendingLink = nil
        launcher.launch(link)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// アプリ表示中に通知が届いたときの見せ方。
    ///
    /// バナーだけを出す。音を鳴らすと TTS と重なり、通知センターに積むと
    /// あとからタップされて会話が二重に始まる（check_022）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    /// 通知が操作されたとき。
    ///
    /// `UNNotificationResponse` は Sendable でないので、この時点で `DeepLink`
    /// （Sendable な値型）へ落としてから MainActor に渡す。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let link = DeepLink(response: response)
        Task { @MainActor [weak self] in
            self?.handle(link)
        }
        completionHandler()
    }

    // MARK: - 内部

    /// 起動要求を処理する。
    ///
    /// - スワイプで消しただけ（`link == nil`）のときは何もしない。
    /// - 「今日は休む」のときは当日の残りの保留通知を取り消してから受け手へ渡す。
    ///   休みを記録に残すかどうかは受け手の担当（`Commitment` は作らない）。
    private func handle(_ link: DeepLink?) {
        guard let link else { return }

        if link.action == .rest {
            let scheduler = self.scheduler
            Task { @MainActor in
                await scheduler.cancelRemainingToday()
            }
        }

        guard let launcher else {
            pendingLink = link
            return
        }
        launcher.launch(link)
    }
}
