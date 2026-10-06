import Foundation
import SaydoCore

/// 答える画面（task_055）が使う読み書き。
///
/// `Repository.swift` 本体には足さない（並行する task_054 が同じファイルを触るため）。
extension Repository {

    /// 追い始めた後で、まだ答えていない約束。無ければ nil（実装計画 §17.3「答える」）。
    ///
    /// 当日の約束を先に見る。深夜に「1時間後」で約束すると追い始める時刻が翌日になるので、
    /// 当日に無ければ前日の約束も見る（その約束の追い始めが `now` より前のときだけ該当する）。
    func commitmentAwaitingAnswer(asOf now: Date = .now, calendar: Calendar = .current) throws -> CommitmentSnapshot? {
        var candidates: [CommitmentSnapshot] = []
        if let today = try todayCommitment(on: now, calendar: calendar) {
            candidates.append(today)
        }
        if let previousDay = calendar.date(byAdding: .day, value: -1, to: now),
           let previous = try todayCommitment(on: previousDay, calendar: calendar) {
            candidates.append(previous)
        }
        return candidates.first { FollowUpRule.isAwaitingAnswer($0, asOf: now, calendar: calendar) }
    }
}

/// 「追い始めた後で答えがまだ」の判定と、連鎖の開始日。
enum FollowUpRule {

    /// 連鎖の開始時刻。アラームの識別子は**この日付**で決まる（`AlarmPlan`）。
    /// 追い始める時刻を持たない古い約束は、作った時刻で代える。
    static func chainStart(of commitment: CommitmentSnapshot) -> Date {
        commitment.plannedAt ?? commitment.createdAt
    }

    /// 追い始めていて、まだ答えていないか。
    ///
    /// 対象は、今日の約束か、追い始める時刻が今日の約束（前日の深夜に約束した分）だけ。
    /// 昨日のうちに追い終えた約束を、翌日に蒸し返さない。
    static func isAwaitingAnswer(_ commitment: CommitmentSnapshot, asOf now: Date, calendar: Calendar = .current) -> Bool {
        guard commitment.outcome == .pending, let start = commitment.plannedAt, start <= now else { return false }
        return commitment.dayKey == DayKey.make(from: now, calendar: calendar)
            || calendar.isDate(start, inSameDayAs: now)
    }
}

/// 答える画面が結果を書く先。`Repository` は `@ModelActor` の具象アクターなので、
/// テストで保存の失敗を起こせるようにこの契約を挟む（`SessionStore` と同じ理由）。
protocol FollowUpStore: Sendable {
    /// 結果を書く。やった = `.done`、少しやった = `.partial`、今日はやめる = `.notYet`。
    func saveOutcome(commitmentID: UUID, outcome: CommitmentOutcome) async throws
}

/// `Repository` を `FollowUpStore` として渡すための薄い包み。
struct RepositoryFollowUpStore: FollowUpStore {
    let repository: Repository

    init(_ repository: Repository) {
        self.repository = repository
    }

    func saveOutcome(commitmentID: UUID, outcome: CommitmentOutcome) async throws {
        try await repository.updateOutcome(commitmentID: commitmentID, outcome: outcome)
    }
}
