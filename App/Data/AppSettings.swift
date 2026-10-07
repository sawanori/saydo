import Foundation
import SaydoCore

/// 時刻（時・分）。朝・昼・晩の回の時刻の保存に使う。
///
/// `Date` ではなく時・分で持つのは、日付に依らず「毎日この時刻」を表すため。
struct TimeOfDay: Sendable, Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(minutesFromMidnight: Int) {
        let clamped = min(max(minutesFromMidnight, 0), 24 * 60 - 1)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }

    var minutesFromMidnight: Int { hour * 60 + minute }

    var dateComponents: DateComponents { DateComponents(hour: hour, minute: minute) }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

/// `UserDefaults` に置く設定（実装計画 §10、fix-decisions P1.4）。
///
/// `@MainActor` にしているのは `UserDefaults` が iOS 26.2 SDK で明示的に
/// 非 Sendable（`@_nonSendable(_assumed)`）だから。検査を外す属性で
/// 警告を黙らせず、隔離で解決する。設定を読むのは UI とアラームの登録で、どちらも main。
///
/// 画面（task_013）はこの型を読み書きするだけで、既定値の定義はここに集約する。
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    /// 既定値（実装計画 §6-5、fix-decisions P1.4）。
    enum Default {
        static let morningTime = TimeOfDay(hour: 10, minute: 0)
        static let noonTime = TimeOfDay(hour: 14, minute: 0)
        static let nightTime = TimeOfDay(hour: 19, minute: 0)
        static let hasCompletedOnboarding = false
    }

    private enum Key {
        static let morningTime = "saydo.settings.morningTimeMinutes"
        static let noonTime = "saydo.settings.noonTimeMinutes"
        static let nightTime = "saydo.settings.nightTimeMinutes"
        static let hasCompletedOnboarding = "saydo.settings.hasCompletedOnboarding"
        static let promiseDismissedDayKey = "saydo.settings.promiseDismissedDayKey"
        static let answeredRounds = "saydo.settings.answeredRounds"
        static let morningPromptStoppedDayKey = "saydo.settings.morningPromptStoppedDayKey"
        static let legacyAlarmsCleared = "saydo.settings.legacyAlarmsCleared"

        static let all = [
            morningTime, noonTime, nightTime, hasCompletedOnboarding,
            promiseDismissedDayKey, answeredRounds, morningPromptStoppedDayKey
        ]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: 追う回の時刻

    /// 朝の回（約束を追う 1 回目）の時刻。既定 10:00。
    var morningTime: TimeOfDay {
        get { time(forKey: Key.morningTime) ?? Default.morningTime }
        set { setTime(newValue, forKey: Key.morningTime) }
    }

    /// 昼の回の時刻。既定 14:00。
    var noonTime: TimeOfDay {
        get { time(forKey: Key.noonTime) ?? Default.noonTime }
        set { setTime(newValue, forKey: Key.noonTime) }
    }

    /// 夜の回の時刻。既定 19:00。
    var nightTime: TimeOfDay {
        get { time(forKey: Key.nightTime) ?? Default.nightTime }
        set { setTime(newValue, forKey: Key.nightTime) }
    }

    // MARK: オンボーディング

    var hasCompletedOnboarding: Bool {
        get {
            guard defaults.object(forKey: Key.hasCompletedOnboarding) != nil else {
                return Default.hasCompletedOnboarding
            }
            return defaults.bool(forKey: Key.hasCompletedOnboarding)
        }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    // MARK: 約束する画面

    /// 本人が約束する画面を閉じた日（`DayKey`）。その日は、起動のたびに約束する画面を出し直さない
    /// （今日の画面の主ボタンからは開ける。実装計画 §17.3）。
    var promiseDismissedDayKey: String? {
        get { defaults.string(forKey: Key.promiseDismissedDayKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.promiseDismissedDayKey)
            } else {
                defaults.removeObject(forKey: Key.promiseDismissedDayKey)
            }
        }
    }

    // MARK: 朝・昼・晩の 3 回で追う（実装計画 §17.9）

    /// 覚えておく日数。前日の深夜の約束が今日に掛かることがあるので、数日ぶんを残す。
    private static let answeredRoundsDaysKept = 3

    /// 答えた回。日付（`DayKey`）ごと。「やった」「今日はやめる」は、その日の全部の回を入れる。
    var answeredRounds: [String: Set<AlarmRound>] {
        guard let stored = defaults.dictionary(forKey: Key.answeredRounds) as? [String: [Int]] else { return [:] }
        return stored.mapValues { Set($0.compactMap(AlarmRound.init(rawValue:))) }
    }

    /// その日の、答えた回。
    func answeredRounds(on dayKey: String) -> Set<AlarmRound> {
        answeredRounds[dayKey] ?? []
    }

    /// その日の回を、答えたものとして足す。古い日の記録は捨てる。
    func markRoundsAnswered(_ rounds: Set<AlarmRound>, on dayKey: String) {
        var all = answeredRounds
        all[dayKey, default: []].formUnion(rounds)
        storeAnsweredRounds(all)
    }

    /// その日の答えの記録を消す（その日に新しく約束したとき）。
    func clearAnsweredRounds(on dayKey: String) {
        var all = answeredRounds
        all[dayKey] = nil
        storeAnsweredRounds(all)
    }

    private func storeAnsweredRounds(_ all: [String: Set<AlarmRound>]) {
        // `DayKey` は文字列の順が日付の順になる。新しい方から数日ぶんだけ残す。
        let kept = all.keys.sorted().suffix(Self.answeredRoundsDaysKept)
        var stored: [String: [Int]] = [:]
        for key in kept {
            stored[key] = (all[key] ?? []).map(\.rawValue).sorted()
        }
        defaults.set(stored, forKey: Key.answeredRounds)
    }

    /// 約束の無い朝に「今日はやめる」と答えた日（`DayKey`）。その日の朝の回は鳴らさない。
    var morningPromptStoppedDayKey: String? {
        get { defaults.string(forKey: Key.morningPromptStoppedDayKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.morningPromptStoppedDayKey)
            } else {
                defaults.removeObject(forKey: Key.morningPromptStoppedDayKey)
            }
        }
    }

    /// 旧い識別子（task_058 より前）で登録したアラームを、取り消し終えたか。
    /// 全削除でも消さない（1 度きりの後始末なので）。
    var legacyAlarmsCleared: Bool {
        get { defaults.bool(forKey: Key.legacyAlarmsCleared) }
        set { defaults.set(newValue, forKey: Key.legacyAlarmsCleared) }
    }

    /// 試験用に差し替えた回の時刻。Debug ビルドで起動引数を渡したときだけ値がある。
    var roundOverride: RoundOverride? {
        #if DEBUG
        DebugRounds.stored(defaults: defaults)
        #else
        nil
        #endif
    }

    /// 全部の設定を既定に戻す（テストと「データを全部消す」で使う）。
    func reset() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: 内部

    private func time(forKey key: String) -> TimeOfDay? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return TimeOfDay(minutesFromMidnight: defaults.integer(forKey: key))
    }

    private func setTime(_ time: TimeOfDay, forKey key: String) {
        defaults.set(time.minutesFromMidnight, forKey: key)
    }
}

// MARK: - 画面への橋渡し

extension TimeOfDay {
    /// `DatePicker` の `Date` から時・分だけを取り出す。
    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// `DatePicker` に渡す `Date`。日付の部分に意味は無く、時・分だけを使う。
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
