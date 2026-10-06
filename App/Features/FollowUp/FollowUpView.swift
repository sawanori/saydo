import SaydoCore
import SwiftUI

/// 答える画面（実装計画 §17.3「答える」）。
///
/// 約束とアクションの文字、本人の声の再生、3 つのボタン（やった・少しやった・まだ）と、
/// 小さい文字ボタンの「今日はやめる」を置く（実装計画 §17.9 の 3）。
/// 責める文言・赤・達成マークは出さない（企画原則 §22-1 / §22-8）。3 つのボタンに優劣を付けない。
struct FollowUpView: View {

    @State private var viewModel: FollowUpViewModel

    init(viewModel: FollowUpViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(PromiseCopy.followUpHeading)
                        .saydoText(.question)
                        .fixedSize(horizontal: false, vertical: true)
                    promiseCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
        .padding(.horizontal, 30)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .saydoGround()
    }

    // MARK: 上部

    private var header: some View {
        HStack {
            Button(PromiseCopy.followUpClose) {
                viewModel.close()
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(SaydoTheme.Palette.ink3)
            .frame(minHeight: SaydoTheme.Metric.minimumTapTarget)
            .contentShape(Rectangle())
            Spacer()
        }
    }

    // MARK: 約束とアクション

    private var promiseCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            labeled(PromiseCopy.followUpPromiseLabel, viewModel.promiseText)

            Rectangle()
                .fill(SaydoTheme.Palette.hairline)
                .frame(height: 1)
                .padding(.vertical, 18)

            labeled(PromiseCopy.followUpActionLabel, viewModel.actionText)

            if viewModel.hasVoice {
                voiceButton
                    .padding(.top, 20)
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

    private func labeled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .saydoText(.sectionLabel)
            Text(text)
                .saydoText(.declaration)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 本人の声をその場で返す（企画原則 §22-10）。押すたびに再生と停止が入れ替わる。
    private var voiceButton: some View {
        Button {
            viewModel.toggleVoice()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: viewModel.isPlayingVoice ? "stop.fill" : "play.fill")
                    .font(.footnote)
                Text(viewModel.isPlayingVoice ? PromiseCopy.followUpStopVoice : PromiseCopy.followUpPlayVoice)
                    .font(.callout)
            }
            .foregroundStyle(SaydoTheme.Palette.accent)
            .padding(.horizontal, 18)
            .frame(minHeight: SaydoTheme.Metric.chipHeight)
            .background(
                Capsule().fill(SaydoTheme.Palette.accent.opacity(0.09))
            )
            .overlay(
                Capsule().stroke(SaydoTheme.Palette.accent.opacity(0.42), lineWidth: 1.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 下部（答えのボタン、または押した後の 1 行）

    @ViewBuilder
    private var footer: some View {
        switch viewModel.phase {
        case .asking, .saving:
            VStack(alignment: .leading, spacing: 12) {
                if let notice = viewModel.notice {
                    Text(notice)
                        .saydoText(.list)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                }
                answerButton(PromiseCopy.doneButton, .done)
                answerButton(PromiseCopy.partialButton, .partial)
                answerButton(PromiseCopy.notYetButton, .notYet)
                stopTodayButton
            }
            .disabled(viewModel.phase == .saving)
            .opacity(viewModel.phase == .saving ? 0.6 : 1)
        case .answered(let reply):
            VStack(alignment: .leading, spacing: 24) {
                Text(reply)
                    .saydoText(.reflection)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    viewModel.close()
                } label: {
                    buttonLabel(PromiseCopy.followUpClose)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func answerButton(_ title: String, _ answer: FollowUpAnswer) -> some View {
        Button {
            Task { await viewModel.answer(answer) }
        } label: {
            buttonLabel(title)
        }
        .buttonStyle(.plain)
    }

    /// 「今日はやめる」。その日の後追いをすべて終える。小さい文字ボタンとして残す。
    private var stopTodayButton: some View {
        Button {
            Task { await viewModel.answer(.stopToday) }
        } label: {
            Text(PromiseCopy.notTodayButton)
                .font(.footnote)
                .foregroundStyle(SaydoTheme.Palette.ink3)
                .frame(maxWidth: .infinity, minHeight: SaydoTheme.Metric.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 3 つとも同じ見た目にする（どれを選んでも同じ重さ）。
    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .foregroundStyle(SaydoTheme.Palette.ink1)
            .frame(maxWidth: .infinity, minHeight: SaydoTheme.Metric.primaryButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                    .fill(SaydoTheme.Palette.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                    .stroke(SaydoTheme.Palette.accent.opacity(0.42), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous))
    }
}
