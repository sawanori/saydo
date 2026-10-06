import Foundation
import Observation
import SaydoCore

/// 今日の画面の頭脳（実装計画 §17.3「今日」）。
///
/// 約束・アクション・追い始める時刻・結果を 1 枚で見せるための状態と、
/// 「時間を変える」（連鎖アラームの登録し直しと `plannedAt` の更新）、約束の声の再生を持つ。
@MainActor
@Observable
final class TodayViewModel {

    /// 今日の画面の段階。
    enum Stage: Equatable {
        /// 読み込み中。
        case loading
        /// 今日の約束が無い。主ボタンは約束する画面を開く。
        case noPromise
        /// 追い始める前。「◯時から追いかけます」と「時間を変える」。
        case beforeChase
        /// 追い始めた後で、答えがまだ。主ボタンは答える画面を開く。
        case awaitingAnswer
        /// 答えた。結果を見せる。
        case answered
        /// 追い始める時刻を持たない約束（旧い会話で作ったもの）。約束だけ見せる。
        case promiseOnly
    }

    // MARK: 公開する状態

    /// いま扱っている約束。
    private(set) var commitment: CommitmentSnapshot?
    private(set) var hasLoaded = false
    /// 時刻のチップを出しているか。
    private(set) var isChoosingTime = false
    /// いま選べる時刻のチップ（過ぎた枠は出さない）。
    private(set) var timeOptions: [PromiseTimeOption] = []
    /// アラームを登録し直しているか。
    private(set) var isRescheduling = false
    /// 登録し直せなかったときの 1 行。
    private(set) var notice: String?
    /// 約束の声を再生しているか。
    private(set) var isPlayingVoice = false

    var stage: Stage {
        guard hasLoaded else { return .loading }
        guard let commitment else { return .noPromise }
        guard commitment.outcome == .pending else { return .answered }
        guard let start = commitment.plannedAt else { return .promiseOnly }
        return start <= now() ? .awaitingAnswer : .beforeChase
    }

    /// 約束の声を再生できるか（声で約束していて、ファイルが残っている）。
    var hasVoice: Bool { voiceURL != nil }

    // MARK: 依存

    private let repository: Repository
    private let alarms: any AlarmScheduling
    private let player: any Playing
    private let audioFiles: AudioFileStore?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    /// 再生の世代。止めた後に前の再生が戻ってきても、新しい再生の表示を倒さないようにする。
    @ObservationIgnored private var playbackGeneration = 0

    init(
        repository: Repository,
        alarms: any AlarmScheduling,
        player: any Playing,
        audioFiles: AudioFileStore?,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.alarms = alarms
        self.player = player
        self.audioFiles = audioFiles
        self.calendar = calendar
        self.now = now
    }

    // MARK: - 読み込み

    /// 約束を読み直す。画面が出たとき、被せた画面を閉じたとき、前面に戻ったときに呼ぶ。
    func load() async {
        commitment = try? await repository.commitmentInPlay(asOf: now(), calendar: calendar)
        hasLoaded = true
        if stage != .beforeChase {
            isChoosingTime = false
        }
    }

    // MARK: - 時間を変える

    /// 「時間を変える」。いま選べるチップを出す。
    func beginChoosingTime() {
        guard stage == .beforeChase, !isRescheduling else { return }
        timeOptions = PromiseTime.options(now: now(), calendar: calendar)
        notice = nil
        isChoosingTime = true
    }

    /// チップを閉じる。時刻は変えない。
    func cancelChoosingTime() {
        guard !isRescheduling else { return }
        isChoosingTime = false
    }

    /// チップを選んだ。連鎖アラームを新しい時刻で登録し直し、登録できたら `plannedAt` を更新する。
    ///
    /// 登録できなかったときは時刻を変えず、元の時刻の連鎖を登録し直して 1 行で伝える。
    func changeTime(to chip: PromiseChip) async {
        guard stage == .beforeChase, !isRescheduling,
              let commitment, let oldStart = commitment.plannedAt,
              let newStart = PromiseTime.date(for: chip, now: now(), calendar: calendar)
        else { return }
        isRescheduling = true
        notice = nil
        defer {
            isRescheduling = false
            isChoosingTime = false
        }

        let voicePath = commitment.declarationAudioPath
        let outcome = await alarms.scheduleChain(start: newStart, voiceRelativePath: voicePath)
        guard case .scheduled(let count) = outcome, count > 0 else {
            if outcome == .notAuthorized {
                notice = PromiseCopy.completionNotAuthorized
            } else {
                // 登録の途中で、同じ日の元の連鎖は取り消されている。元の時刻で登録し直す。
                _ = await alarms.scheduleChain(start: oldStart, voiceRelativePath: voicePath)
                notice = PromiseCopy.changeTimeUnavailable
            }
            return
        }

        do {
            self.commitment = try await repository.updatePlannedAt(commitmentID: commitment.id, plannedAt: newStart)
        } catch {
            // 時刻を保存できなかった。アラームだけが新しい時刻にならないよう、元に戻す。
            if !calendar.isDate(oldStart, inSameDayAs: newStart) {
                await alarms.cancelChain(startedOn: newStart)
            }
            _ = await alarms.scheduleChain(start: oldStart, voiceRelativePath: voicePath)
            notice = PromiseCopy.changeTimeUnavailable
            return
        }

        // 連鎖の識別子は開始日で決まる。日をまたいで変えたときは、元の日の連鎖が残るので取り消す。
        if !calendar.isDate(oldStart, inSameDayAs: newStart) {
            await alarms.cancelChain(startedOn: oldStart)
        }
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
