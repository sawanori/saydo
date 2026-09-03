import Foundation
import Observation

/// 波形描画のためのレベル履歴。
///
/// `VoiceCapture` の `.level` イベント（= @MainActor に届いた値）だけを受け取る。
/// `installTap` のクロージャからは呼ばない。
@MainActor
@Observable
final class WaveformSampler {
    /// 画面に出すバーの本数。スパイクで使った値をそのまま採用する。
    static let capacity = 80
    /// 正規化の下限。無音のときに 0 除算とノイズの拡大表示を避ける。
    static let normalizationFloor: Float = 0.05

    private(set) var levels: [Float] = []
    private(set) var current: Float = 0
    private(set) var peak: Float = 0

    init() {}

    func append(rms: Float) {
        let value = max(0, rms)
        current = value
        peak = max(peak, value)
        levels.append(value)
        if levels.count > Self.capacity {
            levels.removeFirst(levels.count - Self.capacity)
        }
    }

    /// 0...1 に丸めた描画用の値。基準はこれまでの最大値（下限あり）。
    var normalizedLevels: [Float] {
        let reference = max(peak, Self.normalizationFloor)
        return levels.map { min(1, $0 / reference) }
    }

    func reset() {
        levels.removeAll(keepingCapacity: true)
        current = 0
        peak = 0
    }
}
