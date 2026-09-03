/// 理由の分類と、その場で返す追加質問 1 文（実装計画 §9）。
///
/// 文字数（60 文字以内）・疑問形であることは `@Guide` ではなく
/// Guardrails（task_005）の後段検査で強制する。
public struct ReasonClassification: Sendable, Codable, Hashable {
    /// 分類した理由。
    public var category: ReasonCategory
    /// 追加質問 1 文。追加質問を出さない場合は空文字。
    public var followUp: String

    public init(category: ReasonCategory, followUp: String = "") {
        self.category = category
        self.followUp = followUp
    }
}
