import Foundation

/// 行動を 1 段ずつ小さくする段階表（実装計画 §7.2 M2 / N3）。
///
/// **一般形に限定し、特定の分野に依存しない。** 企画メモ §6 の例（PC を開く → メールアプリを
/// 開く → 相手の名前を検索する …）はメールの話なので、そのままは使わない。
/// 「開く → 一部だけ → 1 行だけ → 置くだけ」の 4 段だけを持つ。
public enum ShrinkLadder {

    /// 段階表の 1 段。
    public struct Rung: Sendable, Equatable, Hashable, Codable {
        /// 段の名前（画面に出す言葉）。
        public let name: String
        /// 行動文として保存する言葉。Guardrails の行動文規則（40 文字以内・動詞終わり）を満たす。
        public let actionText: String
        /// 見積もり時間（分）。
        public let estimatedMinutes: Int

        public init(name: String, actionText: String, estimatedMinutes: Int) {
            self.name = name
            self.actionText = actionText
            self.estimatedMinutes = estimatedMinutes
        }
    }

    /// 上から下へ 1 段ずつ小さくなる。
    public static let rungs: [Rung] = [
        Rung(name: "開く", actionText: "開く", estimatedMinutes: 5),
        Rung(name: "一部だけ", actionText: "一部だけ見る", estimatedMinutes: 3),
        Rung(name: "1行だけ", actionText: "1行だけ書く", estimatedMinutes: 2),
        Rung(name: "置くだけ", actionText: "必要なものを机に置く", estimatedMinutes: 1),
    ]

    /// いちばん下の段の番号。
    public static var lastIndex: Int { rungs.count - 1 }

    /// 段を取り出す。範囲外はいちばん下に丸める。
    public static func rung(at index: Int) -> Rung {
        rungs[min(max(index, 0), lastIndex)]
    }

    /// いちばん上の段から始める。
    public static func start() -> MicroAction {
        let rung = rungs[0]
        return MicroAction(text: rung.actionText, estimatedMinutes: rung.estimatedMinutes, shrinkCount: 0)
    }

    /// 1 段下る。いちばん下まで来ていたらそこで止まる。
    public static func next(after action: MicroAction) -> MicroAction {
        let index = min(action.shrinkCount + 1, lastIndex)
        let rung = rung(at: index)
        return MicroAction(text: rung.actionText, estimatedMinutes: rung.estimatedMinutes, shrinkCount: index)
    }

    /// これ以上小さくできるか。
    public static func canShrink(_ action: MicroAction) -> Bool {
        action.shrinkCount < lastIndex
    }
}
