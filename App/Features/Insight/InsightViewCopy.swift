import SwiftUI

/// Insight 画面だけで使う文言（CLAUDE.md §1「文言は *Copy に置く」）。
///
/// 集計の結果として出る文（1 行インサイト・振り返り・データ不足）は `SaydoCore` の
/// `InsightCopy` が持つ。ここには見出しと読み上げラベルだけを置く。
/// 責める語・達成率・連続日数の語彙は置かない（企画原則 §22-1 / §22-8）。
enum InsightViewCopy {

    /// 週次画面のタイトル。
    static let weeklyTitle = "この1週間"

    /// 上位 5 分野の見出し。
    static let topDomainsLabel = "あなたが逃げやすいこと"

    /// 「逃げる理由」の帯の見出し。
    static let reasonsLabel = "逃げる理由"

    /// 日付範囲の区切り（8月29日 — 9月4日）。
    static let periodSeparator = " — "

    /// Timeline 上部のカードの読み上げラベル。
    static let openWeeklyAccessibilityLabel = "この1週間の振り返りを開く"

    /// 週次画面を閉じるボタンの読み上げラベル。
    static let closeAccessibilityLabel = "閉じる"

    /// `InsightCopy` の文で分野名を囲んでいる引用符。
    static let emphasisOpen: Character = "『"
    static let emphasisClose: Character = "』"

    /// 『』で囲まれた部分だけを温色にする（design-notes §画面別 5）。
    ///
    /// 文そのものは `InsightCopy` が作る。ここでは色の当て方だけを決める。
    static func emphasized(_ text: String, emphasis: Color) -> AttributedString {
        var result = AttributedString()
        var buffer = ""
        var isEmphasized = false

        func flush() {
            guard !buffer.isEmpty else { return }
            var piece = AttributedString(buffer)
            if isEmphasized { piece.foregroundColor = emphasis }
            result.append(piece)
            buffer = ""
        }

        for character in text {
            if character == emphasisOpen {
                flush()
                isEmphasized = true
                buffer.append(character)
            } else if character == emphasisClose {
                buffer.append(character)
                flush()
                isEmphasized = false
            } else {
                buffer.append(character)
            }
        }
        flush()
        return result
    }
}
