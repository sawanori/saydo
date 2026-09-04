import Foundation
import SaydoCore

/// 時刻（時・分）。通知時刻の保存に使う。
///
/// `Date` ではなく時・分で持つのは、通知が
/// `UNCalendarNotificationTrigger` の `DateComponents` を必要とするため。
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

/// 固定通知の本数（retention-strategy.md R2、fix-decisions B）。
///
/// 行動時刻の通知（朝 M4 で登録する 1 回）はモードに関係なく常に出す。
enum NotificationMode: String, Sendable, Codable, Hashable, CaseIterable {
    /// 既定。固定通知は朝だけ。行動時刻と合わせて 1 日 2 回。
    case twoPerDay = "two"
    /// 昼と夜の固定通知を足す。
    case threePerDay = "three"

    /// このモードで出す固定通知のセッション。
    var fixedSessionTypes: [SessionType] {
        switch self {
        case .twoPerDay: [.morning]
        case .threePerDay: [.morning, .noon, .night]
        }
    }
}

/// `UserDefaults` に置く設定（実装計画 §10、fix-decisions P1.4）。
///
/// `@MainActor` にしているのは `UserDefaults` が iOS 26.2 SDK で明示的に
/// 非 Sendable（`@_nonSendable(_assumed)`）だから。検査を外す属性で
/// 警告を黙らせず、隔離で解決する。設定を読むのは UI と通知登録で、どちらも main。
///
/// 画面（task_013）はこの型を読み書きするだけで、既定値の定義はここに集約する。
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    /// 既定値（実装計画 §6-5、fix-decisions P1.4）。
    enum Default {
        static let morningTime = TimeOfDay(hour: 8, minute: 0)
        static let noonTime = TimeOfDay(hour: 13, minute: 0)
        static let nightTime = TimeOfDay(hour: 21, minute: 0)
        /// 無音がこの秒数続いたら発話終了（実装計画 §7.3）。
        static let silenceThresholdSeconds = 1.5
        static let notificationMode = NotificationMode.twoPerDay
        /// 週末の固定通知。既定は出す。止めたい人が設定で切る（retention-strategy.md R2）。
        static let weekendNotificationsEnabled = true
        static let hasCompletedOnboarding = false
        /// 「話せない時」を自動で使う時間帯（task_013 の scope 末尾）。既定は使わない。
        static let quietModeScheduleEnabled = false
        static let quietModeStart = TimeOfDay(hour: 9, minute: 0)
        static let quietModeEnd = TimeOfDay(hour: 18, minute: 0)
    }

    /// 設定画面で選べる無音秒数（実装計画 §7.3）。
    static let silenceThresholdChoices: [Double] = [1.2, 1.5, 2.0]

    private enum Key {
        static let morningTime = "saydo.settings.morningTimeMinutes"
        static let noonTime = "saydo.settings.noonTimeMinutes"
        static let nightTime = "saydo.settings.nightTimeMinutes"
        static let silenceThreshold = "saydo.settings.silenceThresholdSeconds"
        static let speechVoiceIdentifier = "saydo.settings.speechVoiceIdentifier"
        static let notificationMode = "saydo.settings.notificationMode"
        static let weekendNotificationsEnabled = "saydo.settings.weekendNotificationsEnabled"
        static let aloneTime = "saydo.settings.aloneTimeMinutes"
        static let hasCompletedOnboarding = "saydo.settings.hasCompletedOnboarding"
        static let quietModeScheduleEnabled = "saydo.settings.quietModeScheduleEnabled"
        static let quietModeStart = "saydo.settings.quietModeStartMinutes"
        static let quietModeEnd = "saydo.settings.quietModeEndMinutes"

        static let all = [
            morningTime, noonTime, nightTime, silenceThreshold, speechVoiceIdentifier,
            notificationMode, weekendNotificationsEnabled, aloneTime, hasCompletedOnboarding,
            quietModeScheduleEnabled, quietModeStart, quietModeEnd
        ]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: 通知

    /// 朝の固定通知の時刻。既定 8:00。
    var morningTime: TimeOfDay {
        get { time(forKey: Key.morningTime) ?? Default.morningTime }
        set { setTime(newValue, forKey: Key.morningTime) }
    }

    /// 昼の固定通知の時刻。既定 13:00（`threePerDay` のときだけ使う）。
    var noonTime: TimeOfDay {
        get { time(forKey: Key.noonTime) ?? Default.noonTime }
        set { setTime(newValue, forKey: Key.noonTime) }
    }

    /// 夜の固定通知の時刻。既定 21:00（`threePerDay` のときだけ使う）。
    var nightTime: TimeOfDay {
        get { time(forKey: Key.nightTime) ?? Default.nightTime }
        set { setTime(newValue, forKey: Key.nightTime) }
    }

    var notificationMode: NotificationMode {
        get {
            guard let raw = defaults.string(forKey: Key.notificationMode),
                  let mode = NotificationMode(rawValue: raw) else {
                return Default.notificationMode
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.notificationMode) }
    }

    /// 週末（土日）に固定通知を出すか。
    var weekendNotificationsEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.weekendNotificationsEnabled) != nil else {
                return Default.weekendNotificationsEnabled
            }
            return defaults.bool(forKey: Key.weekendNotificationsEnabled)
        }
        set { defaults.set(newValue, forKey: Key.weekendNotificationsEnabled) }
    }

    /// 一人で話せる時間（retention-strategy.md R1）。
    /// 宣言を後回しにしたときに「30 秒だけ、声で約束して」を 1 回だけ送る時刻。
    /// オンボーディングで聞くまでは nil で、その間は夜の時刻を代わりに使う。
    var aloneTime: TimeOfDay? {
        get { time(forKey: Key.aloneTime) }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.aloneTime)
                return
            }
            setTime(newValue, forKey: Key.aloneTime)
        }
    }

    /// 宣言の後回し通知に使う時刻。未設定なら夜の時刻。
    var effectiveAloneTime: TimeOfDay { aloneTime ?? nightTime }

    /// 指定したセッションの固定通知の時刻。モードで出さないセッションは nil。
    func fixedNotificationTime(for sessionType: SessionType) -> TimeOfDay? {
        guard notificationMode.fixedSessionTypes.contains(sessionType) else { return nil }
        switch sessionType {
        case .morning: return morningTime
        case .noon: return noonTime
        case .night: return nightTime
        case .adhoc: return nil
        }
    }

    // MARK: 音声

    /// 無音がこの秒数続いたら発話終了とみなす。既定 1.5 秒。
    var silenceThresholdSeconds: Double {
        get {
            guard defaults.object(forKey: Key.silenceThreshold) != nil else {
                return Default.silenceThresholdSeconds
            }
            let stored = defaults.double(forKey: Key.silenceThreshold)
            return Self.silenceThresholdChoices.contains(stored) ? stored : Default.silenceThresholdSeconds
        }
        set {
            let chosen = Self.silenceThresholdChoices.contains(newValue) ? newValue : Default.silenceThresholdSeconds
            defaults.set(chosen, forKey: Key.silenceThreshold)
        }
    }

    /// `AVSpeechSynthesisVoice` の識別子。未設定なら端末の既定音声を使う。
    var speechVoiceIdentifier: String? {
        get { defaults.string(forKey: Key.speechVoiceIdentifier) }
        set {
            guard let newValue, !newValue.isEmpty else {
                defaults.removeObject(forKey: Key.speechVoiceIdentifier)
                return
            }
            defaults.set(newValue, forKey: Key.speechVoiceIdentifier)
        }
    }

    // MARK: 「話せない時」を自動で使う時間帯

    /// 決めた時間帯に開いたセッションを、最初から選択肢 + テキスト経路で始めるか（task_013 の scope 末尾）。
    var quietModeScheduleEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.quietModeScheduleEnabled) != nil else {
                return Default.quietModeScheduleEnabled
            }
            return defaults.bool(forKey: Key.quietModeScheduleEnabled)
        }
        set { defaults.set(newValue, forKey: Key.quietModeScheduleEnabled) }
    }

    /// 時間帯の開始。既定 9:00。
    var quietModeStart: TimeOfDay {
        get { time(forKey: Key.quietModeStart) ?? Default.quietModeStart }
        set { setTime(newValue, forKey: Key.quietModeStart) }
    }

    /// 時間帯の終了。既定 18:00。
    var quietModeEnd: TimeOfDay {
        get { time(forKey: Key.quietModeEnd) ?? Default.quietModeEnd }
        set { setTime(newValue, forKey: Key.quietModeEnd) }
    }

    /// その時刻が「話せない時」の時間帯に入っているか。
    ///
    /// 設定が切ってあれば常に false。開始と同じ時刻は含み、終了と同じ時刻は含まない。
    func isQuietMode(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietModeScheduleEnabled else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return Self.isWithin(minutesFromMidnight: minutes, start: quietModeStart, end: quietModeEnd)
    }

    /// 時間帯の判定（純計算）。
    ///
    /// 終了が開始より前なら日をまたぐ帯として扱う（22:00〜6:00 なら 23:00 も 5:00 も中）。
    /// 開始と終了が同じときは幅が 0 の帯なので、どの時刻も外とする。
    static func isWithin(minutesFromMidnight minutes: Int, start: TimeOfDay, end: TimeOfDay) -> Bool {
        let startMinutes = start.minutesFromMidnight
        let endMinutes = end.minutesFromMidnight
        if startMinutes == endMinutes { return false }
        if startMinutes < endMinutes {
            return minutes >= startMinutes && minutes < endMinutes
        }
        return minutes >= startMinutes || minutes < endMinutes
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

// MARK: - 画面と通知計画への橋渡し

extension TimeOfDay {
    /// 通知計画（`SaydoCore.NotificationPlan`）が使う型へ写す。
    var core: SaydoCore.TimeOfDay { SaydoCore.TimeOfDay(hour: hour, minute: minute) }

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

extension NotificationMode {
    /// 通知計画が使うモードへ写す。
    var core: SaydoCore.NotificationMode {
        switch self {
        case .twoPerDay: .twice
        case .threePerDay: .thrice
        }
    }
}

extension AppSettings {
    /// `NotificationScheduler.reschedule(settings:)` に渡す形。
    ///
    /// 画面がそれぞれ組み立てると食い違うので、変換はここ 1 か所に置く。
    var notificationSettings: SaydoCore.NotificationSettings {
        SaydoCore.NotificationSettings(
            morning: morningTime.core,
            noon: noonTime.core,
            night: nightTime.core,
            mode: notificationMode.core,
            weekendEnabled: weekendNotificationsEnabled
        )
    }
}
