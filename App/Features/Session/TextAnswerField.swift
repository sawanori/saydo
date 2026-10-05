import SwiftUI

/// 会話画面の中に置く、文字の答えの入力欄（実装計画 §16.8。task_040）。
///
/// シートではないので、送っても閉じない。「声を出さない」の間は質問をまたいで出たままになり、
/// 「この質問だけ文字で答える」とアプリが文字に落とした質問では、その質問の間だけ出る
/// （出すかどうかは `SessionViewModel.showsTextField` が決める）。
///
/// スキップはここに置かない。必須でない質問にだけ、`SessionView` がこの欄の下に出す。
struct TextAnswerField: View {

    /// いまの質問が文字の答えを待っているか。待っていない間（質問と質問の間）は送れない。
    let acceptsAnswer: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: (String) -> Void

    @State private var text = ""

    var body: some View {
        HStack(spacing: Layout.spacing) {
            TextField(
                text: $text,
                prompt: Text(SessionCopy.textFieldPrompt).foregroundStyle(SaydoTheme.Palette.ink4)
            ) {
                Text(SessionCopy.textFieldLabel)
            }
            .textFieldStyle(.plain)
            .saydoText(.declaration)
            .focused(isFocused)
            .submitLabel(.send)
            .onSubmit(send)
            .frame(minHeight: SaydoTheme.Metric.chipHeight)
            .accessibilityLabel(SessionCopy.textFieldLabel)

            Button(action: send) {
                Text(SessionCopy.send)
                    .saydoText(.list)
                    .foregroundStyle(canSend ? SaydoTheme.Palette.accent : SaydoTheme.Palette.ink4)
                    .frame(
                        minWidth: SaydoTheme.Metric.minimumTapTarget,
                        minHeight: SaydoTheme.Metric.chipHeight
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.leading, Layout.fieldPadding)
        .padding(.trailing, Layout.sendPadding)
        .background(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                .fill(SaydoTheme.Palette.chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SaydoTheme.Metric.chipCornerRadius, style: .continuous)
                .stroke(SaydoTheme.Palette.hairline, lineWidth: 1)
        )
    }

    private var answer: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 空の送信はできない。
    private var canSend: Bool {
        acceptsAnswer && !answer.isEmpty
    }

    private func send() {
        guard canSend else { return }
        let sent = answer
        text = ""
        // キーボードの「送信」は入力欄からフォーカスを外す。続けて次の質問に書けるよう戻す。
        isFocused.wrappedValue = true
        onSubmit(sent)
    }

    private enum Layout {
        static let spacing: CGFloat = 8
        static let fieldPadding: CGFloat = 16
        static let sendPadding: CGFloat = 8
    }
}
