import Foundation
import SaydoCore

/// 答える画面（task_055）が使う読み書き。
///
/// `Repository.swift` 本体には足さない（並行する task_054 が同じファイルを触るため）。
extension Repository {

    /// 答えを待っている約束。無ければ nil（実装計画 §17.9）。
    ///
    /// その日の結果が「やった」でも「今日はやめる」でもなく、すでに始まっている回のうち、
    /// まだ答えていない回がある約束。当日の約束を先に見る。回は約束した日の時刻で決まり、最後の回を
    /// 過ぎてからの約束には回が無い。前日の約束も見るが、今日始まる回があるときだけ該当する（通常は無い）。
    func commitmentAwaitingAnswer(asOf now: Date = .now, rules: ChaseRules) throws -> CommitmentSnapshot? {
        let calendar = rules.calendar
        var candidates: [CommitmentSnapshot] = []
        if let today = try todayCommitment(on: now, calendar: calendar) {
            candidates.append(today)
        }
        if let previousDay = calendar.date(byAdding: .day, value: -1, to: now),
           let previous = try todayCommitment(on: previousDay, calendar: calendar) {
            candidates.append(previous)
        }
        return candidates.first { rules.isAwaitingAnswer($0, asOf: now) }
    }

    /// いま扱っている約束。今日の約束か、前日の深夜に約束して追う回が今日になった、答えがまだの約束。
    /// 無ければ nil（＝今日は約束できる）。入口の判定と今日の画面が同じものを見るために使う。
    func commitmentInPlay(asOf now: Date = .now, rules: ChaseRules) throws -> CommitmentSnapshot? {
        let calendar = rules.calendar
        if let today = try todayCommitment(on: now, calendar: calendar) {
            return today
        }
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: now),
              let previous = try todayCommitment(on: previousDay, calendar: calendar),
              rules.isCarriedIntoToday(previous, asOf: now)
        else { return nil }
        return previous
    }
}

/// 答える画面が結果を書く先。`Repository` は `@ModelActor` の具象アクターなので、
/// テストで保存の失敗を起こせるようにこの契約を挟む（`PromiseStore` と同じ理由）。
protocol FollowUpStore: Sendable {
    /// 結果を書く。やった = `.done`、少しやった = `.partial`、まだ・今日はやめる = `.notYet`。
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
        // 「やった」は、逃げていた対象を終わったものにする（旧い昼の会話と同じ扱い）。
        // 結果はもう保存できているので、ここで失敗しても答えは成立させる（アラームを止めるのが先）。
        if outcome == .done {
            try? await repository.updateAvoidanceStatus(commitmentID: commitmentID, status: .done)
        }
    }
}
