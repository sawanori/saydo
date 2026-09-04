import Foundation
import SaydoCore
import SwiftData

/// 週次インサイトの集計期間（実装計画 §7.6）。
///
/// `endingAt` の当日を含む `days` 日ぶんの半開区間 `[start, end)` を返す。
/// 日の境界は渡された暦に従う。
enum InsightPeriod {
    static func make(endingAt end: Date, days: Int, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        let upperBound = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return DateInterval(start: start, end: upperBound)
    }
}

/// 週次インサイト（task_016）が使う読み出し。
///
/// `Repository.swift` 本体には足さない（第 2 波で同ファイルを別の担当が変更中のため）。
/// ここから出すのは `InsightCalculator` の入力と件数だけで、宣言の結果内訳
/// （done / partial / notYet）と平均縮小回数は出さない（fix-decisions P2.2 / 実装計画 §7.6）。
/// 集計値そのものは既存の `weeklyStats(from:to:)` を使う。
extension Repository {

    /// 週次インサイトの入力。`endingAt` の当日を含む `days` 日ぶんを古い順に返す。
    func insightInputs(
        endingAt end: Date = .now,
        days: Int = 7,
        calendar: Calendar = .current
    ) throws -> [InsightInput] {
        let period = InsightPeriod.make(endingAt: end, days: days, calendar: calendar)
        return try insightInputs(from: period.start, to: period.end)
    }

    /// `[start, end)` に作られた宣言を `InsightInput` に詰め替える。
    ///
    /// `InsightInput.outcome` は既定のまま埋めない。`InsightCalculator` は結果を読まず、
    /// 結果内訳をインサイト経路に持ち込まない方針だから（fix-decisions P2.2）。
    func insightInputs(from start: Date, to end: Date) throws -> [InsightInput] {
        let descriptor = FetchDescriptor<Commitment>(
            predicate: #Predicate<Commitment> { $0.createdAt >= start && $0.createdAt < end },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { commitment in
            InsightInput(
                date: commitment.createdAt,
                domain: commitment.avoidanceItem?.domain ?? .other,
                reason: commitment.reason
            )
        }
    }

    /// これまでに記録した宣言の件数（retention R9 の「3 件目」判定に使う）。
    func recordedCommitmentCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Commitment>())
    }

    /// 最初に記録した宣言の日時。1 件も無ければ nil。
    ///
    /// 「使い始めてから 7 日そろったか」（週次に切り替えるか）の判定に使う。
    func firstCommitmentDate() throws -> Date? {
        var descriptor = FetchDescriptor<Commitment>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.createdAt
    }
}
