import Foundation
import OSLog
import SaydoCore

/// 朝・昼・晩の 3 回で追うアラームの段取り（実装計画 §17.9）。
///
/// 「いま登録されているべき回」を `ChaseRules` から計算し、`AlarmScheduling` に頼む。
/// 起動・前面復帰・約束の保存・答えの保存・設定の変更は、すべてここを通る。
///
/// - 登録と取り消しは 1 本の列で順に処理する（起動時の登録し直しの途中で答えが保存されても、
///   答えの後の状態で終わる）。
/// - 同じ起動のあいだ、同じ内容をすでに登録できている日は登録し直さない（前面復帰のたびに
///   鳴っているアラームを取り消して並べ直すのを避ける）。
@MainActor
final class ChaseCoordinator {

    /// その日の約束を引く。無ければ nil。
    typealias CommitmentLookup = @Sendable (Date) async -> CommitmentSnapshot?

    let alarms: any AlarmScheduling
    private let settings: AppSettings
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let commitmentOn: CommitmentLookup
    private let logger = Logger(subsystem: "com.nonturn.saydo", category: "chase")

    /// この起動で登録できた内容。日付（`DayKey`）ごと。
    private var applied: [String: Applied] = [:]
    /// 登録と取り消しの列の末尾。
    private var tail: Task<Void, Never>?

    private struct Applied {
        var plan: [AlarmRoundRequest]
        var outcome: AlarmScheduleOutcome
    }

    init(
        alarms: any AlarmScheduling,
        settings: AppSettings,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
        commitmentOn: @escaping CommitmentLookup
    ) {
        self.alarms = alarms
        self.settings = settings
        self.calendar = calendar
        self.now = now
        self.commitmentOn = commitmentOn
    }

    /// いまの設定と答えの記録から作った規則。
    var rules: ChaseRules { settings.chaseRules(calendar: calendar) }

    // MARK: - 登録し直す

    /// 前日・今日・翌日の分を登録し直す（実装計画 §17.9 の 6）。今日の分の結果を返す。
    ///
    /// - Parameter known: いま保存したばかりの約束。その日の約束は、引き直さずにこれを使う。
    @discardableResult
    func refresh(known: CommitmentSnapshot? = nil) async -> AlarmScheduleOutcome {
        await enqueue { await self.apply(known: known) }
    }

    /// 約束を保存した。その日の答えの記録を消して、登録し直す。今日の分の結果を返す。
    func promiseSaved(_ commitment: CommitmentSnapshot) async -> AlarmScheduleOutcome {
        settings.clearAnsweredRounds(on: commitment.dayKey)
        return await refresh(known: commitment)
    }

    /// 答えを保存した（実装計画 §17.9 の 3）。次に追う回の時刻を返す（無ければ nil）。
    ///
    /// - 「やった」「今日はやめる」: その日の全部の回を答えたことにし、その日のアラームをすべて取り消す。
    /// - 「少しやった」「まだ」: すでに始まっている回だけを答えたことにし、その回だけを取り消す。
    @discardableResult
    func answered(_ answer: FollowUpAnswer, for commitment: CommitmentSnapshot) async -> Date? {
        let moment = now()
        let started = rules.awaitingRounds(for: commitment, asOf: moment).map(\.round)
        let marked = answer.endsTheDay ? Set(AlarmRound.allCases) : Set(started)
        settings.markRoundsAnswered(marked, on: commitment.dayKey)
        let next = rules.nextRound(for: commitment, after: moment)?.start

        await enqueue {
            let day = commitment.createdAt
            if answer.endsTheDay {
                await self.alarms.cancelDay(day)
            } else {
                for round in started {
                    await self.alarms.cancelRound(round, on: day)
                }
            }
            // 取り消した後の姿を、登録済みの内容として覚え直す（次の登録し直しで並べ直さない）。
            if let previous = self.applied[commitment.dayKey] {
                self.applied[commitment.dayKey] = Applied(
                    plan: self.rules.plan(for: day, commitment: commitment),
                    outcome: previous.outcome
                )
            }
            // 翌日の朝の回を登録しておく。
            _ = await self.apply(known: commitment)
        }
        return next
    }

    /// 約束の無い朝に「今日はやめる」と答えた。その日の朝の回を止める。
    func stopMorningPrompt() async {
        settings.morningPromptStoppedDayKey = DayKey.make(from: now(), calendar: calendar)
        await refresh()
    }

    /// このアプリのアラームをすべて取り消す（全削除の後。答える先の無いアラームを残さない）。
    func cancelEverything() async {
        await enqueue {
            self.applied = [:]
            await self.alarms.cancelAll()
        }
    }

    // MARK: - 内部

    private func apply(known: CommitmentSnapshot?) async -> AlarmScheduleOutcome {
        // 旧い識別子で登録したアラーム（開発中の端末に残っているもの）を、1 度だけ取り消す。
        if !settings.legacyAlarmsCleared {
            await alarms.cancelAll()
            applied = [:]
            settings.legacyAlarmsCleared = true
        }

        let moment = now()
        let rules = self.rules
        var todayOutcome = AlarmScheduleOutcome.scheduled(count: 0)

        for offset in [-1, 0, 1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: moment) else { continue }
            let key = DayKey.make(from: day, calendar: calendar)
            let commitment: CommitmentSnapshot?
            if let known, known.dayKey == key {
                commitment = known
            } else {
                commitment = await commitmentOn(day)
            }
            // 前日は、約束があった日だけ見る（深夜の約束の、日付をまたぐ回）。
            if offset < 0, commitment == nil { continue }

            let plan = rules.plan(for: day, commitment: commitment)
            let outcome: AlarmScheduleOutcome
            if let previous = applied[key], previous.plan == plan {
                outcome = previous.outcome
            } else {
                outcome = await alarms.scheduleRounds(plan, on: day)
                if case .scheduled = outcome {
                    applied[key] = Applied(plan: plan, outcome: outcome)
                } else {
                    applied[key] = nil
                }
                logger.info("rounds applied day=\(key, privacy: .public) rounds=\(plan.count, privacy: .public) outcome=\(String(describing: outcome), privacy: .public)")
            }
            if offset == 0 { todayOutcome = outcome }
        }
        return todayOutcome
    }

    /// 登録と取り消しを、頼まれた順に 1 つずつ処理する。
    private func enqueue<Value: Sendable>(_ work: @escaping @MainActor () async -> Value) async -> Value {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }
}
