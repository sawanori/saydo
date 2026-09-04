import Foundation
import SaydoCore
import SwiftData

/// 設定画面の「開発者向け」節に出す集計（retention-strategy.md §4、task_013）。
///
/// `Repository.swift` 本体には足さない（別のタスクが同じファイルを触っているため）。
/// `weeklyStats` にも混ぜない: あちらは LLM へ渡す「分野別の件数と理由別の割合」だけを持つ
/// と決めてある（fix-decisions P2.2）。結果内訳をここに置くのはその決定に沿う。
extension Repository {

    /// 端末の中だけで数えた値。外部送信はしない。
    struct DeveloperStats: Sendable, Equatable {
        /// 集計した日数（`now` を含む直近 N 日）。
        var windowDays: Int

        /// 期間内に始まった会話の件数。
        var sessionCount: Int
        /// そのうち最後まで進んだ件数。
        var completedSessionCount: Int
        /// 種別ごとの（完走数, 総数）。
        var sessionCountsByType: [SessionType: SessionCount]
        /// 種別ごとの所要時間の中央値（秒）。終わりが記録されている会話だけを数える。
        var medianDurationByType: [SessionType: Double]

        /// 期間内に作られた宣言の件数。
        var commitmentCount: Int
        /// 宣言のあとの答えの内訳。
        var outcomeCounts: [CommitmentOutcome: Int]
        /// 「もっと小さく」を下った回数の平均。
        var averageShrinkCount: Double
        /// 声を使わずに宣言した件数（retention-strategy R1 の代替経路）。
        var voicelessCommitmentCount: Int
        /// 期間内で宣言が 1 件も無かった日数。「休んだ回数」の代わりに見る値。
        var daysWithoutCommitment: Int

        /// 会話の完走率。1 件も無ければ nil。
        var completionRate: Double? {
            guard sessionCount > 0 else { return nil }
            return Double(completedSessionCount) / Double(sessionCount)
        }

        /// 表示するものが何も無い状態。
        var isEmpty: Bool { sessionCount == 0 && commitmentCount == 0 }
    }

    /// 種別ごとの件数。
    struct SessionCount: Sendable, Equatable {
        var completed: Int
        var total: Int

        var rate: Double? {
            guard total > 0 else { return nil }
            return Double(completed) / Double(total)
        }
    }

    /// 直近 `windowDays` 日の集計。
    ///
    /// 期間は「`now` の日の始まり」から数えて `windowDays` 日ぶん遡り、`now` の日の終わりまで。
    func developerStats(
        now: Date = .now,
        windowDays: Int = 30,
        calendar: Calendar = .current
    ) throws -> DeveloperStats {
        let days = max(windowDays, 1)
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        let logs = try modelContext.fetch(
            FetchDescriptor<SessionLog>(
                predicate: #Predicate<SessionLog> { $0.startedAt >= start && $0.startedAt < end }
            )
        )
        let commitments = try modelContext.fetch(
            FetchDescriptor<Commitment>(
                predicate: #Predicate<Commitment> { $0.createdAt >= start && $0.createdAt < end }
            )
        )

        var sessionCounts: [SessionType: SessionCount] = [:]
        var durations: [SessionType: [Double]] = [:]
        for log in logs {
            let type = log.sessionType
            var counts = sessionCounts[type] ?? SessionCount(completed: 0, total: 0)
            counts.total += 1
            if log.completed { counts.completed += 1 }
            sessionCounts[type] = counts

            if let endedAt = log.endedAt {
                let seconds = endedAt.timeIntervalSince(log.startedAt)
                if seconds >= 0 { durations[type, default: []].append(seconds) }
            }
        }

        var outcomeCounts: [CommitmentOutcome: Int] = [:]
        var shrinkTotal = 0
        var voiceless = 0
        var daysWithCommitment: Set<Date> = []
        for commitment in commitments {
            outcomeCounts[commitment.outcome, default: 0] += 1
            shrinkTotal += commitment.shrinkCount
            if commitment.isVoiceless { voiceless += 1 }
            daysWithCommitment.insert(calendar.startOfDay(for: commitment.createdAt))
        }

        return DeveloperStats(
            windowDays: days,
            sessionCount: logs.count,
            completedSessionCount: logs.filter(\.completed).count,
            sessionCountsByType: sessionCounts,
            medianDurationByType: durations.compactMapValues(Self.median(of:)),
            commitmentCount: commitments.count,
            outcomeCounts: outcomeCounts,
            averageShrinkCount: commitments.isEmpty ? 0 : Double(shrinkTotal) / Double(commitments.count),
            voicelessCommitmentCount: voiceless,
            daysWithoutCommitment: max(days - daysWithCommitment.count, 0)
        )
    }

    /// 中央値。件数が偶数なら真ん中 2 つの平均。空なら nil。
    static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
