import Foundation

/// 週次分析の入力 1 件。
///
/// SwiftData の `Commitment` と、その `AvoidanceItem` から取り出した軽量な値。
/// SaydoCore は SwiftData に依存しないので、App 側の `Repository` がこの形に詰め替えて渡す。
public struct InsightInput: Sendable, Codable, Hashable {
    /// 逃げたいことを言った日時（`Commitment.createdAt` 相当）。
    public var date: Date
    /// 逃げている対象の分野（`AvoidanceItem.domain` 相当）。未判定は nil。
    public var domain: TaskDomain?
    /// 逃げたい理由。未確定は nil。
    public var reason: ReasonCategory?
    /// 宣言の結果。
    public var outcome: CommitmentOutcome

    public init(
        date: Date,
        domain: TaskDomain? = nil,
        reason: ReasonCategory? = nil,
        outcome: CommitmentOutcome = .pending
    ) {
        self.date = date
        self.domain = domain
        self.reason = reason
        self.outcome = outcome
    }
}

/// 「何をやったか」ではなく「何から逃げているか」を集計する純関数（実装計画 §7.6、企画メモ §11）。
///
/// 結果内訳（`done` / `partial` / `notYet` の件数）と平均縮小回数は持たない。
/// `WeeklyStats` の目的を「何から、なぜ逃げるか」の理解に限定し、達成率の表示に使わせない
/// （企画原則 §22-8「タスク管理アプリにしない」）。
public enum InsightCalculator {

    /// 初回インサイトを出すのに必要な件数（retention-strategy R9）。
    public static let firstInsightThreshold = 3

    // MARK: - 集計

    /// 与えられた入力をそのまま集計する。期間の切り出しは呼び出し側の責任。
    ///
    /// - 分野別件数: `domain` が nil の入力は数えない（分野が未判定のため）。
    /// - 理由別割合: `reason != nil` の件数を母数にする。1 件も無ければ空。
    public static func weeklyStats(from inputs: [InsightInput], weekStart: Date) -> WeeklyStats {
        var domainCounts: [TaskDomain: Int] = [:]
        for domain in inputs.compactMap(\.domain) {
            domainCounts[domain, default: 0] += 1
        }

        let reasons = inputs.compactMap(\.reason)
        var reasonRatios: [ReasonCategory: Double] = [:]
        if !reasons.isEmpty {
            var reasonCounts: [ReasonCategory: Int] = [:]
            for reason in reasons {
                reasonCounts[reason, default: 0] += 1
            }
            let denominator = Double(reasons.count)
            for (reason, count) in reasonCounts {
                reasonRatios[reason] = Double(count) / denominator
            }
        }

        return WeeklyStats(weekStart: weekStart, domainCounts: domainCounts, reasonRatios: reasonRatios)
    }

    /// `date` を含む週に入る入力だけを集計する。週の始まりは暦の `firstWeekday` に従う。
    public static func weeklyStats(
        from inputs: [InsightInput],
        weekContaining date: Date,
        calendar: Calendar = .current
    ) -> WeeklyStats {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return weeklyStats(from: inputs, weekStart: calendar.startOfDay(for: date))
        }
        let inWeek = inputs.filter { week.start <= $0.date && $0.date < week.end }
        return weeklyStats(from: inWeek, weekStart: week.start)
    }

    // MARK: - 初回インサイト（retention-strategy R9）

    /// 3 件目で出す 1 行。「3 回のうち 2 回が『人への返信』」。
    ///
    /// 週次を待たずに Timeline 上部へ出す。件数が足りないとき、または偏りが無いとき（最多が 1 件）は nil。
    public static func firstInsight(from inputs: [InsightInput]) -> String? {
        let domains = inputs.compactMap(\.domain)
        guard domains.count >= firstInsightThreshold else { return nil }

        var counts: [TaskDomain: Int] = [:]
        for domain in domains {
            counts[domain, default: 0] += 1
        }
        guard let top = counts
            .sorted(by: { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.rawValue < rhs.key.rawValue : lhs.value > rhs.value
            })
            .first,
            top.value >= 2
        else { return nil }

        return InsightCopy.firstInsight(total: domains.count, count: top.value, domain: top.key)
    }

    // MARK: - 週次の振り返り 1 文

    /// テンプレートの振り返り 1 文（Tier B）。上位の理由 × 上位の分野の組み合わせ表から選ぶ。
    ///
    /// Tier A はこの `stats` だけを LLM に渡して生成し、Guardrails を通らなければこの戻り値に置き換える。
    public static func weeklyReflection(for stats: WeeklyStats) -> String {
        guard stats.totalCount >= firstInsightThreshold,
              let domain = stats.topDomains(limit: 1).first
        else { return InsightCopy.notEnoughData }

        guard let reason = stats.topReasons(limit: 1).first else {
            return InsightCopy.reflection(domain: domain)
        }
        return InsightCopy.reflection(reason: reason, domain: domain)
    }
}
