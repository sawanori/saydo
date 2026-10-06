import SwiftUI

/// 初回だけ出る 3 画面（実装計画 §17.6、task_056）: 何をするアプリか、マイクの許可、アラームの許可。
///
/// 1 画面に 1 つだけ置く。許可は画面下の主ボタンで求め、断られても先へ進める
/// （マイクが無ければ文字だけ、アラームが無くても約束は残る）。
/// 朝の通知の許可はここでは求めない（最初の約束が保存された後に求める）。
/// 終えると `onFinished()` を呼び、`AppRouter` が約束する画面を出す。
@MainActor
struct OnboardingView: View {

    /// オンボーディングが終わったことを親へ返す。
    private let onFinished: @MainActor () -> Void

    @State private var permissions: PermissionsViewModel
    @State private var step: Step = .concept
    /// 許可のダイアログを出している間、主ボタンを二度押させない。
    @State private var isRequesting = false
    /// 日本語の聞き取りモデルの取得を、画面の裏で始めておく（約束する画面で待たせないため）。
    @State private var transcription = TranscriptionService()
    @Environment(\.scenePhase) private var scenePhase

    init(alarms: any AlarmScheduling, onFinished: @escaping @MainActor () -> Void) {
        self.onFinished = onFinished
        _permissions = State(initialValue: PermissionsViewModel(alarms: alarms))
    }

    // MARK: - 段階

    private enum Step: Int, CaseIterable {
        case concept
        case microphone
        case alarm

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    // MARK: - 本体

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .tint(SaydoTheme.Palette.accent)
        .saydoGround()
        .task {
            // 取得できなくても先へ進める。約束する画面が、録音のたびにもう一度確かめる。
            _ = try? await transcription.prepare()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refresh() }
        }
    }

    private var header: some View {
        HStack {
            if let previous = step.previous {
                Button(OnboardingCopy.back) { step = previous }
                    .buttonStyle(.plain)
                    .saydoText(.status)
                    .disabled(isRequesting)
            }
            Spacer()
            Text(verbatim: "\(step.rawValue + 1) / \(Step.allCases.count)")
                .saydoText(.time)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .concept: conceptStep
        case .microphone: microphoneStep
        case .alarm: alarmStep
        }
    }

    /// 画面下の主ボタン。許可の画面では、このボタンで許可を求めてから進む。
    private var footer: some View {
        Button(primaryTitle) {
            Task { await advance() }
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .disabled(isRequesting)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    private var primaryTitle: String {
        switch step {
        case .concept:
            OnboardingCopy.next
        case .microphone:
            permissions.microphone == .undetermined ? OnboardingCopy.microphoneRequest : OnboardingCopy.next
        case .alarm:
            OnboardingCopy.alarmRequest
        }
    }

    /// 主ボタン。許可を求め、答えがどちらでも次へ進む。
    private func advance() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }

        switch step {
        case .concept:
            break
        case .microphone:
            await permissions.requestMicrophone()
        case .alarm:
            await permissions.requestAlarm()
        }

        if let next = step.next {
            step = next
        } else {
            onFinished()
        }
    }

    // MARK: - 各段階

    private var conceptStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.conceptTitle)
                .saydoText(.logo)
            Text(OnboardingCopy.conceptBody)
                .saydoText(.question)
            Text(OnboardingCopy.conceptDetail)
                .saydoText(.list)
        }
    }

    private var microphoneStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.microphoneTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.microphoneBody)
                .saydoText(.list)

            switch permissions.microphone {
            case .undetermined:
                EmptyView()
            case .granted:
                Text(OnboardingCopy.microphoneGranted)
                    .saydoText(.status)
            case .denied:
                Text(OnboardingCopy.microphoneDenied)
                    .saydoText(.list)
                Text(OnboardingCopy.microphoneDeniedHint)
                    .saydoText(.status)
                Button(OnboardingCopy.openSystemSettings) {
                    permissions.openSystemSettings()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var alarmStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.alarmTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.alarmBody)
                .saydoText(.list)
            Text(OnboardingCopy.alarmDetail)
                .saydoText(.status)
        }
    }
}

// MARK: - ボタン

/// 画面下の主ボタン（高さ 64、角丸はチップと同じ 15）。
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .saydoText(.list)
            .foregroundStyle(SaydoTheme.Palette.groundBottom)
            .frame(maxWidth: .infinity)
            .frame(height: SaydoTheme.Metric.primaryButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                    .fill(SaydoTheme.Palette.accent)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 文中に置く副ボタン（チップと同じ高さ・角丸）。
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .saydoText(.list)
            .foregroundStyle(SaydoTheme.Palette.accent)
            .padding(.horizontal, 20)
            .frame(height: SaydoTheme.Metric.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                    .fill(SaydoTheme.Palette.chipFill)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
