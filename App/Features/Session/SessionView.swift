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
/// 画面にあるのは上から順に、ロゴ / 1 行の質問 / 波形 / 状態行 / （あれば）チップと答えの例 /
/// （文字で答える間だけ）入力欄、そして右下のキーボードボタンと左下の「声を出さない」だけ。
///
/// 会話の開始（`SessionViewModel.start`）は `AppRouter` が担う。この View は
/// 状態を映して入力を返すだけで、フローの判断をしない。
struct SessionView: View {

    let viewModel: SessionViewModel
    /// 会話を閉じる。`AppRouter.dismissSession()` を渡す。
    let onClose: () -> Void

    /// 入力欄にフォーカスがあるか。
    @FocusState private var isTextFieldFocused: Bool
    /// キーボードのボタンを押した。入力欄が出たら、そのままキーボードを上げる。
    @State private var focusesFieldWhenItAppears = false
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
        // 再生前の配慮（retention R8）。イヤホン未接続で音量が大きいとき、音を出す前に聞き方を選ばせる。
        .sheet(isPresented: listenModePrompt) {
            ListenModeSheet { mode in
                Task { await viewModel.chooseListenMode(mode) }
            }
            .interactiveDismissDisabled()
        }
    }

    private var listenModePrompt: Binding<Bool> {
        Binding(get: { viewModel.listenModePrompt }, set: { _ in })
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
            chips
            exampleChips
            textAnswer
            skipButton
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
            closeButton
            Text(SessionCopy.logo)
                .saydoText(.logo)
                .frame(maxWidth: .infinity, alignment: .leading)
            micDeniedNotice
        }
    }

    /// 左上の「閉じる」。会話のどの段階でも出し、1 タップで閉じる（task_037）。
    /// 控えめな見た目のまま、タップ領域は 44pt 以上にする。
    private var closeButton: some View {
        Button(action: onClose) {
            Text(SessionCopy.close)
                .saydoText(.status)
                .foregroundStyle(SaydoTheme.Palette.ink3)
                .frame(
                    minWidth: SaydoTheme.Metric.minimumTapTarget,
                    minHeight: SaydoTheme.Metric.minimumTapTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SessionCopy.closeAccessibilityLabel)
    }

    /// マイクが使えない日、または声を始められなかった質問の掲示。会話は文字で続く（fix-decisions P2.3）。
    /// 設定を開く導線は、マイクが拒否されているときだけ出す。
    @ViewBuilder
    private var micDeniedNotice: some View {
        if viewModel.notice == .micDenied || viewModel.notice == .captureFailed {
            VStack(alignment: .leading, spacing: Layout.tightSpacing) {
                Text(viewModel.notice == .micDenied ? SessionCopy.micDeniedNotice : SessionCopy.captureFailedNotice)
                    .saydoText(.list)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.notice == .micDenied {
                    Button(SessionCopy.openSettings) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .saydoText(.list)
                    .foregroundStyle(SaydoTheme.Palette.accent)
                }
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

    /// チップや答えの例が出ている質問では波形を小さくする（design-notes の M1）。
    private var waveformStyle: WaveformStyle {
        viewModel.choices.isEmpty && viewModel.examples.isEmpty ? .large : .compact
    }

    /// 「聞いています…」は 2.8 秒で呼吸する（opacity 0.5 ↔ 1.0）。
    ///
    /// 時刻から直に不透明度を出す（状態を持って `repeatForever` を仕掛けると、
    /// 聞き終わったあとも呼吸が止まらないため）。Reduce Motion では止める。
    @ViewBuilder
    private var statusLine: some View {
        if let status = SessionCopy.status(for: viewModel.phase, awaitsText: viewModel.acceptsTextInput) {
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

    /// 呼吸するのは声を聞いている間だけ。文字の入力待ちでは動かさない。
    private var shouldBreathe: Bool {
        !reduceMotion && viewModel.phase == .listening && !viewModel.acceptsTextInput
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

    @ViewBuilder
    private var chips: some View {
        if !viewModel.choices.isEmpty {
            ChoiceChipsView(choices: viewModel.choices) { choice in
                Task { await viewModel.select(choice) }
            }
            .padding(.top, Layout.chipsTopSpacing)
        }
    }

    /// 答えの例。押すと、その文言が答えになる（実装計画 §16.8）。
    @ViewBuilder
    private var exampleChips: some View {
        if !viewModel.examples.isEmpty {
            ChoiceChipsView(choices: viewModel.examples) { choice in
                Task { await viewModel.select(choice) }
            }
            .padding(.top, viewModel.choices.isEmpty ? Layout.chipsTopSpacing : Layout.blockSpacing)
        }
    }

    /// 文字の答えの入力欄。「声を出さない」の間は出たままになり、その質問だけ文字で答える場合と、
    /// アプリが文字に落とした質問では、その質問の間だけ出る。
    @ViewBuilder
    private var textAnswer: some View {
        if viewModel.showsTextField {
            TextAnswerField(
                acceptsAnswer: viewModel.acceptsTextInput,
                isFocused: $isTextFieldFocused
            ) { answer in
                Task { await viewModel.submit(text: answer) }
            }
            .padding(.top, Layout.blockSpacing)
            .onAppear {
                guard focusesFieldWhenItAppears else { return }
                focusesFieldWhenItAppears = false
                isTextFieldFocused = true
            }
        }
    }

    /// スキップ。必須でない質問（理由・時刻）にだけ、入力欄の下に控えめに出す。
    @ViewBuilder
    private var skipButton: some View {
        if viewModel.canSkip {
            Button {
                Task { await viewModel.skip() }
            } label: {
                Text(SessionCopy.skip)
                    .saydoText(.status)
                    .foregroundStyle(SaydoTheme.Palette.ink3)
                    .frame(
                        minWidth: SaydoTheme.Metric.minimumTapTarget,
                        minHeight: SaydoTheme.Metric.minimumTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(SessionCopy.skipAccessibilityLabel)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// 昼 N0（task_010）。宣言音声の再生リボンと宣言テキスト。「声なし」の日はテキストを大きく出す。
    @ViewBuilder
    private var playbackLine: some View {
        if viewModel.phase == .playback {
            PlaybackCardView(viewModel: viewModel)
                .padding(.top, Layout.blockSpacing)
        }
    }

    @ViewBuilder
    private var closing: some View {
        if viewModel.phase == .done, let completion = viewModel.completion {
            VStack(spacing: Layout.blockSpacing) {
                Text(SessionCopy.closing(for: completion))
                    .saydoText(.list)
                if viewModel.declarationRetakeFailed {
                    Text(SessionCopy.declarationRetakeKept)
                        .saydoText(.list)
                        .foregroundStyle(SaydoTheme.Palette.ink3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                declarationActions
            }
            .padding(.top, Layout.chipsTopSpacing)
        }
    }

    /// 完了画面の「聞いてみる」と「言い直す」（task_038）。主ボタンは「閉じる」のままにし、
    /// この 2 つは控えめに置く。押さなければタップは増えない（企画原則 §22-2）。
    @ViewBuilder
    private var declarationActions: some View {
        if viewModel.canPreviewDeclaration {
            HStack(spacing: Layout.declarationActionSpacing) {
                declarationAction(
                    viewModel.isPreviewingDeclaration
                        ? SessionCopy.stopDeclarationPreview
                        : SessionCopy.previewDeclaration,
                    accessibilityLabel: viewModel.isPreviewingDeclaration
                        ? SessionCopy.stopDeclarationPreviewAccessibilityLabel
                        : SessionCopy.previewDeclarationAccessibilityLabel
                ) {
                    Task { await viewModel.playDeclarationPreview() }
                }
                if viewModel.canRetakeDeclaration {
                    declarationAction(
                        SessionCopy.retakeDeclaration,
                        accessibilityLabel: SessionCopy.retakeDeclarationAccessibilityLabel
                    ) {
                        Task { await viewModel.retakeDeclaration() }
                    }
                }
            }
        }
    }

    private func declarationAction(
        _ title: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .saydoText(.status)
                .foregroundStyle(SaydoTheme.Palette.accent)
                .frame(
                    minWidth: SaydoTheme.Metric.minimumTapTarget,
                    minHeight: SaydoTheme.Metric.minimumTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - 下の補助

    /// 左下に「声を出さない」（戻すときは「声に戻す」）、右下に「この質問だけ文字で答える」。
    /// 会話が終わったら出さない。
    private var assistBar: some View {
        HStack(alignment: .center) {
            voiceToggle
            Spacer(minLength: 0)
            keyboardButton
        }
        .padding(.horizontal, Layout.assistBarMargin)
        .padding(.bottom, Layout.assistBarBottom)
    }

    /// 「声を出さない」の切り替え。マイクが拒否されている端末では声に戻せないので、戻す操作を出さない。
    @ViewBuilder
    private var voiceToggle: some View {
        if viewModel.canSwitchToVoice {
            assistTextButton(
                SessionCopy.voiceOnToggle,
                color: SaydoTheme.Palette.accent,
                accessibilityLabel: SessionCopy.voiceOnToggleAccessibilityLabel
            ) {
                Task { await viewModel.switchToVoiceMode() }
            }
        } else if !viewModel.isVoiceOff, viewModel.completion == nil {
            assistTextButton(
                SessionCopy.voiceOffToggle,
                color: SaydoTheme.Palette.ink3,
                accessibilityLabel: SessionCopy.voiceOffToggleAccessibilityLabel
            ) {
                Task { await viewModel.switchToTextMode() }
            }
        }
    }

    private func assistTextButton(
        _ title: String,
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .saydoText(.status)
                .foregroundStyle(color)
                .frame(
                    minWidth: SaydoTheme.Metric.minimumTapTarget,
                    minHeight: SaydoTheme.Metric.minimumTapTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// この質問だけ文字で答える。進行中の聞き取りを止め、入力欄を出してキーボードを上げる。
    /// 次の質問は声に戻る。
    @ViewBuilder
    private var keyboardButton: some View {
        if viewModel.canAnswerByTextOnce {
            Button {
                focusesFieldWhenItAppears = true
                Task {
                    await viewModel.answerByTextOnce()
                    // 文字で受けられない段階（チップだけが答え）では入力欄は出ない。持ち越さない。
                    if !viewModel.showsTextField {
                        focusesFieldWhenItAppears = false
                    }
                }
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
        static let declarationActionSpacing: CGFloat = 24
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
