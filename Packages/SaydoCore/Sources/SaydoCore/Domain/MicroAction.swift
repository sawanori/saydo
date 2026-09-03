/// 5 分以下の行動（実装計画 §7.2 M2 / N3、§9）。
///
/// `text` は原則として**本人の言葉**をそのまま入れる（企画原則 §22-6）。
/// Tier A の LLM 提案を採用した場合も、Guardrails を通した後の文だけを入れる。
public struct MicroAction: Sendable, Codable, Hashable {
    /// 行動文。40 文字以内・動詞で終わることは Guardrails（task_005）が保証する。
    public var text: String
    /// 見積もり時間（分）。5 分以下に収める。
    public var estimatedMinutes: Int
    /// 「もっと小さく」を何回下ったか。
    public var shrinkCount: Int

    public init(text: String, estimatedMinutes: Int = 5, shrinkCount: Int = 0) {
        self.text = text
        self.estimatedMinutes = estimatedMinutes
        self.shrinkCount = shrinkCount
    }

    /// 5 分以下に収まっているか。
    public var isFiveMinutesOrLess: Bool {
        estimatedMinutes <= 5
    }

    /// 1 段小さくした行動を返す（`text` の書き換えは呼び出し側が行う）。
    public func shrunk(to text: String, estimatedMinutes: Int) -> MicroAction {
        MicroAction(text: text, estimatedMinutes: estimatedMinutes, shrinkCount: shrinkCount + 1)
    }
}
