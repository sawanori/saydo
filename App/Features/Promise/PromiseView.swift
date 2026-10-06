import SwiftUI
import SaydoCore

/// 約束する画面（実装計画 §17.3）。
///
/// 画面にあるのは、質問 1 行、大きな「押して話す」ボタン、聞き取った 1 行、キーボードのボタンだけ。
/// 質問は読み上げない。2 つ答えたら、聞き取った 2 行と「約束する」を出す（追う時刻は選ばない。§17.9）。
/// 約束の無い朝は、下に小さく「今日はやめる」を出す（その日の朝の回を止める）。
/// 文言はすべて `PromiseCopy` から採る。
struct PromiseView: View {

    @State private var viewModel: PromiseViewModel
    private let microphoneGranted: Bool
    private let onClose: () -> Void

    @GestureState private var isPressed = false
    @FocusState private var isTextFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// 配線用。依存をそのまま受け取る。
    ///
    /// - Parameters:
    ///   - microphoneGranted: マイクが使えるか。使えなければ最初から文字の入力になる。
    ///   - onClose: 「閉じる」を押したとき、または完了の 1 行を出し終えたときに呼ぶ。
    init(
        repository: Repository,
        capture: any VoiceCapturing,
        transcriber: any Transcribing,
        chase: ChaseCoordinator,
        audioFiles: AudioFileStore,
        audioSession: (any AudioSessionControlling)? = nil,
        microphoneGranted: Bool,
        calendar: Calendar = .current,
        onClose: @escaping () -> Void
    ) {
        self.init(
            viewModel: PromiseViewModel(
                store: RepositoryPromiseStore(repository, calendar: calendar),
                capture: capture,
                transcriber: transcriber,
                chase: chase,
                audioFiles: audioFiles,
                audioSession: audioSession,
                calendar: calendar
            ),
            microphoneGranted: microphoneGranted,
            onClose: onClose
        )
    }

    init(viewModel: PromiseViewModel, microphoneGranted: Bool, onClose: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.microphoneGranted = microphoneGranted
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: Layout.sectionSpacing)
            content
            Spacer(minLength: Layout.sectionSpacing)
            footer
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.bottom, Layout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .saydoGround()
        .onAppear { viewModel.open(microphoneGranted: microphoneGranted) }
        .onDisappear { viewModel.close() }
        .onChange(of: isPressed) { _, pressed in
            if pressed {
                viewModel.pressBegan()
            } else {
                viewModel.pressEnded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 画面が前面でなくなったら、指が離れたのと同じ扱いにする。
            if phase != .active {
                viewModel.pressEnded()
            }
        }
        .onChange(of: viewModel.showsTextField) { _, shows in
            isTextFocused = shows
        }
        .task(id: viewModel.stage) {
            // 追いかける約束ができたら、完了の 1 行を見せてから戻る。
            // 追えなかったときの 1 行は、本人が読んで閉じるまで出したままにする。
            guard viewModel.stage == .done, case .scheduled = viewModel.alarmOutcome else { return }
            try? await Task.sleep(for: Layout.completionHold)
            guard !Task.isCancelled else { return }
            onClose()
        }
        .onChange(of: viewModel.didStopToday) { _, stopped in
            // 「今日はやめる」。朝の回を止め終えたら閉じる。
            guard stopped else { return }
            viewModel.close()
            onClose()
        }
    }

    // MARK: 上段

    private var topBar: some View {
        HStack {
            Button {
                viewModel.close()
                onClose()
            } label: {
                Text(PromiseCopy.close)
                    .saydoText(.list)
                    .frame(
                        minWidth: SaydoTheme.Metric.minimumTapTarget,
                        minHeight: SaydoTheme.Metric.minimumTapTarget,
                        alignment: .leading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, Layout.topPadding)
    }

    // MARK: 中段

    @ViewBuilder
    private var content: some View {
        VStack(spacing: Layout.sectionSpacing) {
            if viewModel.stage == .done {
                Text(viewModel.completionLine ?? "")
                    .saydoText(.question)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                answeredLines
                if let question = viewModel.currentQuestion {
                    Text(question.text)
                        .saydoText(.question)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notice = viewModel.notice {
                        noticeLine(notice.text)
                    } else if !viewModel.microphoneGranted {
                        noticeLine(PromiseCopy.textInputGuide)
                    }
                    if viewModel.showsTalkButton {
                        talkButton
                    }
                } else if viewModel.stage == .confirm {
                    confirmSection
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func noticeLine(_ text: String) -> some View {
        Text(text)
            .saydoText(.list)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 答え終えた質問と、聞き取った 1 行。横に「言い直す」。
    private var answeredLines: some View {
        VStack(alignment: .leading, spacing: Layout.answerSpacing) {
            ForEach(PromiseQuestion.allCases, id: \.self) { question in
                if let answer = viewModel.answers[question] {
                    VStack(alignment: .leading, spacing: Layout.answerInnerSpacing) {
                        Text(question.text)
                            .saydoText(.status)
                        HStack(alignment: .firstTextBaseline, spacing: Layout.answerInnerSpacing) {
                            Text(answer.text)
                                .saydoText(.declaration)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            Button {
                                viewModel.redo(question)
                            } label: {
                                Text(PromiseCopy.redo)
                                    .saydoText(.list)
                                    .foregroundStyle(SaydoTheme.Palette.accent)
                                    .frame(
                                        minWidth: SaydoTheme.Metric.minimumTapTarget,
                                        minHeight: SaydoTheme.Metric.minimumTapTarget
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isSaving)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 押している間だけ録音するボタン。押下中は波形と経過秒数に変わる。
    private var talkButton: some View {
        VStack(spacing: Layout.talkSpacing) {
            ZStack {
                Circle()
                    .fill(viewModel.isHolding ? SaydoTheme.Palette.accent : SaydoTheme.Palette.chipFill)
                Circle()
                    .stroke(SaydoTheme.Palette.accent, lineWidth: Layout.talkStroke)
                if viewModel.isHolding {
                    Text(PromiseCopy.elapsed(seconds: viewModel.elapsedSeconds))
                        .font(.title.weight(.medium).monospacedDigit())
                        .foregroundStyle(SaydoTheme.Palette.groundBottom)
                } else {
                    Text(PromiseCopy.pressToTalk)
                        .saydoText(.screenTitle)
                }
            }
            .frame(width: Layout.talkDiameter, height: Layout.talkDiameter)
            .scaleEffect(viewModel.isHolding ? Layout.talkPressedScale : 1)
            .animation(.easeOut(duration: Layout.talkAnimation), value: viewModel.isHolding)
            .contentShape(Circle())
            .opacity(viewModel.isFinalizing ? Layout.busyOpacity : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, pressed, _ in pressed = true }
            )
            .accessibilityElement()
            .accessibilityLabel(PromiseCopy.pressToTalk)
            .accessibilityAddTraits(.isButton)

            ZStack {
                if viewModel.isHolding {
                    VStack(spacing: Layout.answerInnerSpacing) {
                        WaveformView(sampler: viewModel.waveform, style: .compact)
                        Text(PromiseCopy.whileHolding)
                            .saydoText(.list)
                    }
                }
            }
            .frame(height: Layout.holdingAreaHeight)
        }
    }

    /// 聞き取った 2 行の下の「約束する」。追う時刻は選ばない（朝・昼・晩の決まった時刻に追う）。
    private var confirmSection: some View {
        VStack(spacing: Layout.sectionSpacing) {
            if let notice = viewModel.notice {
                noticeLine(notice.text)
            }
            Button {
                Task { await viewModel.commit() }
            } label: {
                Text(PromiseCopy.commit)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(SaydoTheme.Palette.groundBottom)
                    .frame(maxWidth: .infinity)
                    .frame(height: SaydoTheme.Metric.primaryButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                            .fill(SaydoTheme.Palette.accent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canCommit)
            .opacity(viewModel.canCommit ? 1 : Layout.busyOpacity)
        }
    }

    /// 約束の無い朝だけ出す、小さい文字ボタン。約束はせず、その日の朝の回を止める。
    private var stopTodayButton: some View {
        Button {
            Task { await viewModel.stopToday() }
        } label: {
            Text(PromiseCopy.notTodayButton)
                .font(.footnote)
                .foregroundStyle(SaydoTheme.Palette.ink3)
                .frame(minHeight: SaydoTheme.Metric.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSaving)
    }

    // MARK: 下段

    /// 文字の入力欄、またはキーボードのボタン。その下に、約束の無い朝だけ「今日はやめる」。
    private var footer: some View {
        VStack(spacing: Layout.answerInnerSpacing) {
            inputFooter
            if viewModel.showsStopToday, viewModel.stage != .done {
                stopTodayButton
            }
        }
    }

    @ViewBuilder
    private var inputFooter: some View {
        if viewModel.showsTextField {
            VStack(spacing: Layout.answerInnerSpacing) {
                TextAnswerField(acceptsAnswer: true, isFocused: $isTextFocused) { text in
                    viewModel.submitText(text)
                }
                if viewModel.canUseVoice {
                    footerButton(symbol: Layout.voiceSymbol, label: PromiseCopy.voiceInputButton) {
                        viewModel.useVoiceInput()
                    }
                }
            }
        } else if viewModel.showsTalkButton {
            footerButton(symbol: Layout.keyboardSymbol, label: PromiseCopy.textInputButton) {
                viewModel.useTextInput()
            }
        } else {
            Color.clear.frame(height: SaydoTheme.Metric.keyboardButtonSize)
        }
    }

    private func footerButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Layout.footerGlyphSize, weight: .light))
                .foregroundStyle(SaydoTheme.Palette.ink3)
                .frame(
                    width: SaydoTheme.Metric.keyboardButtonSize,
                    height: SaydoTheme.Metric.keyboardButtonSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private enum Layout {
        static let horizontalPadding: CGFloat = 24
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
        static let answerSpacing: CGFloat = 14
        static let answerInnerSpacing: CGFloat = 6
        static let talkSpacing: CGFloat = 16
        static let talkDiameter: CGFloat = 200
        static let talkStroke: CGFloat = 2
        static let talkPressedScale: CGFloat = 1.06
        static let talkAnimation: Double = 0.15
        static let holdingAreaHeight: CGFloat = 100
        static let busyOpacity: Double = 0.5
        static let footerGlyphSize: CGFloat = 20
        static let keyboardSymbol = "keyboard"
        static let voiceSymbol = "mic"
        static let completionHold: Duration = .seconds(3)
    }
}
