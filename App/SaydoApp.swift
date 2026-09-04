import OSLog
import SwiftData
import SwiftUI

@main
struct SaydoApp: App {
    /// 通知デリゲート（実装計画 §7.4）。通知が唯一の入口なので、起動時から必ず生かす。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let logger = Logger(subsystem: "com.nonturn.saydo", category: "startup")

    private let modelContainer: ModelContainer
    /// どの会話をどこから開くか。`AppDelegate` の起動要求はここへ流す。
    private let router: AppRouter

    init() {
        let container = Self.makeModelContainer()
        modelContainer = container
        router = AppRouter(modelContainer: container)
        Task { await Self.sweepOrphanAudioFiles(in: container) }
    }

    var body: some Scene {
        WindowGroup {
            RootView(router: router)
                // `@UIApplicationDelegateAdaptor` の値は `init` では取れないので、
                // 最初のフレームで注入する。それより前に届いた通知は `AppDelegate` が
                // `pendingLink` に 1 件だけ持っていて、ここで流れる。
                .onAppear { appDelegate.setLauncher(router) }
        }
        .modelContainer(modelContainer)
    }

    /// 保存先が開けない場合もアプリは立ち上げる。会話だけは始められる方が、
    /// 起動できないより本人の役に立つ（記録はその起動の間だけ残る）。
    private static func makeModelContainer() -> ModelContainer {
        do {
            return try SaydoModelContainer.make()
        } catch {
            logger.error("persistent store unavailable: \(error.localizedDescription, privacy: .public)")
        }
        do {
            return try SaydoModelContainer.make(inMemory: true)
        } catch {
            fatalError("SwiftData container could not be created: \(error)")
        }
    }

    /// 起動時に 1 回だけ孤児ファイルを掃除する（実装計画 §10）。
    private static func sweepOrphanAudioFiles(in container: ModelContainer) async {
        do {
            let removed = try await Repository(modelContainer: container).sweepOrphanAudioFiles()
            if !removed.isEmpty {
                logger.info("removed \(removed.count, privacy: .public) orphan audio files")
            }
        } catch {
            logger.error("orphan sweep failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
