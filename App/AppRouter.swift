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
    /// 会話を閉じるたびに増える。`TodayView` を作り直して今日の宣言を読み直すための印。
    private(set) var sessionGeneration = 0

    // MARK: 依存

    let repository: Repository
    /// Today / Timeline の再生に使う共有プレイヤー（同時再生はしない）。
    let sharedPlayer: VoicePlayer
    private let notifications: NotificationScheduler
    /// 会話中の AVAudioSession（.playAndRecord・経路・音量）。会話ごとの音声スタックと共有する。
    private let audioSession: AudioSessionController
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
        let audioSession = AudioSessionController()
        self.audioSession = audioSession
        self.sharedPlayer = VoicePlayer(sessionController: audioSession)
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
        await startManualSession(today == nil ? .morning : .adhoc)
    }

    /// `TodayView` が種類を決めて開く（宣言前は朝、宣言後は手動チェックイン、夜は夜）。
    func startManualSession(_ sessionType: SessionType) async {
        let today = try? await repository.todayCommitment(on: now(), calendar: calendar)
        present(
            SessionRequest(
                sessionType: sessionType,
                commitmentID: today?.id,
                source: .manual
            )
        )
    }

    // MARK: - 起動時の再計画

    /// 起動ごとに今日からの通知計画を作り直す（実装計画 §7.4、task_009 scope）。
    /// 今日の宣言があれば行動時刻と結果を計画に反映する。
    func rescheduleOnLaunch() async {
        let today = try? await repository.todayCommitment(on: now(), calendar: calendar)
        let day = today.map { DayCommitment(plannedAt: $0.plannedAt, outcome: $0.outcome) } ?? .noCommitment
        _ = await notifications.reschedule(
            now: now(),
            settings: settings.notificationSettings,
            today: day,
            commitmentID: today?.id
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
        // 「話せない時を自動で使う時間帯」（task_013）なら最初から選択肢 + テキスト経路で始める。
        await viewModel.start(
            sessionType: request.sessionType,
            microphoneGranted: granted,
            voicelessMode: settings.isQuietMode(at: now())
        )
    }

    /// 会話を閉じる。途中で閉じた場合は中断として保存し、録音と読み上げを止める。
    func dismissSession() {
        if let viewModel = sessionViewModel, viewModel.phase != .done {
            Task { await viewModel.interrupt() }
        }
        activeSession = nil
        sessionViewModel = nil
        hasStartedActiveSession = false
        sessionGeneration += 1
    }

    // MARK: - オンボーディング

    /// オンボーディングを終えた。統合後は `OnboardingView`（task_013）から呼ぶ。
    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        hasCompletedOnboarding = true
    }

    /// 設定の「全削除」で `AppSettings.reset()` が走った後など、保存値から状態を読み直す。
    func reloadOnboardingState() {
        hasCompletedOnboarding = settings.hasCompletedOnboarding
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
            synthesizer: SpeechSynthesisService(sessionController: audioSession),
            capture: VoiceCapture(),
            transcriber: TranscriptionService(),
            player: VoicePlayer(sessionController: audioSession),
            notifications: notifications,
            audioFiles: audioFiles,
            // 再生前の配慮（R8）の判定に使う。渡さないと確認は一度も出ない。
            audioSession: audioSession,
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
