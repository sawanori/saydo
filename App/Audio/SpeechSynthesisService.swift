import AVFoundation
import Foundation
import Observation

// MARK: - 値型

/// デリゲートから @MainActor へ運ぶ唯一の型。
enum SynthesisEvent: Sendable {
    case started
    case finished
    case cancelled
}

/// ja-JP 音声の品質。オンボーディングで高品質音声のダウンロードを案内するかの判断に使う
/// （fix-decisions P5.8）。
enum SynthesisVoiceQuality: Int, Sendable, Comparable {
    case unavailable = 0
    case standard = 1
    case enhanced = 2
    case premium = 3

    static func < (lhs: SynthesisVoiceQuality, rhs: SynthesisVoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(_ quality: AVSpeechSynthesisVoiceQuality) {
        switch quality {
        case .premium: self = .premium
        case .enhanced: self = .enhanced
        case .default: self = .standard
        @unknown default: self = .standard
        }
    }
}

// MARK: - プロトコル

@MainActor
protocol Synthesizing: AnyObject {
    var isSpeaking: Bool { get }
    /// enhanced 以上の ja-JP 音声が端末に入っているか。
    var hasHighQualityJapaneseVoice: Bool { get }
    var voiceQuality: SynthesisVoiceQuality { get }

    /// 読み終わるまで待つ。半二重のため、呼び出し側はこれが返ってから聞き取りを始める。
    func speak(_ text: String, preferReceiver: Bool) async
    func stop()
}

// MARK: - デリゲート

/// `AVSpeechSynthesizerDelegate` は iOS 26 SDK で Sendable。
/// 格納プロパティを Sendable な continuation だけにすることで適合が成立する
/// （Sendable の unchecked 適合は使わない）。
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let events: AsyncStream<SynthesisEvent>.Continuation

    init(events: AsyncStream<SynthesisEvent>.Continuation) {
        self.events = events
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        events.yield(.started)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        events.yield(.finished)
        events.finish()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        events.yield(.cancelled)
        events.finish()
    }
}

// MARK: - 実装

/// ja-JP の読み上げ。発話完了を async で待てるようにして半二重を成立させる（計画 §7.3）。
@MainActor
@Observable
final class SpeechSynthesisService: Synthesizing {
    private(set) var isSpeaking = false
    private(set) var voiceQuality: SynthesisVoiceQuality = .unavailable

    var hasHighQualityJapaneseVoice: Bool { voiceQuality >= .enhanced }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var delegate: SynthesizerDelegate?
    @ObservationIgnored private weak var sessionController: (any AudioSessionControlling)?

    init(sessionController: (any AudioSessionControlling)? = nil) {
        self.sessionController = sessionController
        // アプリのオーディオセッション設定（.playAndRecord と経路の override）を使わせる。
        synthesizer.usesApplicationAudioSession = true
        voiceQuality = SynthesisVoiceQuality(Self.preferredJapaneseVoice()?.quality ?? .default)
        if Self.preferredJapaneseVoice() == nil {
            voiceQuality = .unavailable
        }
    }

    func speak(_ text: String, preferReceiver: Bool = false) async {
        guard !text.isEmpty else { return }
        // 発話の直前に出力経路を決める（計画 §7.3 / task_007 scope の最終項）。
        sessionController?.applyOutputRoute(preferReceiver: preferReceiver)

        let (events, continuation) = AsyncStream<SynthesisEvent>.makeStream()
        let delegate = SynthesizerDelegate(events: continuation)
        self.delegate = delegate
        synthesizer.delegate = delegate

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredJapaneseVoice()
        synthesizer.speak(utterance)

        for await event in events {
            switch event {
            case .started:
                isSpeaking = true
            case .finished, .cancelled:
                isSpeaking = false
            }
        }
        isSpeaking = false
        self.delegate = nil
        synthesizer.delegate = nil
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: 音声の選択

    /// enhanced / premium がインストール済みならそれを優先し、無ければ既定音声で始める
    /// （fix-decisions P5.8。ダウンロードの案内はオンボーディング側の仕事）。
    static func preferredJapaneseVoice() -> AVSpeechSynthesisVoice? {
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
        let best = japanese.max {
            SynthesisVoiceQuality($0.quality) < SynthesisVoiceQuality($1.quality)
        }
        return best ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }
}
