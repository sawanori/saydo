import SwiftUI

@main
struct SaydoApp: App {
    /// 通知デリゲート（実装計画 §7.4）。通知が唯一の入口なので、起動時から必ず生かす。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("SAYDO")
        }
    }
}
