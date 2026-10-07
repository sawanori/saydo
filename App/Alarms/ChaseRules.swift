import Foundation
import SaydoCore

/// 試験用に差し替えた、ある 1 日の回の時刻（Debug ビルドの起動引数でだけ作られる）。
struct RoundOverride: Sendable, Equatable {
    /// 差し替える日（`DayKey`）。ほかの日には効かない。
    var dayKey: String
    /// 朝・昼・晩の開始時刻。nil なら設定の時刻のまま。
    var starts: [Date]?
    /// 回の中の間隔（秒）。nil なら既定の 3 分。
    var interval: TimeInterval?
}

/// 朝・昼・晩の 3 回まで追う規則（実装計画 §17.9 / §17.10）。
///
/// 設定（回の時刻）と、どの回まで答えたかを写した値。`AppSettings` は MainActor の持ち物なので、
/// `Repository`（別のアクター）や判定の関数へは、この値を渡す。計算は純粋。
struct ChaseRules: Sendable, Equatable {
    var morning: TimeOfDay
    var noon: TimeOfDay
    var night: TimeOfDay
    /// 答えた回。日付（`DayKey`）ごと。「やった」「今日はやめる」は、その日の全部の回を答えたことにする。
    var answeredRounds: [String: Set<AlarmRound>] = [:]
    /// 約束の無い朝に「今日はやめる」と答えた日（`DayKey`）。その日の朝の回は鳴らさない。
    var morningPromptStoppedDayKey: String?
    /// 試験用の差し替え。本番では常に nil。
    var roundOverride: RoundOverride?
    var calendar: Calendar = .current

    // MARK: - 回の時刻

    func dayKey(of date: Date) -> String {
        DayKey.make(from: date, calendar: calendar)
    }

    /// その日の朝・昼・晩の開始時刻。
    func times(on day: Date) -> (morning: Date, noon: Date, evening: Date) {
        if let roundOverride, roundOverride.dayKey == dayKey(of: day),
           let starts = roundOverride.starts, starts.count == 3 {
            return (starts[0], starts[1], starts[2])
        }
        return (
            morning.date(on: day, calendar: calendar),
            noon.date(on: day, calendar: calendar),
            night.date(on: day, calendar: calendar)
        )
    }

    /// その日の、回の中の間隔（秒）。
    func interval(on day: Date) -> TimeInterval {
        if let roundOverride, roundOverride.dayKey == dayKey(of: day), let interval = roundOverride.interval {
            return interval
        }
        return AlarmPlan.defaultInterval
    }

    // MARK: - 約束を追う回

    /// その約束を追う回のすべて（答えたかどうかは見ない）。約束より前の回は入らない。
    func rounds(for commitment: CommitmentSnapshot) -> [AlarmRoundStart] {
        let times = times(on: commitment.createdAt)
        return AlarmPlan.rounds(
            promisedAt: commitment.createdAt,
            morning: times.morning,
            noon: times.noon,
            evening: times.evening
        )
    }

    /// まだ答えていない回。「やった」の約束には無い。
    func pendingRounds(for commitment: CommitmentSnapshot) -> [AlarmRoundStart] {
        guard commitment.outcome != .done else { return [] }
        let answered = answeredRounds[commitment.dayKey] ?? []
        return rounds(for: commitment).filter { !answered.contains($0.round) }
    }

    /// すでに始まっていて、まだ答えていない回。
    func awaitingRounds(for commitment: CommitmentSnapshot, asOf now: Date) -> [AlarmRoundStart] {
        pendingRounds(for: commitment).filter { $0.start <= now }
    }

    /// これから始まる、まだ答えていない回のうち、いちばん早いもの。
    func nextRound(for commitment: CommitmentSnapshot, after now: Date) -> AlarmRoundStart? {
        pendingRounds(for: commitment).first { $0.start > now }
    }

    /// 答えを待っているか（実装計画 §17.9）。
    ///
    /// その日の結果が「やった」でも「今日はやめる」でもなく、すでに始まっている回のうち、
    /// まだ答えていない回がある。対象は、今日の約束か、その回が今日始まった約束（前日の深夜に
    /// 約束した分）だけ。昨日のうちに追い終えた約束を、翌日に蒸し返さない。
    func isAwaitingAnswer(_ commitment: CommitmentSnapshot, asOf now: Date) -> Bool {
        let awaiting = awaitingRounds(for: commitment, asOf: now)
        guard !awaiting.isEmpty else { return false }
        return commitment.dayKey == dayKey(of: now)
            || awaiting.contains { calendar.isDate($0.start, inSameDayAs: now) }
    }

    /// 前日に約束して、追う回が今日になった、まだ答えていない約束か。
    /// 回は約束の日の時刻で決まるので、通常は false（追加の 1 回があった旧い版の名残。試験用の差し替えで日付をまたぐときだけ true になりうる）。
    func isCarriedIntoToday(_ commitment: CommitmentSnapshot, asOf now: Date) -> Bool {
        pendingRounds(for: commitment).contains { calendar.isDate($0.start, inSameDayAs: now) }
    }

    // MARK: - 約束の無い朝

    /// 約束の無い日の、朝の回（約束を促す）が始まっているか。
    func isMorningPromptDue(asOf now: Date) -> Bool {
        guard morningPromptStoppedDayKey != dayKey(of: now) else { return false }
        return times(on: now).morning <= now
    }

    /// 約束する画面に「今日はやめる」を出すか。朝の回がまだ止められておらず、鳴り終えてもいない間だけ出す。
    func canStopMorningPrompt(asOf now: Date) -> Bool {
        guard morningPromptStoppedDayKey != dayKey(of: now) else { return false }
        let end = times(on: now).morning
            .addingTimeInterval(interval(on: now) * Double(AlarmPlan.defaultCount))
        return now < end
    }

    // MARK: - 登録する回

    /// その日に登録しておく回（実装計画 §17.9 の 4〜6）。
    ///
    /// - 約束のある日: まだ答えていない回。約束の声（声で約束した日だけ）で鳴らし、題は「最初にやること」の文字。
    /// - 約束の無い日: 朝の回だけ。既定の音で約束を促す（「今日はやめる」と答えた日は無し）。
    func plan(for day: Date, commitment: CommitmentSnapshot?) -> [AlarmRoundRequest] {
        let interval = interval(on: day)
        if let commitment {
            return pendingRounds(for: commitment).map {
                AlarmRoundRequest(
                    round: $0.round,
                    start: $0.start,
                    interval: interval,
                    voiceRelativePath: commitment.declarationAudioPath,
                    purpose: .chase,
                    title: PromiseCopy.alarmTitle(firstAction: commitment.microAction.text)
                )
            }
        }
        guard morningPromptStoppedDayKey != dayKey(of: day) else { return [] }
        return [
            AlarmRoundRequest(
                round: .morning,
                start: times(on: day).morning,
                interval: interval,
                voiceRelativePath: nil,
                purpose: .prompt
            )
        ]
    }
}

// MARK: - 設定からの写し

extension AppSettings {
    /// いまの設定と答えの記録から、追う規則を作る。
    func chaseRules(calendar: Calendar = .current) -> ChaseRules {
        ChaseRules(
            morning: morningTime,
            noon: noonTime,
            night: nightTime,
            answeredRounds: answeredRounds,
            morningPromptStoppedDayKey: morningPromptStoppedDayKey,
            roundOverride: roundOverride,
            calendar: calendar
        )
    }
}

// MARK: - 試験用の短縮（Debug ビルドだけ）

#if DEBUG
/// 回の時刻を、起動引数で「いまから数分後」に差し替える（task_058 の実機確認用）。
///
/// - `-saydoRoundsInMinutes 2,5,8`: この起動の時刻から 2 分後・5 分後・8 分後を、今日の朝・昼・晩の時刻にする。
/// - `-saydoRoundInterval 60`: 今日の、回の中の間隔を 60 秒にする。
/// - `-saydoRoundsReset`: 覚えている差し替えを消す。
///
/// 差し替えは `UserDefaults` に覚えておき、同じ日のうちは引数なしで開き直しても同じ時刻を使う
/// （`AppSettings` の朝・昼・夜の時刻は書き換えない）。日付が変わると効かなくなる。
enum DebugRounds {
    static let roundsArgument = "-saydoRoundsInMinutes"
    static let intervalArgument = "-saydoRoundInterval"
    static let resetArgument = "-saydoRoundsReset"

    private enum Key {
        static let dayKey = "saydo.debug.rounds.dayKey"
        static let starts = "saydo.debug.rounds.starts"
        static let interval = "saydo.debug.rounds.interval"
    }

    /// 起動引数を読んで、差し替えを覚える・消す。引数が無ければ何もしない。
    @MainActor
    static func applyLaunchArguments(
        _ arguments: [String],
        defaults: UserDefaults,
        now: Date,
        calendar: Calendar = .current
    ) {
        if arguments.contains(resetArgument) {
            clear(defaults: defaults)
        }
        let minutes = value(after: roundsArgument, in: arguments).flatMap(parseMinutes)
        let interval = value(after: intervalArgument, in: arguments)
            .flatMap(TimeInterval.init)
            .flatMap { $0 >= 1 ? $0 : nil }
        guard minutes != nil || interval != nil else { return }

        let today = DayKey.make(from: now, calendar: calendar)
        // 別の日の差し替えが残っていたら、引き継がない。
        if defaults.string(forKey: Key.dayKey) != today {
            clear(defaults: defaults)
        }
        defaults.set(today, forKey: Key.dayKey)
        if let minutes {
            let starts = minutes.map { now.addingTimeInterval(Double($0) * 60).timeIntervalSinceReferenceDate }
            defaults.set(starts, forKey: Key.starts)
        }
        if let interval {
            defaults.set(interval, forKey: Key.interval)
        }
    }

    /// 覚えている差し替え。無ければ nil。
    @MainActor
    static func stored(defaults: UserDefaults) -> RoundOverride? {
        guard let dayKey = defaults.string(forKey: Key.dayKey) else { return nil }
        let starts = (defaults.array(forKey: Key.starts) as? [Double])?
            .map(Date.init(timeIntervalSinceReferenceDate:))
        let interval = defaults.object(forKey: Key.interval) == nil ? nil : defaults.double(forKey: Key.interval)
        guard starts != nil || interval != nil else { return nil }
        return RoundOverride(dayKey: dayKey, starts: starts?.count == 3 ? starts : nil, interval: interval)
    }

    @MainActor
    static func clear(defaults: UserDefaults) {
        for key in [Key.dayKey, Key.starts, Key.interval] {
            defaults.removeObject(forKey: key)
        }
    }

    /// 「2,5,8」を、昇順の 3 つの分に直す。形が違えば nil。
    static func parseMinutes(_ text: String) -> [Int]? {
        let parts = text.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3 else { return nil }
        let minutes = parts.compactMap { $0 }
        guard minutes.count == 3, minutes.allSatisfy({ $0 >= 0 }), minutes == minutes.sorted() else { return nil }
        return minutes
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
