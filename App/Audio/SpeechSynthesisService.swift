import AVFoundation
import OSLog
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

/// デリゲートの通知 1 件。どの発話のものかを添えて @MainActor へ運ぶ。
private struct SynthesisSignal: Sendable {
    var event: SynthesisEvent
    var utterance: ObjectIdentifier
}

/// `AVSpeechSynthesizerDelegate` は iOS 26 SDK で Sendable。
/// 格納プロパティを Sendable な continuation だけにすることで適合が成立する
/// （Sendable の unchecked 適合は使わない）。
private final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let signals: AsyncStream<SynthesisSignal>.Continuation

    init(signals: AsyncStream<SynthesisSignal>.Continuation) {
        self.signals = signals
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        signals.yield(SynthesisSignal(event: .started, utterance: ObjectIdentifier(utterance)))
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        signals.yield(SynthesisSignal(event: .finished, utterance: ObjectIdentifier(utterance)))
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        signals.yield(SynthesisSignal(event: .cancelled, utterance: ObjectIdentifier(utterance)))
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

    /// いま鳴らしている発話と、その終わりを待っている呼び出し元。
    private struct ActiveUtterance {
        /// 発話そのものを持ち続ける。通知の照合に使う同一性が、別の発話で使い回されないようにする。
        let utterance: AVSpeechUtterance
        var didStart = false
        var waiter: CheckedContinuation<UtteranceEnd, Never>?
    }

    private struct UtteranceEnd: Sendable {
        var lastEvent: String
        var didStart: Bool
    }

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let logger = Logger(subsystem: "com.nonturn.saydo", category: "tts")
    @ObservationIgnored private let delegate: SynthesizerDelegate
    @ObservationIgnored private let signals: AsyncStream<SynthesisSignal>.Continuation
    @ObservationIgnored private var active: ActiveUtterance?
    /// 前の発話が終わるのを待っている `speak()`。
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private weak var sessionController: (any AudioSessionControlling)?
    /// 設定画面で選んだ音声の識別子を返す。発話のたびに読むので、設定変更が次の発話から効く。
    @ObservationIgnored private let voiceIdentifier: @MainActor () -> String?

    init(
        sessionController: (any AudioSessionControlling)? = nil,
        voiceIdentifier: @escaping @MainActor () -> String? = { AppSettings.shared.speechVoiceIdentifier }
    ) {
        self.sessionController = sessionController
        self.voiceIdentifier = voiceIdentifier
        let (incoming, signals) = AsyncStream<SynthesisSignal>.makeStream()
        self.signals = signals
        delegate = SynthesizerDelegate(signals: signals)
        synthesizer.delegate = delegate
        // アプリのオーディオセッション設定（.playAndRecord と経路の override）を使わせる。
        synthesizer.usesApplicationAudioSession = true
        if let voice = Self.preferredJapaneseVoice(identifier: voiceIdentifier()) {
            voiceQuality = SynthesisVoiceQuality(voice.quality)
        } else {
            voiceQuality = .unavailable
        }
        // 通知を受けるのはこの 1 本だけ。`speak()` を呼んだ側のタスクが止められても、通知は取りこぼさない。
        Task { [weak self] in
            for await signal in incoming {
                self?.receive(signal)
            }
        }
    }

    deinit {
        signals.finish()
    }

    func speak(_ text: String, preferReceiver: Bool = false) async {
        guard !text.isEmpty else { return }
        // 発話中に呼ばれたら、前の発話が終わるまで待つ。
        while active != nil {
            await withCheckedContinuation { idleWaiters.append($0) }
        }
        // 待っているあいだに呼び出し元が止められていたら、鳴らさない。
        guard !Task.isCancelled else { return }
        // 発話の直前に出力経路を決める（計画 §7.3 / task_007 scope の最終項）。
        sessionController?.applyOutputRoute(preferReceiver: preferReceiver)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredJapaneseVoice(identifier: voiceIdentifier())
        let identity = ObjectIdentifier(utterance)
        let startedAt = ContinuousClock.now
        active = ActiveUtterance(utterance: utterance)
        synthesizer.speak(utterance)

        // 読み終わり（または中止）の通知まで待つ。待っているタスクが止められたら、音も止める。
        let end = await withTaskCancellationHandler {
            await withCheckedContinuation { active?.waiter = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.abandon(identity)
            }
        }

        let elapsed = ContinuousClock.now - startedAt
        let voiceID = utterance.voice?.identifier ?? "nil"
        if end.didStart {
            logger.info("utterance chars=\(text.count, privacy: .public) end=\(end.lastEvent, privacy: .public) elapsed=\(elapsed, privacy: .public) voice=\(voiceID, privacy: .public)")
        } else {
            logger.error("utterance never started chars=\(text.count, privacy: .public) end=\(end.lastEvent, privacy: .public) elapsed=\(elapsed, privacy: .public) voice=\(voiceID, privacy: .public)")
        }
    }

    /// デリゲートの通知を受ける。いまの発話のものでなければ捨てる
    /// （止めた発話の中止通知が、次の発話の終わりとして数えられないようにする）。
    private func receive(_ signal: SynthesisSignal) {
        guard let current = active, ObjectIdentifier(current.utterance) == signal.utterance else { return }
        switch signal.event {
        case .started:
            active?.didStart = true
            isSpeaking = true
        case .finished:
            end(signal.utterance, lastEvent: "finished")
        case .cancelled:
            end(signal.utterance, lastEvent: "cancelled")
        }
    }

    /// その発話を終わった扱いにし、待っている呼び出し元と、次の発話を待っている呼び出し元を再開する。
    private func end(_ identity: ObjectIdentifier, lastEvent: String) {
        guard let current = active, ObjectIdentifier(current.utterance) == identity else { return }
        active = nil
        isSpeaking = false
        current.waiter?.resume(returning: UtteranceEnd(lastEvent: lastEvent, didStart: current.didStart))
        let waiters = idleWaiters
        idleWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// 待っていた呼び出し元が止められた。その発話がまだ鳴っていれば止める。
    private func abandon(_ identity: ObjectIdentifier) {
        guard let current = active, ObjectIdentifier(current.utterance) == identity else { return }
        synthesizer.stopSpeaking(at: .immediate)
        end(identity, lastEvent: "abandoned")
    }

    /// 読み上げをその場で止める。待っている `speak()` は、中止の通知を待たずにここで返す。
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        if let current = active {
            end(ObjectIdentifier(current.utterance), lastEvent: "stopped")
        }
    }

    // MARK: 音声の選択

    /// 設定で選んだ識別子の音声が端末にあり日本語ならそれを使う（task_013 の音声選択）。
    /// 無ければ enhanced / premium がインストール済みならそれを優先し、それも無ければ既定音声で始める
    /// （fix-decisions P5.8。ダウンロードの案内はオンボーディング側の仕事）。
    static func preferredJapaneseVoice(identifier: String? = nil) -> AVSpeechSynthesisVoice? {
        if let identifier,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier),
           chosen.language.hasPrefix("ja") {
            return chosen
        }
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
        let best = japanese.max {
            SynthesisVoiceQuality($0.quality) < SynthesisVoiceQuality($1.quality)
        }
        return best ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }
}
