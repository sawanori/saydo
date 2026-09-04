import SaydoCore
import SwiftUI

/// 昼 N0「朝のあなたからです。」の画面（実装計画 §7.2 / docs/design/Playback.dc.html）。
///
/// 象徴体験そのもの（企画原則 §22-10）。本人の宣言音声を本人に返し、宣言テキストは
/// 常に画面に出す。「声なし」の日は音の代わりにテキストを大きく出す（fix-decisions P2.3）。
/// 進捗バーは置かない（タスク管理アプリにしない。§22-8）。
struct PlaybackCardView: View {

    private let viewModel: SessionViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: SessionViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(preface)
                .saydoText(.preface)
                .foregroundStyle(SaydoTheme.Palette.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 24)

            ribbon
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Spacer(minLength: 24)

            declarationText

            Spacer(minLength: 24)

            listenButtons
        }
        .padding(.horizontal, 30)
    }

    // MARK: 前置き

    /// 「朝のあなたからです。」。読み上げ済みならその 1 行、まだなら文言の先頭を出す
    /// （「文字で読む」を選んだ日は読み上げないので、その場合もこちらを使う）。
    private var preface: String {
        if viewModel.currentStep == .noonPlayback, !viewModel.spokenLine.isEmpty {
            return viewModel.spokenLine
        }
        return DialogueCopy.variants(.noonIntro).first?.text ?? ""
    }

    // MARK: 再生リボン

    @ViewBuilder
    private var ribbon: some View {
        if reduceMotion || viewModel.declarationPlaybackStartedAt == nil {
            DeclarationRibbon(progress: viewModel.declarationPlaybackStartedAt == nil ? 0 : 1)
        } else {
            TimelineView(.animation) { timeline in
                DeclarationRibbon(progress: progress(at: timeline.date))
            }
        }
    }

    private func progress(at date: Date) -> Double {
        guard let started = viewModel.declarationPlaybackStartedAt,
              viewModel.declarationDurationSec > 0
        else { return 0 }
        return min(1, max(0, date.timeIntervalSince(started) / viewModel.declarationDurationSec))
    }

    // MARK: 宣言テキスト

    /// 宣言テキストは常に出す。声で残していない日は、これが本人の言葉そのものなので大きく出す。
    @ViewBuilder
    private var declarationText: some View {
        let text = viewModel.declarationTextToShow ?? viewModel.commitment?.declarationTranscript ?? ""
        if !text.isEmpty {
            Text(text)
                .saydoText(viewModel.declarationTextToShow == nil ? .declaration : .question)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: 聞き方

    /// 「聞く」と「耳に当てて聞く」を並べる。塗り無し・高さ 46・ヘアラインの区切り。
    private var listenButtons: some View {
        HStack(spacing: 0) {
            listenButton(PlaybackCopy.listenAloud, systemImage: "play") {
                await viewModel.replayDeclaration(preferReceiver: false)
            }
            Rectangle()
                .fill(SaydoTheme.Palette.hairline)
                .frame(width: 1, height: 22)
            listenButton(PlaybackCopy.listenAtEar, systemImage: "ear") {
                await viewModel.replayDeclaration(preferReceiver: true)
            }
        }
        .opacity(viewModel.commitment?.declarationAudioPath == nil ? 0 : 1)
        // 声で残していない日は鳴らすものが無いので、押せる要素を出さない。
        .allowsHitTesting(viewModel.commitment?.declarationAudioPath != nil)
    }

    private func listenButton(
        _ label: String,
        systemImage: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.footnote)
                Text(label)
                    .saydoText(.status)
                    .tracking(0.56)
            }
            .foregroundStyle(SaydoTheme.Palette.ink3)
            .frame(maxWidth: .infinity)
            .frame(height: SaydoTheme.Metric.chipHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 再生リボン

/// 上下対称のリボンで「録音済みの声」を表す（docs/design/design-notes.md「再生波形（N0）」）。
///
/// 再生済みの区間はアクセント、未再生は静かな線。再生位置に縦線を 1 本引く。
/// 進捗バーは置かない。
struct DeclarationRibbon: View {

    /// 再生位置（0...1）。
    var progress: Double

    /// 版下の座標系。実寸はこの比率で拡縮する。
    private static let designSize = CGSize(width: 340, height: 150)
    private static let amplitude: Double = 40
    /// 3 つの山 = 3 つの語句。
    private static let envelope: [(center: Double, width: Double, weight: Double)] = [
        (0.18, 0.10, 0.55), (0.46, 0.13, 1.00), (0.78, 0.11, 0.72),
    ]
    private static let components: [(amplitude: Double, frequency: Double, phase: Double)] = [
        (1.00, 7.0, 0.6), (0.55, 15.0, 2.7), (0.25, 27.0, 5.1),
    ]
    private static let normalization = 1 / components.reduce(0) { $0 + $1.amplitude }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let clamped = min(1, max(0, progress))
            let samples = max(2, Int(size.width))

            for mirrored in [false, true] {
                let points = Self.points(in: size, samples: samples, mirrored: mirrored)
                let split = Int((Double(samples - 1) * clamped).rounded())

                if split < samples - 1 {
                    let idle = Self.path(points, from: split, to: samples - 1)
                    context.stroke(
                        idle,
                        with: .color(SaydoTheme.Palette.waveformIdle.opacity(0.34)),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }
                if split > 0 {
                    let played = Self.path(points, from: 0, to: split)
                    // bloom → 中間 → 芯 の 3 層。芯だけがはっきり見える。
                    for layer in [(9.0, 0.11), (4.5, 0.15), (2.5, 1.0)] {
                        context.stroke(
                            played,
                            with: .color(SaydoTheme.Palette.accent.opacity(layer.1)),
                            style: StrokeStyle(lineWidth: layer.0, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }

            guard clamped > 0 else { return }
            let x = size.width * clamped
            let half = size.height * (39 / Self.designSize.height)
            var head = Path()
            head.move(to: CGPoint(x: x, y: size.height / 2 - half))
            head.addLine(to: CGPoint(x: x, y: size.height / 2 + half))
            context.stroke(
                head,
                with: .color(SaydoTheme.Palette.accentHighlight.opacity(0.65)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
        }
        .aspectRatio(Self.designSize.width / Self.designSize.height, contentMode: .fit)
    }

    // MARK: 形

    /// `y(x) = cy ∓ env(u)·A·norm·Σ aᵢ·sin(2π·fᵢ·u + φᵢ)`（design-notes）。
    private static func points(in size: CGSize, samples: Int, mirrored: Bool) -> [CGPoint] {
        let scale = size.height / designSize.height
        let centerY = size.height / 2
        return (0..<samples).map { index in
            let u = Double(index) / Double(samples - 1)
            let sum = components.reduce(0.0) { partial, component in
                partial + component.amplitude * sin(2 * .pi * component.frequency * u + component.phase)
            }
            let offset = envelopeValue(u) * amplitude * normalization * sum * scale
            return CGPoint(x: size.width * u, y: centerY + (mirrored ? offset : -offset))
        }
    }

    private static func envelopeValue(_ u: Double) -> Double {
        let sum = envelope.reduce(0.0) { partial, hill in
            let z = (u - hill.center) / hill.width
            return partial + hill.weight * exp(-z * z)
        }
        return min(1, sum)
    }

    private static func path(_ points: [CGPoint], from start: Int, to end: Int) -> Path {
        var path = Path()
        guard start < end, points.indices.contains(start), points.indices.contains(end) else { return path }
        path.move(to: points[start])
        for index in (start + 1)...end {
            path.addLine(to: points[index])
        }
        return path
    }
}
