import Foundation
import Observation
import SaydoCore

/// 答える画面の頭脳（実装計画 §17.3「答える」）。
///
/// ボタンのどれかが押されたときにだけ、結果を保存し、アラームを取り消す（実装計画 §17.9 の 3）。
/// 「やった」「今日はやめる」はその日の全部を、「少しやった」「まだ」はその回だけを取り消す。
/// 画面を閉じただけ、声を聞いただけでは取り消さない（答えるまで追う。§17.1-6）。
@MainActor
@Observable
final class FollowUpViewModel {

    enum Phase: Equatable {
        /// 答えのボタンを出している。
        case asking
        /// 保存している。
        case saving
        /// 答え終えた。押した後の 1 行を出している。
        case answered(reply: String)
    }

    // MARK: 公開する状態

    private(set) var phase: Phase = .asking
    /// 本人の声を再生しているか。
    private(set) var isPlayingVoice = false
    /// 保存できなかったときの 1 行。次に押したときに消える。
    private(set) var notice: String?

    /// 約束（本人の言葉のまま）。
    let promiseText: String
    /// 最初のアクション（本人の言葉のまま）。
    let actionText: String
    /// 本人の声のファイル。文字で約束した日、ファイルが無い日は nil（再生ボタンを出さない）。
    let voiceURL: URL?

    var hasVoice: Bool { voiceURL != nil }

    // MARK: 依存

    private let commitment: CommitmentSnapshot
    private let store: any FollowUpStore
    private let chase: ChaseCoordinator
    private let calendar: Calendar
    private let player: any Playing
    private let onClose: @MainActor () -> Void

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    /// 再生の世代。止めた後に前の再生が戻ってきても、新しい再生の表示を倒さないようにする。
    @ObservationIgnored private var playbackGeneration = 0

    /// - Parameters:
    ///   - commitment: 答える約束（`Repository.commitmentAwaitingAnswer(asOf:)` などで取ったもの）。
    ///   - store: 結果を書く先。本番は `RepositoryFollowUpStore(repository)`。
    ///   - chase: アラームの段取り。答えに応じて、その回だけ・その日の全部を取り消す。
    ///   - player: 本人の声の再生。
    ///   - audioFileStore: 声の相対パスを URL に直す。nil なら再生ボタンを出さない。
    ///   - onClose: 画面を閉じるときに呼ぶ。
    init(
        commitment: CommitmentSnapshot,
        store: any FollowUpStore,
        chase: ChaseCoordinator,
        player: any Playing,
        audioFileStore: AudioFileStore?,
        calendar: Calendar = .current,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.commitment = commitment
        self.store = store
        self.chase = chase
        self.calendar = calendar
        self.player = player
        self.onClose = onClose
        self.promiseText = commitment.avoidanceTitle
        self.actionText = commitment.microAction.text
        if let path = commitment.declarationAudioPath,
           let audioFileStore,
           audioFileStore.fileExists(atRelativePath: path) {
            self.voiceURL = audioFileStore.url(forRelativePath: path)
        } else {
            self.voiceURL = nil
        }
    }

    // MARK: - 答える

    /// 答えのボタン。やった = `.done`、少しやった = `.partial`、まだ・今日はやめる = `.notYet`。
    ///
    /// 保存できたときにだけ、アラームを取り消す。保存に失敗したら取り消さず、
    /// 1 行で伝えて、もう一度押せる状態に戻す。押した後の 1 行は、次の回があればその時刻を伝える。
    func answer(_ answer: FollowUpAnswer) async {
        guard phase == .asking else { return }
        phase = .saving
        notice = nil
        stopVoice()

        do {
            try await store.saveOutcome(commitmentID: commitment.id, outcome: answer.outcome)
        } catch {
            notice = PromiseCopy.followUpSaveFailed
            phase = .asking
            return
        }

        let next = await chase.answered(answer, for: commitment)
        phase = .answered(reply: PromiseCopy.reply(for: answer, nextRoundAt: next, calendar: calendar))
    }

    // MARK: - 本人の声

    /// 再生していれば止め、止まっていれば最初から再生する。
    func toggleVoice() {
        if isPlayingVoice {
            stopVoice()
        } else {
            playVoice()
        }
    }

    private func playVoice() {
        guard let voiceURL else { return }
        playbackGeneration += 1
        let generation = playbackGeneration
        isPlayingVoice = true
        playbackTask = Task { [weak self, player] in
            try? await player.play(voiceURL, preferReceiver: false)
            guard let self, self.playbackGeneration == generation else { return }
            self.isPlayingVoice = false
        }
    }

    private func stopVoice() {
        guard isPlayingVoice else { return }
        playbackGeneration += 1
        isPlayingVoice = false
        player.stop()
        playbackTask = nil
    }

    // MARK: - 閉じる

    /// 画面を閉じる。答えていなければ、アラームはそのまま追い続ける。
    func close() {
        stopVoice()
        onClose()
    }
}
