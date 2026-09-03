import SwiftUI
import UIKit
import UserNotifications

@main
struct SpeechSpikeApp: App {
    @UIApplicationDelegateAdaptor(SpikeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            SpikeView()
        }
    }
}

/// 通知タップの時刻をできるだけ早く取るためのデリゲート。
/// `UNUserNotificationCenterDelegate` は @MainActor ではないので、
/// メソッドは nonisolated にして時刻だけ取り、状態変更は @MainActor へ渡す。
final class SpikeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 前面にいる間もバナーを出す（計測のたびにアプリを閉じなくてよいように）
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tappedAt = Date()
        // completionHandler は非 Sendable なのでここで同期的に呼び、Task には渡さない
        completionHandler()
        Task { @MainActor in
            SpikeController.shared.handleNotificationTap(at: tappedAt)
        }
    }
}
