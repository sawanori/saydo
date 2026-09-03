import Foundation

/// 無音で発話終了とみなすまでの秒数（計画 §7.3。設定画面で選ばせる 3 択）。
enum SilenceDuration: Double, CaseIterable, Sendable, Codable {
    case short = 1.2
    case standard = 1.5
    case long = 2.0

    var seconds: TimeInterval { rawValue }
}

/// RMS の列から「話し終わった」を判定する純ロジック。
///
/// 音声フレームワークに一切依存しないので、そのままユニットテストできる
/// （`Tests/SaydoTests/SilenceDetectorTests.swift`）。
/// `installTap` のクロージャからは呼ばない。RMS は値として @MainActor へ渡り、
/// この構造体の更新も @MainActor 側だけで行う（計画 §7.3 / fix-decisions P4.6）。
struct SilenceDetector: Sendable, Equatable {
    /// この値未満を無音とみなす（RMS。実機で調整する前提の初期値）。
    var threshold: Float
    /// この秒数だけ無音が続いたら発話終了。
    var requiredSilence: TimeInterval

    private(set) var silentSeconds: TimeInterval = 0
    private(set) var hasHeardSpeech = false

    static let defaultThreshold: Float = 0.015

    init(requiredSilence: TimeInterval, threshold: Float = SilenceDetector.defaultThreshold) {
        self.requiredSilence = requiredSilence
        self.threshold = threshold
    }

    init(duration: SilenceDuration, threshold: Float = SilenceDetector.defaultThreshold) {
        self.init(requiredSilence: duration.seconds, threshold: threshold)
    }

    /// 1 バッファぶんの RMS を食わせる。戻り値 true で「発話が終わった」。
    /// 話し始める前の無音は数えない（読み上げ直後の間で切らないため）。
    mutating func feed(rms: Float, duration: TimeInterval) -> Bool {
        guard duration > 0 else { return false }
        if rms >= threshold {
            hasHeardSpeech = true
            silentSeconds = 0
            return false
        }
        guard hasHeardSpeech else { return false }
        silentSeconds += duration
        return silentSeconds >= requiredSilence
    }

    /// 無音ゲージの進み具合（0...1）。UI の「もうすぐ切れる」表示に使う。
    var progress: Double {
        guard requiredSilence > 0 else { return 0 }
        return min(1, silentSeconds / requiredSilence)
    }

    /// 発話終了の条件を満たしているか（`feed` を呼ばずに現在値だけ見る）。
    var hasFinished: Bool {
        hasHeardSpeech && silentSeconds >= requiredSilence
    }

    mutating func reset() {
        silentSeconds = 0
        hasHeardSpeech = false
    }
}
