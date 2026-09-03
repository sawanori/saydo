import AVFoundation
import Foundation
import Observation

// MARK: - 値型

enum PlaybackFault: Error, Sendable, Equatable {
    case fileUnreadable(String)
    case decodeFailed
    case startFailed
}

/// デリゲートから @MainActor へ運ぶ唯一の型。
private enum PlaybackEvent: Sendable {
    case finished(successfully: Bool)
    case decodeError
}

// MARK: - プロトコル

@MainActor
protocol Playing: AnyObject {
    var isPlaying: Bool { get }
    var currentURL: URL? { get }

    /// 再生が終わるまで待つ。朝の宣言音声を行動時刻に返すのに使う（企画原則 10）。
    func play(_ url: URL, preferReceiver: Bool) async throws
    func stop()
}

// MARK: - デリゲート

/// `AVAudioPlayerDelegate` は iOS 26 SDK で Sendable。
/// 格納プロパティを Sendable な continuation だけにして適合させる。
private final class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let events: AsyncStream<PlaybackEvent>.Continuation

    init(events: AsyncStream<PlaybackEvent>.Continuation) {
        self.events = events
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        events.yield(.finished(successfully: flag))
        events.finish()
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        events.yield(.decodeError)
        events.finish()
    }
}

// MARK: - 実装

/// 録音した .m4a の再生。完了まで await できる。
@MainActor
@Observable
final class VoicePlayer: Playing {
    private(set) var isPlaying = false
    private(set) var currentURL: URL?
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var delegate: PlayerDelegate?
    @ObservationIgnored private var continuation: AsyncStream<PlaybackEvent>.Continuation?
    @ObservationIgnored private weak var sessionController: (any AudioSessionControlling)?

    init(sessionController: (any AudioSessionControlling)? = nil) {
        self.sessionController = sessionController
    }

    func play(_ url: URL, preferReceiver: Bool = false) async throws {
        stop()
        // 再生の直前に出力経路を決める（計画 §7.3 / task_007 scope の最終項）。
        sessionController?.applyOutputRoute(preferReceiver: preferReceiver)

        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(contentsOf: url)
        } catch {
            throw PlaybackFault.fileUnreadable(error.localizedDescription)
        }

        let (events, continuation) = AsyncStream<PlaybackEvent>.makeStream()
        let delegate = PlayerDelegate(events: continuation)
        player.delegate = delegate
        self.player = player
        self.delegate = delegate
        self.continuation = continuation

        guard player.play() else {
            cleanUp()
            throw PlaybackFault.startFailed
        }
        isPlaying = true
        currentURL = url
        duration = player.duration

        var fault: PlaybackFault?
        for await event in events {
            switch event {
            case .finished:
                break
            case .decodeError:
                fault = .decodeFailed
            }
        }
        cleanUp()
        if let fault { throw fault }
    }

    func stop() {
        player?.stop()
        // 待っている side を確実に起こしてから片付ける。
        continuation?.finish()
        cleanUp()
    }

    private func cleanUp() {
        player?.delegate = nil
        player = nil
        delegate = nil
        continuation = nil
        isPlaying = false
    }
}
