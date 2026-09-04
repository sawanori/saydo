import Foundation
import Observation
import OSLog

/// タイムラインの再生（task_012）。同時に鳴るのは 1 件だけ。
///
/// 行の強調は `nowPlayingID` だけで決まる。失敗しても本人には何も掲示せず静かに止める
/// （企画原則 §22-1。再生できない 1 件で責めない）。
@MainActor
@Observable
final class TimelinePlayback {
    /// いま鳴っている `VoiceEntry` の id。鳴っていなければ nil。
    private(set) var nowPlayingID: UUID?

    @ObservationIgnored private let player: any Playing
    /// 相対パス（`yyyy/MM/<uuid>.m4a`）を URL に直すのに使う。
    @ObservationIgnored private var audioFileStore: AudioFileStore?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.nonturn.saydo", category: "timeline")

    init(player: any Playing, audioFileStore: AudioFileStore? = nil) {
        self.player = player
        self.audioFileStore = audioFileStore
    }

    /// 1 件鳴らす。別の行が鳴っていれば先に止める（同時再生の禁止）。
    /// 音声を持たない行（チップだけで答えた日）は何もしない。
    func play(entry: VoiceEntrySnapshot) {
        stop()
        guard let relativePath = entry.audioPath, let store = resolvedStore() else { return }

        let url = store.url(forRelativePath: relativePath)
        nowPlayingID = entry.id
        playbackTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.player.play(url, preferReceiver: false)
            } catch {
                Self.logger.error("timeline playback failed: \(error.localizedDescription, privacy: .public)")
            }
            // 途中で別の行に移った場合は、その行の状態を消さない。
            guard self.nowPlayingID == entry.id else { return }
            self.nowPlayingID = nil
            self.playbackTask = nil
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        nowPlayingID = nil
        player.stop()
    }

    /// 置き場所を開けなければ再生できないというだけ。掲示はしない。
    private func resolvedStore() -> AudioFileStore? {
        if let audioFileStore { return audioFileStore }
        do {
            let store = try AudioFileStore.applicationSupport()
            audioFileStore = store
            return store
        } catch {
            Self.logger.error("audio store unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
