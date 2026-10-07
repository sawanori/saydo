import AVFoundation
import Foundation
import Observation
import OSLog
import SwiftData
import SaydoCore

/// 旧い版が登録した通知の後始末の入口。`AppRouter` が使うぶんだけを切り出してある。
///
/// 約束を促す朝の 1 通は、朝の回のアラームに置き換えた（実装計画 §17.9 の 5）。通知はもう登録しない。
@MainActor
protocol PendingNotificationClearing: AnyObject {
    /// このアプリが登録した保留中の通知を、すべて取り消す。
    func removeAllManagedPending() async
}

extension NotificationScheduler: PendingNotificationClearing {}

/// 開いたときに何を出すか（実装計画 §17.3）。
///
/// 起動時・前面に戻ったとき・アラームの「開く」・通知のタップは、すべて同じ判定
/// （`destination(...)`）を通る。画面の出し方は `RootView` が決め、この型は「いま被せる画面」
/// （`cover`）と、その画面の頭脳の組み立てだけを持つ。
@MainActor
@Observable
final class AppRouter: NotificationTapHandling {

    /// 判定の結果。
    enum Destination: Equatable {
        /// オンボーディングが済んでいない。
        case onboarding
        /// 始まっている回の答えがまだ（または「開く」の合図があった）。答える画面を全画面で出す。
        case followUp(CommitmentSnapshot)
        /// 今日の約束が無い（朝の回が鳴っている日は、閉じた後でも）。約束する画面を全画面で出す。
        case promise
        /// 今日の画面。
        case today
    }

    /// 今日の画面の上に全画面で被せる画面。
    enum Cover: Equatable, Identifiable {
        /// 約束する画面。`token` は開くたびに変わる（開き直したら新しい画面にする）。
        case promise(token: UUID)
        /// 答える画面。
        case followUp(CommitmentSnapshot)

        var id: String {
            switch self {
            case .promise(let token): "promise-\(token.uuidString)"
            case .followUp(let commitment): "followUp-\(commitment.id.uuidString)"
            }
        }
    }

    // MARK: 公開する状態

    /// いま被せている画面。無ければ今日の画面が見えている。
    private(set) var cover: Cover?
    /// オンボーディングを終えているか。`RootView` の分岐に使う。
    private(set) var hasCompletedOnboarding: Bool
    /// 起動してから 1 回でも判定を終えたか。終えるまで `RootView` は今日の画面を見せない
    /// （約束する画面の前に今日の画面が一瞬見えるのを避ける）。
    private(set) var hasResolvedEntry = false
    /// 被せた画面を閉じるたびに増える。`TodayView` が約束を読み直すための印。
    private(set) var generation = 0

    // MARK: 依存

    let repository: Repository
    /// Today / Timeline / 答える画面の再生に使う共有プレイヤー（同時再生はしない）。
    let sharedPlayer: VoicePlayer
    /// アラームの入口。オンボーディングの許可に使う。
    let alarms: any AlarmScheduling
    /// 朝・昼・晩の 3 回で追う段取り。約束する画面・答える画面・今日の画面で共有する。
    let chase: ChaseCoordinator
    /// 録音の置き場所。保存先が開けない端末では一時ディレクトリになる。
    let audioFiles: AudioFileStore
    private let notifications: any PendingNotificationClearing
    /// 録音中の AVAudioSession。約束する画面と再生で共有する。
    private let audioSession: AudioSessionController
    private let settings: AppSettings
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private static let logger = Logger(subsystem: "com.nonturn.saydo", category: "router")

    init(
        modelContainer: ModelContainer,
        notifications: (any PendingNotificationClearing)? = nil,
        alarms: (any AlarmScheduling)? = nil,
        audioFiles: AudioFileStore? = nil,
        settings: AppSettings = .shared,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let repository = Repository(modelContainer: modelContainer)
        self.repository = repository
        let audioSession = AudioSessionController()
        self.audioSession = audioSession
        self.sharedPlayer = VoicePlayer(sessionController: audioSession)
        let files = audioFiles ?? Self.defaultAudioFileStore()
        self.audioFiles = files
        let scheduler = alarms ?? AlarmScheduler(audioFileStore: files)
        self.alarms = scheduler
        self.chase = ChaseCoordinator(
            alarms: scheduler,
            settings: settings,
            calendar: calendar,
            now: now,
            commitmentOn: { day in try? await repository.todayCommitment(on: day, calendar: calendar) }
        )
        self.notifications = notifications ?? NotificationScheduler.shared
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.hasCompletedOnboarding = settings.hasCompletedOnboarding
    }

    // MARK: - 判定

    /// 開いたときに出す画面を決める（純粋な判定。実装計画 §17.3 / §17.9）。
    ///
    /// - Parameters:
    ///   - openRequested: アラームの「開く」の合図があったか。
    ///   - awaiting: 始まっている回の答えがまだの約束（`Repository.commitmentAwaitingAnswer`）。
    ///   - inPlay: いま扱っている約束（`Repository.commitmentInPlay`）。無ければ今日は約束できる。
    ///   - inPlayHasRoundsLeft: その約束に、まだ答えていない回が残っているか。
    ///   - promiseDismissedToday: その日に本人が約束する画面を閉じたか。
    ///   - morningPromptDue: 約束の無い朝の回が始まっていて、「今日はやめる」とも答えていないか。
    nonisolated static func destination(
        hasCompletedOnboarding: Bool,
        openRequested: Bool,
        awaiting: CommitmentSnapshot?,
        inPlay: CommitmentSnapshot?,
        inPlayHasRoundsLeft: Bool,
        promiseDismissedToday: Bool,
        morningPromptDue: Bool
    ) -> Destination {
        guard hasCompletedOnboarding else { return .onboarding }
        if let awaiting { return .followUp(awaiting) }
        // 「開く」はアラームが鳴ったから押せる。時計のずれで「始まっている回」に入らなくても、
        // まだ答えていない回が残っている約束があれば答える画面を出す。
        if openRequested, let inPlay, inPlayHasRoundsLeft {
            return .followUp(inPlay)
        }
        // 約束が無い日。朝の回が鳴っている間と「開く」の合図は、閉じた後でも約束する画面を出す。
        if inPlay == nil, !promiseDismissedToday || openRequested || morningPromptDue { return .promise }
        return .today
    }

    /// 起動時・前面に戻ったとき・「開く」の合図・通知のタップで呼ぶ。判定して `cover` に反映する。
    ///
    /// - Parameters:
    ///   - openRequested: アラームの「開く」の合図があったか（`FollowUpOpenRequest.consume()`）。
    ///   - ignoringDismissal: その日に約束する画面を閉じていても、約束が無ければ出す
    ///     （通知をタップしたとき、オンボーディングを終えたとき）。
    @discardableResult
    func resolveEntry(openRequested: Bool = false, ignoringDismissal: Bool = false) async -> Destination {
        await resolveEntry(
            hasCompletedOnboarding: hasCompletedOnboarding,
            openRequested: openRequested,
            ignoringDismissal: ignoringDismissal
        )
    }

    private func resolveEntry(
        hasCompletedOnboarding: Bool,
        openRequested: Bool,
        ignoringDismissal: Bool
    ) async -> Destination {
        let moment = now()
        let rules = chase.rules
        let awaiting = try? await repository.commitmentAwaitingAnswer(asOf: moment, rules: rules)
        let inPlay = try? await repository.commitmentInPlay(asOf: moment, rules: rules)
        let dismissedToday = settings.promiseDismissedDayKey == DayKey.make(from: moment, calendar: calendar)
        let destination = Self.destination(
            hasCompletedOnboarding: hasCompletedOnboarding,
            openRequested: openRequested,
            awaiting: awaiting,
            inPlay: inPlay,
            inPlayHasRoundsLeft: inPlay.map { !rules.pendingRounds(for: $0).isEmpty } ?? false,
            promiseDismissedToday: dismissedToday && !ignoringDismissal,
            morningPromptDue: rules.isMorningPromptDue(asOf: moment)
        )
        apply(destination)
        hasResolvedEntry = true
        Self.logger.info("entry resolved: \(Self.name(of: destination), privacy: .public) open=\(openRequested, privacy: .public)")
        return destination
    }

    /// 判定を `cover` に反映する。すでに同じ画面を出していれば、作り直さない（入力の途中を壊さない）。
    private func apply(_ destination: Destination) {
        switch destination {
        case .onboarding:
            cover = nil
        case .followUp(let commitment):
            if case .followUp(let current) = cover, current.id == commitment.id { return }
            cover = .followUp(commitment)
        case .promise:
            if case .promise = cover { return }
            cover = .promise(token: UUID())
        case .today:
            // 今日の画面でよい判定のときに、開いている画面を勝手に閉じない
            // （本人が今日の画面から開いた約束する画面、答え終えた 1 行を出している答える画面）。
            break
        }
    }

    private static func name(of destination: Destination) -> String {
        switch destination {
        case .onboarding: "onboarding"
        case .followUp: "followUp"
        case .promise: "promise"
        case .today: "today"
        }
    }

    // MARK: - 通知から開く

    /// `AppDelegate` から来るタップ（`NotificationTapHandling`）。旧い版が登録した通知の本体のタップ。
    ///
    /// 開くのは旧い会話ではなく、起動時と同じ判定（約束が無ければ約束する画面、答えがまだなら答える画面）。
    func handleLegacyNotificationTap() {
        Task { await openFromLegacyNotification() }
    }

    /// `handleLegacyNotificationTap()` の中身。テストから待てるように分けてある。
    func openFromLegacyNotification() async {
        guard hasCompletedOnboarding else { return }
        await resolveEntry(ignoringDismissal: true)
    }

    // MARK: - 今日の画面から開く

    /// 今日の画面の主ボタン（約束が無い日）。約束する画面を開く。
    func openPromise() {
        if case .promise = cover { return }
        cover = .promise(token: UUID())
    }

    /// 今日の画面の主ボタン（答えがまだの日）。答える画面を開く。
    func openFollowUp(for commitment: CommitmentSnapshot) {
        cover = .followUp(commitment)
    }

    // MARK: - 閉じる

    /// 約束する画面を閉じた（「閉じる」「今日はやめる」、または完了の 1 行を出し終えた）。
    ///
    /// その日は、起動のたびに約束する画面を出し直さない（朝の回が鳴っている間は別。
    /// 約束するか「今日はやめる」と答えるまで、開くたびに出る。実装計画 §17.9 の 5）。
    func closePromise() async {
        guard case .promise = cover else { return }
        settings.promiseDismissedDayKey = DayKey.make(from: now(), calendar: calendar)
        cover = nil
        generation += 1
    }

    /// 答える画面を閉じた。答えていなければ、アラームはそのまま追い続ける。
    func closeFollowUp() {
        guard case .followUp = cover else { return }
        cover = nil
        generation += 1
    }

    // MARK: - アラームの登録し直し

    /// 起動・前面復帰・設定の変更のたびに、今日と翌日の回を登録し直す（実装計画 §17.9 の 6）。
    ///
    /// 約束を促す朝の 1 通は朝の回のアラームに置き換えたので、通知は登録しない。
    /// 旧い版が登録した保留中の通知は、ここで取り消す。
    func refreshAlarms() async {
        await notifications.removeAllManagedPending()
        await chase.refresh()
    }

    // MARK: - オンボーディング

    /// オンボーディングを終えた。約束が無ければ、そのまま約束する画面が出る。
    func completeOnboarding() async {
        settings.hasCompletedOnboarding = true
        // 先に被せる画面を決めてから切り替える（今日の画面が一瞬見えるのを避ける）。
        _ = await resolveEntry(hasCompletedOnboarding: true, openRequested: false, ignoringDismissal: true)
        hasCompletedOnboarding = true
    }

    /// 設定の「全削除」で `AppSettings.reset()` が走った後など、保存値から状態を読み直す。
    ///
    /// 全削除の後は約束が残っていないので、鳴り続けるアラームに答える先が無くなる。
    /// このアプリのアラームをここですべて取り消す。
    func reloadOnboardingState() {
        hasCompletedOnboarding = settings.hasCompletedOnboarding
        guard !hasCompletedOnboarding else { return }
        cover = nil
        let chase = self.chase
        Task { await chase.cancelEverything() }
    }

    // MARK: - 画面の頭脳の組み立て

    /// 約束する画面の頭脳。録音・文字起こしの実体を持つので、画面を出すときに 1 回だけ作る。
    func makePromiseViewModel() -> PromiseViewModel {
        PromiseViewModel(
            store: RepositoryPromiseStore(repository, calendar: calendar),
            capture: VoiceCapture(),
            transcriber: TranscriptionService(),
            chase: chase,
            audioFiles: audioFiles,
            audioSession: audioSession,
            calendar: calendar,
            now: now
        )
    }

    /// 答える画面の頭脳。
    func makeFollowUpViewModel(for commitment: CommitmentSnapshot) -> FollowUpViewModel {
        FollowUpViewModel(
            commitment: commitment,
            store: RepositoryFollowUpStore(repository),
            chase: chase,
            player: sharedPlayer,
            audioFileStore: audioFiles,
            calendar: calendar,
            onClose: { [weak self] in self?.closeFollowUp() }
        )
    }

    /// 今日の画面の頭脳。
    func makeTodayViewModel() -> TodayViewModel {
        TodayViewModel(
            repository: repository,
            chase: chase,
            player: sharedPlayer,
            audioFiles: audioFiles,
            calendar: calendar,
            now: now
        )
    }

    // MARK: - 内部

    /// 本番の録音の置き場所。開けない端末では一時ディレクトリに落とす（約束は諦めない）。
    private static func defaultAudioFileStore() -> AudioFileStore {
        do {
            return try AudioFileStore.applicationSupport()
        } catch {
            logger.error("audio storage unavailable: \(error.localizedDescription, privacy: .public)")
            return AudioFileStore(
                rootDirectory: FileManager.default.temporaryDirectory
                    .appending(path: "SaydoAudio", directoryHint: .isDirectory)
            )
        }
    }

    /// マイクの許可。未決定なら 1 回だけ要求する。
    ///
    /// 拒否されていても約束する画面は開く（文字で約束できる。実装計画 §17.8-4）。
    static func microphonePermission() async -> Bool {
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
