import Foundation
import Observation
import SaydoCore

/// 答える画面の頭脳（実装計画 §17.3「答える」）。
///
/// 3 つのボタンのどれかが押されたときにだけ、結果を保存し、その日の連鎖アラームをすべて取り消す。
/// 画面を閉じただけ、声を聞いただけでは取り消さない（答えるまで追う。§17.1-6）。
@MainActor
@Observable
final class FollowUpViewModel {

    enum Phase: Equatable {
        /// 3 つのボタンを出している。
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
    private let alarms: any AlarmScheduling
    private let player: any Playing
    private let onClose: @MainActor () -> Void

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    /// 再生の世代。止めた後に前の再生が戻ってきても、新しい再生の表示を倒さないようにする。
    @ObservationIgnored private var playbackGeneration = 0

    /// - Parameters:
    ///   - commitment: 答える約束（`Repository.commitmentAwaitingAnswer(asOf:)` などで取ったもの）。
    ///   - store: 結果を書く先。本番は `RepositoryFollowUpStore(repository)`。
    ///   - alarms: 連鎖アラームの入口。本番は `AlarmScheduler(audioFileStore:)`。
    ///   - player: 本人の声の再生。
    ///   - audioFileStore: 声の相対パスを URL に直す。nil なら再生ボタンを出さない。
    ///   - onClose: 画面を閉じるときに呼ぶ。
    init(
        commitment: CommitmentSnapshot,
        store: any FollowUpStore,
        alarms: any AlarmScheduling,
        player: any Playing,
        audioFileStore: AudioFileStore?,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.commitment = commitment
        self.store = store
        self.alarms = alarms
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

    /// 3 つのボタン。やった = `.done`、少しやった = `.partial`、今日はやめる = `.notYet`。
    ///
    /// 保存できたときにだけ、その日のアラームを取り消す。保存に失敗したら取り消さず、
    /// 1 行で伝えて、もう一度押せる状態に戻す。
    func answer(_ outcome: CommitmentOutcome) async {
        guard phase == .asking, let reply = PromiseCopy.reply(for: outcome) else { return }
        phase = .saving
        notice = nil
        stopVoice()

        do {
            try await store.saveOutcome(commitmentID: commitment.id, outcome: outcome)
        } catch {
            notice = PromiseCopy.followUpSaveFailed
            phase = .asking
            return
        }

        await alarms.cancelChain(startedOn: FollowUpRule.chainStart(of: commitment))
        phase = .answered(reply: reply)
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
