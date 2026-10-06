import SaydoCore
import SwiftUI
import UIKit

/// 今日の画面（実装計画 §17.3「今日」）。
///
/// 約束・アクション・これから追う回の時刻・結果を 1 枚で見せる。主ボタンは、約束が無い日は約束する画面、
/// 答えがまだの回がある日は答える画面を開く。これから追う回がある日は「次は ◯時に追いかけます」（§17.9）。
/// 一覧・チェックボックス・進捗率・連続日数は作らない（企画原則 §22-8）。
/// 約束の声はここからも本人に返せる（§22-10）。
struct TodayView: View {

    private let viewModel: TodayViewModel
    /// 変わるたびに約束を読み直す（被せた画面を閉じたとき）。
    private let reloadToken: Int
    /// 朝の通知が断られているか。断られているときだけ掲示を出す。
    private let notificationsDenied: Bool
    private let onOpenPromise: @MainActor () -> Void
    private let onOpenFollowUp: @MainActor (CommitmentSnapshot) -> Void
    private let onOpenSettings: @MainActor () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(
        viewModel: TodayViewModel,
        reloadToken: Int,
        notificationsDenied: Bool,
        onOpenPromise: @escaping @MainActor () -> Void,
        onOpenFollowUp: @escaping @MainActor (CommitmentSnapshot) -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.viewModel = viewModel
        self.reloadToken = reloadToken
        self.notificationsDenied = notificationsDenied
        self.onOpenPromise = onOpenPromise
        self.onOpenFollowUp = onOpenFollowUp
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    promise
                    if notificationsDenied {
                        notificationNotice
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            footer
        }
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .saydoGround()
        .task(id: reloadToken) {
            await viewModel.load()
        }
        .task(id: viewModel.nextRoundAt) {
            // 画面を出したまま次の回の時刻を過ぎたら読み直す（主ボタンが「答える」に変わる）。
            guard let start = viewModel.nextRoundAt else { return }
            let wait = start.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait + 1))
            }
            guard !Task.isCancelled else { return }
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.load() }
            } else {
                viewModel.stopVoice()
            }
        }
        .onDisappear { viewModel.stopVoice() }
    }

    // MARK: 上部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "SAYDO")
                .saydoText(.logo)
            Spacer()
            Text(Date.now.formatted(Self.dayStyle))
                .saydoText(.time)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.footnote)
                    .foregroundStyle(SaydoTheme.Palette.ink4)
                    .frame(width: SaydoTheme.Metric.minimumTapTarget, height: SaydoTheme.Metric.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(TodayCopy.settings)
        }
    }

    private static let dayStyle = Date.FormatStyle
        .dateTime
        .locale(Locale(identifier: "ja_JP"))
        .month(.defaultDigits)
        .day()
        .weekday(.abbreviated)

    // MARK: 今日の約束

    @ViewBuilder
    private var promise: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(TodayCopy.promiseSectionLabel)
                .saydoText(.sectionLabel)
            if let commitment = viewModel.commitment {
                promiseCard(commitment)
            } else if viewModel.stage == .noPromise {
                Text(TodayCopy.noPromiseYet)
                    .saydoText(.declaration)
                    .foregroundStyle(SaydoTheme.Palette.ink3)
            }
        }
    }

    /// 約束・アクション・追い始める時刻（または結果）を 1 枚に置く。
    private func promiseCard(_ commitment: CommitmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            labeled(PromiseCopy.followUpPromiseLabel, commitment.avoidanceTitle)
            hairline
            labeled(PromiseCopy.followUpActionLabel, commitment.microAction.text)

            let statuses = statusLines(for: commitment)
            if !statuses.isEmpty || viewModel.hasVoice {
                hairline
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(statuses, id: \.label) { status in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(status.label)
                                    .saydoText(.sectionLabel)
                                Text(status.text)
                                    .font(.title3.weight(.medium).monospacedDigit())
                                    .foregroundStyle(SaydoTheme.Palette.accent)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Spacer(minLength: 12)
                    if viewModel.hasVoice {
                        playButton
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                .fill(SaydoTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.cardCornerRadius, style: .continuous)
                .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
        )
    }

    /// カードの下段。答えた回があれば結果、追っている・これから追う回があればその時刻。
    private func statusLines(for commitment: CommitmentSnapshot) -> [(label: String, text: String)] {
        var lines: [(label: String, text: String)] = []
        if let result = PromiseCopy.resultLabel(for: commitment.outcome) {
            lines.append((TodayCopy.resultLabel, result))
        }
        if let since = viewModel.chasingSince, viewModel.stage == .awaitingAnswer {
            lines.append((TodayCopy.chaseTimeLabel, PromiseCopy.chasing(since: since)))
        } else if let next = viewModel.nextRoundAt {
            lines.append((TodayCopy.chaseTimeLabel, PromiseCopy.nextChase(at: next)))
        }
        return lines
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .saydoText(.sectionLabel)
            Text(text)
                .saydoText(.declaration)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(SaydoTheme.Palette.hairline)
            .frame(height: 1)
            .padding(.vertical, 18)
    }

    /// 48px の再生ボタン。約束の声をその場で返す。押すたびに再生と停止が入れ替わる。
    private var playButton: some View {
        Button {
            viewModel.toggleVoice()
        } label: {
            Image(systemName: viewModel.isPlayingVoice ? "stop.fill" : "play.fill")
                .font(.footnote)
                .foregroundStyle(SaydoTheme.Palette.accent)
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(SaydoTheme.Palette.accent.opacity(0.09))
                )
                .overlay(
                    Circle().stroke(SaydoTheme.Palette.accent.opacity(0.42), lineWidth: 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isPlayingVoice ? TodayCopy.stopDeclaration : TodayCopy.playDeclaration)
    }

    // MARK: 通知の再許可

    /// 朝の通知を断っているときだけ出す。黙って壊れたままにしない（実装計画 §7.4）。
    private var notificationNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TodayCopy.notificationsStopped)
                .saydoText(.list)
            Button(TodayCopy.openSystemSettings) {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(SaydoTheme.Palette.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                .fill(SaydoTheme.Palette.chipFill)
        )
    }

    // MARK: 下部

    @ViewBuilder
    private var footer: some View {
        switch viewModel.stage {
        case .noPromise:
            primaryButton(PromiseCopy.todayPromiseButton) {
                onOpenPromise()
            }
        case .awaitingAnswer:
            primaryButton(PromiseCopy.todayAnswerButton) {
                if let commitment = viewModel.commitment {
                    onOpenFollowUp(commitment)
                }
            }
        case .answered:
            Text(TodayCopy.dayFinished)
                .saydoText(.status)
                .frame(maxWidth: .infinity)
        case .loading, .beforeChase:
            EmptyView()
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .tracking(1.7)
                .foregroundStyle(SaydoTheme.Palette.accentHighlight)
                .frame(maxWidth: .infinity)
                .frame(height: SaydoTheme.Metric.primaryButtonHeight)
                .background(
                    Capsule().fill(SaydoTheme.Palette.accent.opacity(0.12))
                )
                .overlay(
                    Capsule().stroke(SaydoTheme.Palette.accent.opacity(0.3), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
