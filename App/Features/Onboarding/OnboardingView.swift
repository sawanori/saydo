import SwiftUI

/// 初回だけ出る設定（実装計画 §8、task_013）。
///
/// 1 画面に 1 つだけ置く。権限を断られても先へ進める（マイクが無ければ文字だけ、
/// 通知が無ければ本人が開いたときに会話する）。最後に `hasCompletedOnboarding` を立て、
/// 決めた時刻で通知を計画し直してから `onFinished()` を呼ぶ。
///
/// 画面の出し分け（初回だけ表示する分岐）は `RootView` の担当。
@MainActor
struct OnboardingView: View {

    /// オンボーディングが終わったことを親へ返す。`RootView` はここで会話画面へ移る。
    private let onFinished: @MainActor () -> Void
    private let settings: AppSettings

    @State private var permissions = PermissionsViewModel()
    @State private var step: Step = .concept

    @State private var mode: NotificationMode
    @State private var morningTime: Date
    @State private var noonTime: Date
    @State private var nightTime: Date
    @State private var isAloneTimeSet: Bool
    @State private var aloneTime: Date

    init(settings: AppSettings = .shared, onFinished: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.onFinished = onFinished
        _mode = State(initialValue: settings.notificationMode)
        _morningTime = State(initialValue: settings.morningTime.date())
        _noonTime = State(initialValue: settings.noonTime.date())
        _nightTime = State(initialValue: settings.nightTime.date())
        _isAloneTimeSet = State(initialValue: settings.aloneTime != nil)
        _aloneTime = State(initialValue: settings.effectiveAloneTime.date())
    }

    // MARK: - 段階

    private enum Step: Int, CaseIterable {
        case concept
        case microphone
        case notifications
        case schedule
        case aloneTime
        case assets
        case backup

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
        var isLast: Bool { next == nil }
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
        .task { await permissions.refresh() }
    }

    private var header: some View {
        HStack {
            if let previous = step.previous {
                Button(OnboardingCopy.back) { step = previous }
                    .buttonStyle(.plain)
                    .saydoText(.status)
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
        case .notifications: notificationStep
        case .schedule: scheduleStep
        case .aloneTime: aloneTimeStep
        case .assets: AssetDownloadView()
        case .backup: backupStep
        }
    }

    private var footer: some View {
        Button(step.isLast ? OnboardingCopy.finish : OnboardingCopy.next) {
            if let next = step.next {
                step = next
            } else {
                Task { await finish() }
            }
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 12)
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
                Button(OnboardingCopy.microphoneRequest) {
                    Task { await permissions.requestMicrophone() }
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
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

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.notificationTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.notificationBody)
                .saydoText(.list)

            if permissions.isNotificationGranted {
                Text(OnboardingCopy.notificationGranted)
                    .saydoText(.status)
            } else if permissions.needsSystemSettingsForNotifications {
                Text(OnboardingCopy.notificationDenied)
                    .saydoText(.list)
                Text(OnboardingCopy.notificationDeniedHint)
                    .saydoText(.status)
                Button(OnboardingCopy.openSystemSettings) {
                    permissions.openSystemSettings()
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            } else {
                Button(OnboardingCopy.notificationRequest) {
                    Task { await permissions.requestNotifications() }
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.scheduleTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.scheduleBody)
                .saydoText(.list)

            Picker(OnboardingCopy.modeLabel, selection: $mode) {
                Text(OnboardingCopy.modeTwoPerDay).tag(NotificationMode.twoPerDay)
                Text(OnboardingCopy.modeThreePerDay).tag(NotificationMode.threePerDay)
            }
            .pickerStyle(.segmented)

            timeRow(OnboardingCopy.morningTimeLabel, selection: $morningTime)
            if mode == .threePerDay {
                timeRow(OnboardingCopy.noonTimeLabel, selection: $noonTime)
                timeRow(OnboardingCopy.nightTimeLabel, selection: $nightTime)
            }
        }
    }

    private var aloneTimeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.aloneTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.aloneBody)
                .saydoText(.list)

            Toggle(OnboardingCopy.aloneSetToggle, isOn: $isAloneTimeSet)
                .saydoText(.list)
            if isAloneTimeSet {
                timeRow(OnboardingCopy.aloneTimeLabel, selection: $aloneTime)
            } else {
                Text(OnboardingCopy.aloneUnanswered)
                    .saydoText(.status)
            }
        }
    }

    private var backupStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(OnboardingCopy.backupTitle)
                .saydoText(.screenTitle)
            Text(OnboardingCopy.backupBody)
                .saydoText(.list)
            Text(OnboardingCopy.backupWarning)
                .saydoText(.list)
            Text(OnboardingCopy.backupSizeNote)
                .saydoText(.status)
        }
    }

    private func timeRow(_ label: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(label)
                .saydoText(.list)
            Spacer()
            DatePicker(label, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    // MARK: - 保存

    private func finish() async {
        settings.notificationMode = mode
        settings.morningTime = TimeOfDay(date: morningTime)
        settings.noonTime = TimeOfDay(date: noonTime)
        settings.nightTime = TimeOfDay(date: nightTime)
        settings.aloneTime = isAloneTimeSet ? TimeOfDay(date: aloneTime) : nil
        settings.hasCompletedOnboarding = true

        await NotificationScheduler.shared.reschedule(settings: settings.notificationSettings)
        onFinished()
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
