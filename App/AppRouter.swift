import AVFoundation
import Foundation
import Observation
import OSLog
import SwiftData
import SaydoCore

/// どの会話をどこから開くか（実装計画 §7.4 / §8）。
///
/// 通知タップは `AppDelegate` → `SessionLauncher.launch(_:)` で、手動は「今話す」から入る。
/// 画面の出し方は `RootView` が決め、この型は「いま開くべき会話」と、その会話の
/// `SessionViewModel` を持つだけにする。
@MainActor
@Observable
final class AppRouter: SessionLauncher {

    /// いま開いている会話。
    struct SessionRequest: Identifiable, Equatable {
        enum Source: Equatable {
            case notification
            case manual
        }

        let id = UUID()
        var sessionType: SessionType
        var commitmentID: UUID?
        var source: Source
    }

    // MARK: 公開する状態

    private(set) var activeSession: SessionRequest?
    /// 会話画面が読む頭脳。`beginSession()` で作る（音声スタックの実体を持つ）。
    private(set) var sessionViewModel: SessionViewModel?
    /// オンボーディングを終えているか。`RootView` の分岐に使う。
    private(set) var hasCompletedOnboarding: Bool

    // MARK: 依存

    private let repository: Repository
    private let notifications: NotificationScheduler
    private let settings: AppSettings
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let logger = Logger(subsystem: "com.nonturn.saydo", category: "router")

    /// 保存先が開けず、一時ディレクトリに録音するしかない状態か。
    /// この日は音声を残せないのでテキスト経路で始める（会話は諦めない）。
    private var isAudioStorageDegraded = false
    private var hasStartedActiveSession = false

    init(
        modelContainer: ModelContainer,
        notifications: NotificationScheduler = .shared,
        settings: AppSettings = .shared,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = Repository(modelContainer: modelContainer)
        self.notifications = notifications
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.hasCompletedOnboarding = settings.hasCompletedOnboarding
    }

    // MARK: - 通知から開く

    /// `AppDelegate` から来る起動要求（`SessionLauncher`）。
    ///
    /// - `.open`（通知本体のタップ）だけが会話を開く。
    /// - `.rest`（「今日は休む」）は `AppDelegate` が当日の保留通知を取り消し済みなので、
    ///   ここでは何もしない。会話を開かないことが「休む」の意味（retention R3）。
    /// - 将来増える操作（「今は話せない」など）も、開くと決めるまでは無視する。
    func launch(_ link: DeepLink) {
        guard link.action == .open else { return }
        present(
            SessionRequest(
                sessionType: link.sessionType,
                commitmentID: link.commitmentID,
                source: .notification
            )
        )
    }

    // MARK: - 手動で開く

    /// 「今話す」から開く。今日の宣言がまだ無ければ朝、あれば手動チェックイン。
    func startManualSession() async {
        let today = try? await repository.todayCommitment(on: now(), calendar: calendar)
        present(
            SessionRequest(
                sessionType: today == nil ? .morning : .adhoc,
                commitmentID: today?.id,
                source: .manual
            )
        )
    }

    // MARK: - 開始と終了

    /// 会話画面が出た直後に呼ぶ。マイクの許可を確かめてから読み上げを始める。
    ///
    /// 起動から 1.5 秒以内に TTS を始めるため、余計な待ちを入れない。
    func beginSession() async {
        guard let request = activeSession, !hasStartedActiveSession else { return }
        hasStartedActiveSession = true

        let viewModel = makeSessionViewModel()
        sessionViewModel = viewModel

        let granted = isAudioStorageDegraded ? false : await Self.microphonePermission()
        await viewModel.start(sessionType: request.sessionType, microphoneGranted: granted)
    }

    /// 会話を閉じる。途中で閉じた場合は中断として保存し、録音と読み上げを止める。
    func dismissSession() {
        if let viewModel = sessionViewModel, viewModel.phase != .done {
            Task { await viewModel.interrupt() }
        }
        activeSession = nil
        sessionViewModel = nil
        hasStartedActiveSession = false
    }

    // MARK: - オンボーディング

    /// オンボーディングを終えた。統合後は `OnboardingView`（task_013）から呼ぶ。
    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        hasCompletedOnboarding = true
    }

    // MARK: - 内部

    private func present(_ request: SessionRequest) {
        // 会話中に別の通知が来たら、いまの会話を中断してから開き直す。
        if activeSession != nil {
            dismissSession()
        }
        activeSession = request
        hasStartedActiveSession = false
    }

    /// 音声スタックと保存を束ねた `SessionViewModel` を作る。
    ///
    /// 保存先が開けない場合でも会話は諦めず、一時ディレクトリに落としてテキスト経路で始める。
    private func makeSessionViewModel() -> SessionViewModel {
        let audioFiles = audioFileStore()
        return SessionViewModel(
            store: RepositorySessionStore(repository),
            synthesizer: SpeechSynthesisService(),
            capture: VoiceCapture(),
            transcriber: TranscriptionService(),
            player: VoicePlayer(),
            notifications: notifications,
            audioFiles: audioFiles,
            calendar: calendar,
            now: now
        )
    }

    private func audioFileStore() -> AudioFileStore {
        do {
            let store = try AudioFileStore.applicationSupport()
            isAudioStorageDegraded = false
            return store
        } catch {
            logger.error("audio storage unavailable: \(error.localizedDescription, privacy: .public)")
            isAudioStorageDegraded = true
            return AudioFileStore(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appending(path: "SaydoAudio", directoryHint: .isDirectory)
            )
        }
    }

    /// マイクの許可。未決定なら 1 回だけ要求する。
    ///
    /// 拒否されていても会話は開く（テキストで完走できる。fix-decisions P2.3）。
    private static func microphonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}
