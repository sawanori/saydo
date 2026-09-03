import Foundation

/// 週次分析の集計値（実装計画 §7.6、fix-decisions P2.2）。
///
/// LLM に渡すのは**分野別の件数と理由別の割合だけ**。本人の発話原文・宣言の結果内訳・
/// 平均縮小回数は渡さない（目的を「何から、なぜ逃げるか」の理解に限定するため）。
public struct WeeklyStats: Sendable, Codable, Hashable {
    /// 集計対象の週の開始日。
    public var weekStart: Date
    /// 分野別の件数。
    public var domainCounts: [TaskDomain: Int]
    /// 理由別の割合（0.0〜1.0）。
    public var reasonRatios: [ReasonCategory: Double]

    public init(
        weekStart: Date,
        domainCounts: [TaskDomain: Int] = [:],
        reasonRatios: [ReasonCategory: Double] = [:]
    ) {
        self.weekStart = weekStart
        self.domainCounts = domainCounts
        self.reasonRatios = reasonRatios
    }

    /// 集計対象の総件数。
    public var totalCount: Int {
        domainCounts.values.reduce(0, +)
    }

    /// 件数の多い順の分野。同数のときは rawValue の昇順で安定させる。
    public func topDomains(limit: Int = 5) -> [TaskDomain] {
        domainCounts
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
            }
            .prefix(max(0, limit))
            .map(\.key)
    }

    /// 割合の大きい順の理由。同率のときは rawValue の昇順で安定させる。
    public func topReasons(limit: Int = 3) -> [ReasonCategory] {
        reasonRatios
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
            }
            .prefix(max(0, limit))
            .map(\.key)
    }
}
