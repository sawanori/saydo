import Foundation
import Observation
import SaydoCore

/// 今日の画面の頭脳（実装計画 §17.3「今日」/ §17.9）。
///
/// 約束・アクション・これから追う回の時刻・結果を 1 枚で見せるための状態と、約束の声の再生を持つ。
/// 追う時刻は朝・昼・晩の決まった時刻なので、ここからは変えられない（設定で変える）。
@MainActor
@Observable
final class TodayViewModel {

    /// 今日の画面の段階。
    enum Stage: Equatable {
        /// 読み込み中。
        case loading
        /// 今日の約束が無い。主ボタンは約束する画面を開く。
        case noPromise
        /// これから追う回がある（いま答えを待っている回は無い）。「次は◯時に追いかけます」。
        case beforeChase
        /// すでに始まっている回のうち、まだ答えていない回がある。主ボタンは答える画面を開く。
        case awaitingAnswer
        /// その日の後追いを終えた。結果を見せる。
        case answered
    }

    // MARK: 公開する状態

    /// いま扱っている約束。
    private(set) var commitment: CommitmentSnapshot?
    private(set) var hasLoaded = false
    /// 約束の声を再生しているか。
    private(set) var isPlayingVoice = false
    /// 読み込んだ時点の規則（回の時刻と、どの回まで答えたか）。
    private var rules: ChaseRules?

    var stage: Stage {
        guard hasLoaded, let rules else { return .loading }
        guard let commitment else { return .noPromise }
        let moment = now()
        if rules.isAwaitingAnswer(commitment, asOf: moment) { return .awaitingAnswer }
        return rules.nextRound(for: commitment, after: moment) == nil ? .answered : .beforeChase
    }

    /// これから追う回の時刻。無ければ nil。
    var nextRoundAt: Date? {
        guard let commitment, let rules else { return nil }
        return rules.nextRound(for: commitment, after: now())?.start
    }

    /// いま答えを待っている回のうち、いちばん早く始まった回の時刻。
    var chasingSince: Date? {
        guard let commitment, let rules else { return nil }
        return rules.awaitingRounds(for: commitment, asOf: now()).first?.start
    }

    /// 約束の声を再生できるか（声で約束していて、ファイルが残っている）。
    var hasVoice: Bool { voiceURL != nil }

    // MARK: 依存

    private let repository: Repository
    private let chase: ChaseCoordinator
    private let player: any Playing
    private let audioFiles: AudioFileStore?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    /// 再生の世代。止めた後に前の再生が戻ってきても、新しい再生の表示を倒さないようにする。
    @ObservationIgnored private var playbackGeneration = 0

    init(
        repository: Repository,
        chase: ChaseCoordinator,
        player: any Playing,
        audioFiles: AudioFileStore?,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.chase = chase
        self.player = player
        self.audioFiles = audioFiles
        self.calendar = calendar
        self.now = now
    }

    // MARK: - 読み込み

    /// 約束を読み直す。画面が出たとき、被せた画面を閉じたとき、前面に戻ったときに呼ぶ。
    func load() async {
        let rules = chase.rules
        commitment = try? await repository.commitmentInPlay(asOf: now(), rules: rules)
        self.rules = rules
        hasLoaded = true
    }

    // MARK: - 約束の声

    private var voiceURL: URL? {
        guard let path = commitment?.declarationAudioPath, let audioFiles,
              audioFiles.fileExists(atRelativePath: path) else { return nil }
        return audioFiles.url(forRelativePath: path)
    }

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

    /// 再生を止める。画面が隠れるときにも呼ぶ。
    func stopVoice() {
        guard isPlayingVoice else { return }
        playbackGeneration += 1
        isPlayingVoice = false
        player.stop()
        playbackTask = nil
    }
}
