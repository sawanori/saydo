import SwiftUI

// MARK: - 意匠

/// 波形の意匠（`docs/design/design-notes.md`「波形（SwiftUI Canvas 再現用）」）。
///
/// 式は `y(x) = cy − env(u)·A·norm·Σ aᵢ·sin(2π·fᵢ·u + φᵢ + t·ωᵢ)`、`u = x/W`、`norm = 1/Σaᵢ`。
/// 数値は design-notes と `docs/design/Main.dc.html` / `SessionReason.dc.html` の実測値。
/// 色は `SaydoTheme` からしか採らない（HEX を書かない）。
struct WaveformStyle: Equatable {

    /// 1 層ぶんの描き方（bloom → 太線 → 反転線 → 芯 の 4 層）。
    struct Layer: Equatable {
        var lineWidth: CGFloat
        var opacity: Double
        /// 振幅の倍率。反転線は負（`A = −20` を `A = 40` の −0.5 倍として表す）。
        var amplitudeScale: CGFloat
        /// 3.6 秒で呼吸するか（bloom だけ）。
        var breathes: Bool
    }

    /// 設計上の幅。実際の描画は与えられた幅に合わせて伸縮する。
    var width: CGFloat
    var height: CGFloat
    /// 中心線の y（設計上の高さに対する位置）。
    var centerY: CGFloat
    /// 振幅 A。
    var amplitude: CGFloat
    /// 包絡 `exp(−((u−0.5)/spread)²)` の σ。
    var spread: Double
    /// 3 成分の初期位相 φ。
    var phases: [Double]
    var layers: [Layer]

    /// M0（チップの無い質問）。320×132、cy=66、A=40、σ=0.30。
    static let large = WaveformStyle(
        width: 320,
        height: 132,
        centerY: 66,
        amplitude: 40,
        spread: 0.30,
        phases: [0.00, 1.90, 3.40],
        layers: [
            Layer(lineWidth: 19, opacity: 0.09, amplitudeScale: 1, breathes: true),
            Layer(lineWidth: 8, opacity: 0.24, amplitudeScale: 1, breathes: false),
            Layer(lineWidth: 1.4, opacity: 0.20, amplitudeScale: -0.5, breathes: false),
            Layer(lineWidth: 3, opacity: 1.0, amplitudeScale: 1, breathes: false),
        ]
    )

    /// M1 など選択肢がある質問。280×64、cy=32、A=20、σ=0.32、φ をずらす。
    static let compact = WaveformStyle(
        width: 280,
        height: 64,
        centerY: 32,
        amplitude: 20,
        spread: 0.32,
        phases: [2.20, 4.60, 0.80],
        layers: [
            Layer(lineWidth: 11, opacity: 0.08, amplitudeScale: 1, breathes: true),
            Layer(lineWidth: 5, opacity: 0.16, amplitudeScale: 1, breathes: false),
            Layer(lineWidth: 1.0, opacity: 0.16, amplitudeScale: -0.5, breathes: false),
            Layer(lineWidth: 2, opacity: 0.82, amplitudeScale: 1, breathes: false),
        ]
    )

    // MARK: 3 成分（design-notes の `(a, f, φ, ω)`。φ は `phases` が持つ）

    static let componentAmplitudes: [Double] = [1.00, 0.42, 0.18]
    static let componentFrequencies: [Double] = [2.6, 5.7, 11.3]
    /// 位相ドリフト ω（rad/s）。Reduce Motion ではこれを掛ける時刻を止める。
    static let componentDrifts: [Double] = [0.55, -0.90, 1.60]
    /// `norm = 1/Σaᵢ`。
    static let normalization = 1.0 / componentAmplitudes.reduce(0, +)

    /// bloom の呼吸周期（秒）。
    static let breathPeriod = 3.6
    /// bloom の呼吸で振れる不透明度と縦倍率。
    static let breathOpacity: ClosedRange<Double> = 0.055...0.12
    static let breathScale: ClosedRange<CGFloat> = 0.93...1.07

    /// 2px ごとにサンプリングして直線でつなぐ（design-notes の版下と同じ刻み）。
    static let sampleStep: CGFloat = 2

    /// Reduce Motion のときに出す振幅バー。
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 2
}

// MARK: - 描画

/// 聞いている状態の 1 本の生きた線（実装計画 §8）。
///
/// - `Canvas` + `TimelineView(.animation)` で位相をドリフトさせる。
/// - `WaveformSampler` のレベルで振幅を変調する（声が大きいほど大きく振れる）。
/// - Reduce Motion では位相ドリフトを止め、振幅バーに切り替える。
struct WaveformView: View {

    let sampler: WaveformSampler
    var style: WaveformStyle = .large

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // `@Observable` の読み取りは body で行う（Canvas のクロージャの中では追跡されない）。
        let levels = sampler.normalizedLevels
        let gain = Self.gain(for: levels.last)

        Group {
            if reduceMotion {
                Canvas { context, size in
                    drawBars(levels: levels, in: &context, size: size)
                }
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        drawLine(
                            time: timeline.date.timeIntervalSinceReferenceDate,
                            gain: gain,
                            in: &context,
                            size: size
                        )
                    }
                }
            }
        }
        .frame(maxWidth: style.width)
        .frame(height: style.height)
        .accessibilityElement()
        .accessibilityLabel(SessionCopy.waveformLabel)
    }

    // MARK: 線

    private func drawLine(time: TimeInterval, gain: CGFloat, in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height * (style.centerY / style.height)
        let amplitude = style.amplitude * (size.height / style.height) * gain
        let breath = Self.breath(at: time)
        let shading = Self.shading(width: size.width)

        for layer in style.layers {
            let scale = layer.amplitudeScale * (layer.breathes ? Self.breathScale(breath) : 1)
            let path = wavePath(
                time: time,
                centerY: centerY,
                amplitude: amplitude * scale,
                size: size
            )
            // 層ごとの不透明度は色ではなく描画の不透明度で表す（色は SaydoTheme のものだけを使う）。
            var layerContext = context
            layerContext.opacity = layer.breathes ? Self.breathOpacity(breath) : layer.opacity
            layerContext.stroke(
                path,
                with: shading,
                style: StrokeStyle(lineWidth: layer.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    /// `y(x) = cy − env(u)·A·norm·Σ aᵢ·sin(2π·fᵢ·u + φᵢ + t·ωᵢ)`。
    private func wavePath(time: TimeInterval, centerY: CGFloat, amplitude: CGFloat, size: CGSize) -> Path {
        var path = Path()
        var x: CGFloat = 0
        while x <= size.width {
            let u = size.width > 0 ? Double(x / size.width) : 0
            let y = centerY - amplitude * CGFloat(offset(at: u, time: time))
            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
            x += WaveformStyle.sampleStep
        }
        return path
    }

    private func offset(at u: Double, time: TimeInterval) -> Double {
        let envelope = exp(-pow((u - 0.5) / style.spread, 2))
        var sum = 0.0
        for index in WaveformStyle.componentAmplitudes.indices {
            let phase = style.phases.indices.contains(index) ? style.phases[index] : 0
            sum += WaveformStyle.componentAmplitudes[index]
                * sin(2 * .pi * WaveformStyle.componentFrequencies[index] * u
                      + phase
                      + time * WaveformStyle.componentDrifts[index])
        }
        return envelope * sum * WaveformStyle.normalization
    }

    // MARK: 振幅バー（Reduce Motion）

    private func drawBars(levels: [Float], in context: inout GraphicsContext, size: CGSize) {
        let centerY = size.height * (style.centerY / style.height)
        let maxAmplitude = style.amplitude * (size.height / style.height)
        let shading = Self.shading(width: size.width)

        guard !levels.isEmpty else {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: centerY))
            line.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(
                line,
                with: .color(SaydoTheme.Palette.waveformIdle.opacity(0.34)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            return
        }

        let pitch = WaveformStyle.barWidth + WaveformStyle.barSpacing
        let count = max(1, min(levels.count, Int(size.width / pitch)))
        let shown = levels.suffix(count)
        var bars = Path()
        for (index, level) in shown.enumerated() {
            let x = CGFloat(index) * pitch
            let height = max(WaveformStyle.barWidth, CGFloat(level) * maxAmplitude * 2)
            bars.addRoundedRect(
                in: CGRect(
                    x: x,
                    y: centerY - height / 2,
                    width: WaveformStyle.barWidth,
                    height: height
                ),
                cornerSize: CGSize(width: WaveformStyle.barWidth / 2, height: WaveformStyle.barWidth / 2)
            )
        }
        context.fill(bars, with: shading)
    }

    // MARK: 色と呼吸

    /// 横方向のグラデーション。中央だけが温かく、端は地に溶ける（design-notes）。
    ///
    /// 中間色は `SaydoTheme` の 2 色を混ぜて作る（画面ファイルに HEX を書かないため）。
    private static func shading(width: CGFloat) -> GraphicsContext.Shading {
        let idle = SaydoTheme.Palette.waveformIdle
        let accent = SaydoTheme.Palette.accent
        let midCool = idle.mix(with: accent, by: 0.45)
        let midWarm = accent.mix(with: idle, by: 0.18)
        let gradient = Gradient(stops: [
            .init(color: idle.opacity(0.10), location: 0.00),
            .init(color: midCool.opacity(0.44), location: 0.18),
            .init(color: midWarm.opacity(0.88), location: 0.38),
            .init(color: accent, location: 0.50),
            .init(color: midWarm.opacity(0.88), location: 0.62),
            .init(color: midCool.opacity(0.44), location: 0.82),
            .init(color: idle.opacity(0.10), location: 1.00),
        ])
        return .linearGradient(
            gradient,
            startPoint: .zero,
            endPoint: CGPoint(x: width, y: 0)
        )
    }

    /// 0...1 の呼吸位相。
    private static func breath(at time: TimeInterval) -> Double {
        0.5 + 0.5 * sin(2 * .pi * time / WaveformStyle.breathPeriod)
    }

    private static func breathOpacity(_ phase: Double) -> Double {
        let range = WaveformStyle.breathOpacity
        return range.lowerBound + (range.upperBound - range.lowerBound) * phase
    }

    private static func breathScale(_ phase: Double) -> CGFloat {
        let range = WaveformStyle.breathScale
        return range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(phase)
    }

    /// レベルによる振幅の変調。声が無い間も線は生きている（下限 0.55）。
    private static func gain(for level: Float?) -> CGFloat {
        let value = CGFloat(min(1, max(0, level ?? 0)))
        return 0.55 + 0.45 * value
    }
}
