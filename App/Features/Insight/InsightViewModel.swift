import Foundation
import Observation
import SaydoCore

// MARK: - 表示用のデータ

/// 「逃げる理由」の 1 段（帯と凡例の 1 行）。
struct ReasonShare: Sendable, Equatable, Identifiable {
    var reason: ReasonCategory
    /// 0.0〜1.0。母数は理由が付いている宣言の件数（実装計画 §7.6）。
    var ratio: Double

    var id: ReasonCategory { reason }
}

/// `WeeklyInsightView` が描くもの。
///
/// 宣言の結果内訳・達成率・平均縮小回数は持たない（fix-decisions P2.2）。
/// 分野の件数も持たない（画面に件数を出さないため。design-notes §画面別 6）。
struct WeeklyInsight: Sendable, Equatable {
    /// 集計期間の最初の日。
    var firstDay: Date
    /// 集計期間の最後の日（当日）。
    var lastDay: Date
    /// あなたが逃げやすいこと（上位 5）。
    var topDomains: [TaskDomain]
    /// 逃げる理由（割合の降順。`SaydoTheme.Palette.accentRamp` の段数まで）。
    var reasons: [ReasonShare]
    /// 振り返り 1 文。
    var reflection: String
}

// MARK: - ViewModel

/// Timeline 上部の 1 行インサイトと `WeeklyInsightView` の状態（task_016、retention R9）。
///
/// 読み出しは `Repository`（`@ModelActor`）に閉じ、集計は `InsightCalculator`（純関数）に任せる。
@MainActor
@Observable
final class InsightViewModel {

    /// 表示する 3 状態（実装計画 §8「WeeklyInsightView」の行）。
    enum State: Equatable {
        /// 記録が 3 件に満たない、または偏りがまだ見えない。何も出さない。
        case insufficient
        /// 3 件以上・7 日未満。週次を待たずに出す 1 行（retention R9）。
        case firstInsight(line: String)
        /// 7 日そろった。上位 5・理由の割合・振り返り 1 文。
        case weekly(WeeklyInsight)
    }

    /// 集計する日数。
    static let periodDays = 7
    /// 「あなたが逃げやすいこと」に出す分野の数。
    static let domainLimit = 5
    /// 「逃げる理由」の帯に出す段数（`SaydoTheme.Palette.accentRamp` の段数と同じ）。
    static let reasonLimit = 4

    private(set) var state: State = .insufficient

    private let repository: Repository
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Tier A の振り返り 1 文の差し込み口（task_015 が `DialogueEngine.weeklyReflection` を渡す）。
    ///
    /// 渡された文が `Guardrails` を通らないとき、または失敗したときは
    /// `InsightCalculator` のテンプレートに落とす（実装計画 §7.5「違反時」）。
    private let reflectionProvider: (@Sendable (WeeklyStats) async throws -> String)?

    init(
        repository: Repository,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now },
        reflectionProvider: (@Sendable (WeeklyStats) async throws -> String)? = nil
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
        self.reflectionProvider = reflectionProvider

        // 生成した時点で 1 回読む。記録が足りない間 `InsightCardView` は `EmptyView` を返し、
        // `EmptyView` には表示物が無いので `.task` が実行されない。読み込みの起点をここに置く。
        // 記録が増えたときは `load()` を呼び直す。
        Task { await load() }
    }

    /// Timeline 上部のカードに出す 1 行。何も出さないときは nil。
    var cardLine: String? {
        switch state {
        case .insufficient: nil
        case .firstInsight(let line): line
        case .weekly(let insight): insight.reflection
        }
    }

    /// 保存済みの記録から状態を作り直す。
    ///
    /// 読み出しに失敗したときはカードを出さない。振り返りは補助的な画面であり、
    /// 読めなかったことを本人に突きつける画面ではないため（企画原則 §22-1）。
    func load() async {
        do {
            state = try await makeState()
        } catch {
            state = .insufficient
        }
    }

    private func makeState() async throws -> State {
        let recordedCount = try await repository.recordedCommitmentCount()
        guard recordedCount >= InsightCalculator.firstInsightThreshold else { return .insufficient }

        let today = now()
        let period = InsightPeriod.make(endingAt: today, days: Self.periodDays, calendar: calendar)
        let stats = try await repository.weeklyStats(from: period.start, to: period.end)

        if try await hasFullPeriod(endingAt: today),
           stats.totalCount >= InsightCalculator.firstInsightThreshold {
            let reflection = await reflection(for: stats)
            return .weekly(
                WeeklyInsight(
                    firstDay: period.start,
                    lastDay: calendar.startOfDay(for: today),
                    topDomains: stats.topDomains(limit: Self.domainLimit),
                    reasons: stats.topReasons(limit: Self.reasonLimit).map { reason in
                        ReasonShare(reason: reason, ratio: stats.reasonRatios[reason] ?? 0)
                    },
                    reflection: reflection
                )
            )
        }

        let inputs = try await repository.insightInputs(
            endingAt: today,
            days: Self.periodDays,
            calendar: calendar
        )
        guard let line = InsightCalculator.firstInsight(from: inputs) else { return .insufficient }
        return .firstInsight(line: line)
    }

    /// 最初の記録から `periodDays` 日ぶんの暦日が経っているか。
    private func hasFullPeriod(endingAt date: Date) async throws -> Bool {
        guard let first = try await repository.firstCommitmentDate() else { return false }
        let elapsed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: first),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return elapsed + 1 >= Self.periodDays
    }

    private func reflection(for stats: WeeklyStats) async -> String {
        let template = InsightCalculator.weeklyReflection(for: stats)
        guard let reflectionProvider else { return template }
        do {
            let generated = try await reflectionProvider(stats)
            return Guardrails.sanitize(generated, form: .statement, fallback: template).text
        } catch {
            return template
        }
    }
}
