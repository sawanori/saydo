import Foundation

/// 追い始める時刻のチップ（実装計画 §17.1-4）。
public enum PromiseChip: String, Sendable, Hashable, Codable, CaseIterable {
    /// 30 分後。
    case inThirtyMinutes
    /// 1 時間後。選ばなければこれになる。
    case inOneHour
    /// 昼 12:00。
    case noon
    /// 夕方 18:00。
    case evening
}

/// いまの時刻から決めたチップ 1 つぶん。
public struct PromiseTimeOption: Sendable, Hashable {
    public let chip: PromiseChip
    /// 追い始める日時。
    public let date: Date

    public init(chip: PromiseChip, date: Date) {
        self.chip = chip
        self.date = date
    }

    /// ボタンに出す文言。
    public var label: String {
        PromiseCopy.chipLabel(chip)
    }
}

/// 追い始める時刻のチップを日時にする（実装計画 §17.4）。
///
/// 純計算だけを行う。過ぎた枠（昼・夕方）は返さない。「30 分後」「1 時間後」は常に未来なので必ず返る。
public enum PromiseTime {

    /// 選ばなかったときのチップ。
    public static let defaultChip: PromiseChip = .inOneHour

    /// 昼の時刻（時）。
    public static let noonHour = 12

    /// 夕方の時刻（時）。
    public static let eveningHour = 18

    /// 30 分後の間隔。
    public static let thirtyMinutes: TimeInterval = 30 * 60

    /// 1 時間後の間隔。
    public static let oneHour: TimeInterval = 60 * 60

    /// いま選べるチップ。`PromiseChip.allCases` の順（30 分後、1 時間後、昼、夕方）で、過ぎたものを除く。
    public static func options(now: Date, calendar: Calendar = .current) -> [PromiseTimeOption] {
        PromiseChip.allCases.compactMap { chip in
            date(for: chip, now: now, calendar: calendar).map { PromiseTimeOption(chip: chip, date: $0) }
        }
    }

    /// チップの日時。昼・夕方がすでに過ぎている（`now` 以前）なら nil。
    public static func date(for chip: PromiseChip, now: Date, calendar: Calendar = .current) -> Date? {
        switch chip {
        case .inThirtyMinutes:
            return now.addingTimeInterval(thirtyMinutes)
        case .inOneHour:
            return now.addingTimeInterval(oneHour)
        case .noon:
            return todayAt(hour: noonHour, now: now, calendar: calendar)
        case .evening:
            return todayAt(hour: eveningHour, now: now, calendar: calendar)
        }
    }

    /// 選ばなかったときの追い始める日時（1 時間後）。
    public static func defaultDate(now: Date, calendar: Calendar = .current) -> Date {
        now.addingTimeInterval(oneHour)
    }

    /// 当日の指定の時（0 分 0 秒）。`now` より後でなければ nil。
    private static func todayAt(hour: Int, now: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        components.second = 0
        guard let date = calendar.date(from: components), date > now else { return nil }
        return date
    }
}
