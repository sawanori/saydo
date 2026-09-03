/// 逃げている対象の分野（実装計画 §7.6）。週次分析の「何から逃げているか」に使う。
public enum TaskDomain: String, Sendable, Codable, Hashable, CaseIterable {
    /// 人への返信
    case reply
    /// お金
    case money
    /// 大きなタスク
    case bigTask
    /// 営業
    case sales
    /// 書類
    case paperwork
    /// 健康
    case health
    /// その他
    case other

    public var displayName: String {
        switch self {
        case .reply: "人への返信"
        case .money: "お金"
        case .bigTask: "大きなタスク"
        case .sales: "営業"
        case .paperwork: "書類"
        case .health: "健康"
        case .other: "その他"
        }
    }
}
