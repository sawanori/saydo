import OSLog
import SwiftData
import SwiftUI

@main
struct SaydoApp: App {
    /// 通知デリゲート。旧い版が登録した通知のタップを受けるので、起動時から必ず生かす。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private static let logger = Logger(subsystem: "com.nonturn.saydo", category: "startup")

    private let modelContainer: ModelContainer
    /// 開いたときに何を出すか。`AppDelegate` が受けた旧い通知のタップはここへ流す。
    private let router: AppRouter

    init() {
        let (container, isPersistent) = Self.makeModelContainer()
        modelContainer = container
        #if DEBUG
        // 試験用の短縮（task_058）。回の時刻を「いまから数分後」に差し替える起動引数を読む。
        DebugRounds.applyLaunchArguments(ProcessInfo.processInfo.arguments, defaults: .standard, now: .now)
        #endif
        router = AppRouter(modelContainer: container)
        if Self.shouldSweepOrphanAudio(isPersistent: isPersistent) {
            Task { await Self.sweepOrphanAudioFiles(in: container) }
        } else {
            // 空のメモリ内ストアを基準にすると、端末上の全録音が孤児として消えてしまう。
            Self.logger.error("orphan audio sweep skipped: running on in-memory store")
        }
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

    /// 保存先が開けない場合もアプリは立ち上げる。約束だけは声にできる方が、
    /// 起動できないより本人の役に立つ（記録はその起動の間だけ残る）。
    /// 戻り値の `isPersistent` は、永続ストアで開けたかどうか（メモリ内ストアなら false）。
    private static func makeModelContainer() -> (container: ModelContainer, isPersistent: Bool) {
        do {
            return (try SaydoModelContainer.make(), true)
        } catch {
            logger.error("persistent store unavailable: \(error.localizedDescription, privacy: .public)")
        }
        do {
            return (try SaydoModelContainer.make(inMemory: true), false)
        } catch {
            fatalError("SwiftData container could not be created: \(error)")
        }
    }

    /// 孤児ファイルの掃除をしてよいか。永続ストアで開けた起動だけ true。
    /// メモリ内ストアは `VoiceEntry` が空なので、掃除すると端末上の全録音が消える。
    nonisolated static func shouldSweepOrphanAudio(isPersistent: Bool) -> Bool {
        isPersistent
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
