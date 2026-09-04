import SwiftUI
import UIKit
import SaydoCore

// MARK: - 折り返す本文

extension View {
    /// 折り返す和文に当てる質問の書体。`saydoText(.question)` の代わりに使う。
    ///
    /// iOS 26.2 SDK の SwiftUI では、`tracking` を当てた和文が幅に余裕があっても
    /// 早い位置で折り返し、末尾が「…」で切れる（iPhone 17 シミュレータで実測。
    /// 幅を明示しても、`fixedSize` を付けても直らない。`docs/PROGRESS.md` の
    /// task_008-ui エントリに証拠あり）。字送り以外は `SaydoTheme` の値をそのまま使う。
    ///
    /// 1 行しか出ない短いラベル（状態行・ロゴ・セクションラベル）は `saydoText` のままでよい。
    func saydoWrappingQuestion() -> some View {
        font(SaydoTheme.TextRole.question.font)
            .lineSpacing(SaydoTheme.TextRole.question.lineSpacing)
            .foregroundStyle(SaydoTheme.TextRole.question.color)
    }
}

/// 会話画面（実装計画 §8、意匠は `docs/design/Main.dc.html` / `SessionReason.dc.html`）。
///
/// 吹き出し・履歴・進捗率・チェックボックスは作らない（企画原則 §22-8）。
/// 画面にあるのは上から順に、ロゴ / 1 行の質問 / 波形 / 状態行 / （あれば）チップ、
/// そして右下のキーボードボタンと「話せない時」トグルだけ。
///
/// 会話の開始（`SessionViewModel.start`）は `AppRouter` が担う。この View は
/// 状態を映して入力を返すだけで、フローの判断をしない。
struct SessionView: View {

    let viewModel: SessionViewModel
    /// 会話を閉じる。`AppRouter.dismissSession()` を渡す。
    let onClose: () -> Void

    @State private var isTextSheetPresented = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            conversation
            // 会話が始まった最初のフレームから置く（実装計画 §8）。
            assistBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saydoGround()
        .sheet(isPresented: $isTextSheetPresented) {
            TextFallbackSheet(viewModel: viewModel)
        }
    }

    // MARK: - 会話

    private var conversation: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: Layout.minimumGap)
            question
            Spacer(minLength: Layout.minimumGap)
            WaveformView(sampler: viewModel.waveform, style: waveformStyle)
            statusLine
            avoidanceLine
            examplesLine
            chips
            playbackLine
            closing
            Spacer(minLength: Layout.minimumGap)
        }
        .padding(.horizontal, Layout.sideMargin)
        .padding(.top, Layout.topMargin)
        .padding(.bottom, Layout.assistBarReserve)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Layout.blockSpacing) {
            Text(SessionCopy.logo)
                .saydoText(.logo)
                .frame(maxWidth: .infinity, alignment: .leading)
            micDeniedNotice
        }
    }

    /// マイクが使えない日の掲示。会話はテキストで続く（fix-decisions P2.3）。
    @ViewBuilder
    private var micDeniedNotice: some View {
        if viewModel.notice == .micDenied {
            VStack(alignment: .leading, spacing: Layout.tightSpacing) {
                Text(SessionCopy.micDeniedNotice)
                    .saydoText(.list)
                    .fixedSize(horizontal: false, vertical: true)
                Button(SessionCopy.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.plain)
                .saydoText(.list)
                .foregroundStyle(SaydoTheme.Palette.accent)
            }
            .padding(Layout.noticePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                    .fill(SaydoTheme.Palette.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                    .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
            )
        }
    }

    /// いま読み上げている（読み上げ終えた）1 行。
    private var question: some View {
        Text(viewModel.spokenLine)
            .saydoWrappingQuestion()
            .multilineTextAlignment(.center)
            .lineLimit(Layout.questionLineLimit)
            .minimumScaleFactor(Layout.questionMinimumScale)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    /// チップが出ている質問では波形を小さくする（design-notes の M1）。
    private var waveformStyle: WaveformStyle {
        viewModel.choices.isEmpty ? .large : .compact
    }

    /// 「聞いています…」は 2.8 秒で呼吸する（opacity 0.5 ↔ 1.0）。
    ///
    /// 時刻から直に不透明度を出す（状態を持って `repeatForever` を仕掛けると、
    /// 聞き終わったあとも呼吸が止まらないため）。Reduce Motion では止める。
    @ViewBuilder
    private var statusLine: some View {
        if let status = SessionCopy.status(for: viewModel.phase) {
            Group {
                if shouldBreathe {
                    TimelineView(.animation) { timeline in
                        Text(status)
                            .saydoText(.status)
                            .opacity(Self.breathOpacity(at: timeline.date))
                    }
                } else {
                    Text(status).saydoText(.status)
                }
            }
            .padding(.top, Layout.blockSpacing)
        }
    }

    private var shouldBreathe: Bool {
        !reduceMotion && viewModel.phase == .listening
    }

    private static func breathOpacity(at date: Date) -> Double {
        let phase = 0.5 + 0.5 * sin(2 * .pi * date.timeIntervalSinceReferenceDate / Layout.breathPeriod)
        return Layout.breathLow + (1 - Layout.breathLow) * phase
    }

    /// M0 の文字起こし 1 行と、1 タップの録り直し（retention R7）。
    @ViewBuilder
    private var avoidanceLine: some View {
        if !viewModel.avoidanceTranscript.isEmpty {
            VStack(spacing: Layout.tightSpacing) {
                Text(viewModel.avoidanceTranscript)
                    .saydoText(.list)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if viewModel.canRetakeAvoidance {
                    Button(SessionCopy.retakeAvoidance) {
                        Task { await viewModel.retakeAvoidance() }
                    }
                    .buttonStyle(.plain)
                    .saydoText(.time)
                    .foregroundStyle(SaydoTheme.Palette.accent)
                }
            }
            .padding(.top, Layout.blockSpacing)
        }
    }

    /// 答えに詰まったときの例示。チップではないので押せない（実装計画 §7.2）。
    @ViewBuilder
    private var examplesLine: some View {
        if !viewModel.examples.isEmpty {
            Text(viewModel.examples.map(\.label).joined(separator: SessionCopy.exampleSeparator))
                .saydoText(.list)
                .foregroundStyle(SaydoTheme.Palette.ink3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.blockSpacing)
        }
    }

    @ViewBuilder
    private var chips: some View {
        if !viewModel.choices.isEmpty {
            ChoiceChipsView(choices: viewModel.choices) { choice in
                Task { await viewModel.select(choice) }
            }
            .padding(.top, Layout.chipsTopSpacing)
        }
    }

    /// 昼 N0。統合時にここへ `PlaybackCardView`（task_010 / エージェント F）を差し込む。
    /// いまは「声なし」の日の宣言テキストを大きく出す最小表示にとどめる。
    @ViewBuilder
    private var playbackLine: some View {
        if viewModel.phase == .playback, let declaration = declarationText {
            Text(declaration)
                .saydoWrappingQuestion()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Layout.blockSpacing)
                .accessibilityLabel(SessionCopy.declarationLabel)
        }
    }

    private var declarationText: String? {
        let text = viewModel.declarationTextToShow ?? viewModel.commitment?.declarationTranscript
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    @ViewBuilder
    private var closing: some View {
        if viewModel.phase == .done, let completion = viewModel.completion {
            VStack(spacing: Layout.blockSpacing) {
                Text(SessionCopy.closing(for: completion))
                    .saydoText(.list)
                Button(action: onClose) {
                    Text(SessionCopy.close)
                        .saydoText(.list)
                        .frame(height: SaydoTheme.Metric.chipHeight)
                        .padding(.horizontal, Layout.closeButtonPadding)
                        .background(
                            RoundedRectangle(
                                cornerRadius: SaydoTheme.Metric.chipCornerRadius,
                                style: .continuous
                            )
                            .fill(SaydoTheme.Palette.chipFill)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, Layout.chipsTopSpacing)
        }
    }

    // MARK: - 右下の補助（常時）

    private var assistBar: some View {
        HStack(alignment: .center) {
            Button(action: switchToTextMode) {
                Text(SessionCopy.voicelessToggle)
                    .saydoText(.status)
                    .foregroundStyle(
                        viewModel.isVoiceless ? SaydoTheme.Palette.accent : SaydoTheme.Palette.ink3
                    )
                    .frame(height: SaydoTheme.Metric.keyboardButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionCopy.voicelessToggle)

            Spacer(minLength: 0)

            Button {
                switchToTextMode()
                isTextSheetPresented = true
            } label: {
                Image(systemName: Layout.keyboardSymbol)
                    .font(.system(size: Layout.keyboardGlyphSize, weight: .light))
                    .foregroundStyle(SaydoTheme.Palette.ink3)
                    .frame(
                        width: SaydoTheme.Metric.keyboardButtonSize,
                        height: SaydoTheme.Metric.keyboardButtonSize
                    )
                    .background(
                        RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                            .fill(SaydoTheme.Palette.chipFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                            .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionCopy.keyboardButton)
        }
        .padding(.horizontal, Layout.assistBarMargin)
        .padding(.bottom, Layout.assistBarBottom)
    }

    /// 読み上げを即座に止め、以降を選択肢 + テキスト経路に切り替える（実装計画 §8）。
    private func switchToTextMode() {
        Task { await viewModel.switchToTextMode() }
    }

    // MARK: - 寸法（docs/design/Main.dc.html の実測値）

    private enum Layout {
        static let sideMargin: CGFloat = 30
        static let topMargin: CGFloat = 24
        static let minimumGap: CGFloat = 12
        static let blockSpacing: CGFloat = 12
        static let tightSpacing: CGFloat = 6
        static let chipsTopSpacing: CGFloat = 24
        static let noticePadding: CGFloat = 16
        static let closeButtonPadding: CGFloat = 24
        static let questionLineLimit = 3
        static let questionMinimumScale: CGFloat = 0.6
        /// 「聞いています…」の呼吸（2.8 秒で 0.5 ↔ 1.0）。
        static let breathPeriod: TimeInterval = 2.8
        static let breathLow: Double = 0.5
        /// 下部の補助バーぶんの余白。
        static let assistBarReserve: CGFloat = 96
        static let assistBarMargin: CGFloat = 20
        static let assistBarBottom: CGFloat = 34
        static let keyboardGlyphSize: CGFloat = 20
        static let keyboardSymbol = "keyboard"
    }
}
