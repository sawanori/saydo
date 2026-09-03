/// 逃げたい理由の 7 分類（実装計画 §7.2 M1）。
///
/// Tier B では本人にこの 7 つから選んでもらい、Tier A では LLM が分類する。
public enum ReasonCategory: String, Sendable, Codable, Hashable, CaseIterable {
    /// 気まずい
    case awkward
    /// 完璧にやりたい
    case perfectionism
    /// 面倒
    case tedious
    /// 不安・怖い
    case anxious
    /// 量が多い
    case tooMuch
    /// 何から始めるかわからない
    case unclearStart
    /// 期限が怖い
    case deadlineFear

    public var displayName: String {
        switch self {
        case .awkward: "気まずい"
        case .perfectionism: "完璧にやりたい"
        case .tedious: "面倒"
        case .anxious: "不安・怖い"
        case .tooMuch: "量が多い"
        case .unclearStart: "何から始めるかわからない"
        case .deadlineFear: "期限が怖い"
        }
    }
}
