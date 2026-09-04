import SwiftUI

/// 右下のキーボードボタンから開く短文入力（実装計画 §7.2）。
///
/// 自動でせり上げない。開くのは本人がボタンを押したときだけで、押した時点で
/// `SessionViewModel.switchToTextMode()` が呼ばれている（読み上げは止まっている）。
struct TextFallbackSheet: View {

    let viewModel: SessionViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text(SessionCopy.textSheetTitle)
                .saydoText(.sectionLabel)

            TextField(
                text: $text,
                prompt: Text(SessionCopy.textFieldPrompt).foregroundStyle(SaydoTheme.Palette.ink4)
            ) {
                Text(SessionCopy.textSheetTitle)
            }
            .textFieldStyle(.plain)
            .saydoText(.declaration)
            .focused($isFocused)
            .submitLabel(.send)
            .onSubmit(send)
            .padding(.horizontal, Layout.fieldPadding)
            .frame(height: SaydoTheme.Metric.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                    .fill(SaydoTheme.Palette.chipFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                    .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
            )

            HStack(spacing: Layout.spacing) {
                Button(action: skip) {
                    Text(SessionCopy.skip)
                        .saydoText(.list)
                        .frame(height: SaydoTheme.Metric.chipHeight)
                        .padding(.horizontal, Layout.fieldPadding)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button(action: send) {
                    Text(SessionCopy.send)
                        .saydoText(.list)
                        .foregroundStyle(canSend ? SaydoTheme.Palette.accent : SaydoTheme.Palette.ink4)
                        .frame(height: SaydoTheme.Metric.chipHeight)
                        .padding(.horizontal, Layout.fieldPadding)
                        .background(
                            RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                                .fill(SaydoTheme.Palette.chipFill)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .saydoGround()
        .presentationDetents([.height(Layout.detentHeight)])
        .presentationBackground(SaydoTheme.Palette.groundMid)
        .onAppear { isFocused = true }
    }

    // MARK: 操作

    /// `acceptsTextInput` が false のあいだは送れない（いまは選択肢を待っている）。
    private var canSend: Bool {
        viewModel.acceptsTextInput && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        dismiss()
        Task { await viewModel.submit(text: answer) }
    }

    private func skip() {
        text = ""
        dismiss()
        Task { await viewModel.skip() }
    }

    private enum Layout {
        static let spacing: CGFloat = 12
        static let padding: CGFloat = 24
        static let fieldPadding: CGFloat = 16
        static let detentHeight: CGFloat = 240
    }
}
