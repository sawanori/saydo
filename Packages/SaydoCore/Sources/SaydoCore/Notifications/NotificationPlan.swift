import Foundation

// MARK: - 設定

/// 時刻（時・分）だけを持つ値。オンボーディングと設定画面で決める 3 つの時刻に使う。
public struct TimeOfDay: Sendable, Codable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// 0 時からの経過分。比較と差分の計算に使う。
    public var minutesFromMidnight: Int {
        hour * 60 + minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

/// 固定通知の枠。識別子の接頭辞になる。
///
/// `action` は朝の宣言（M4）が終わってはじめて時刻が決まるので固定通知には数えない。
public enum NotificationSlot: String, Sendable, Codable, Hashable, CaseIterable {
    case morning
    case noon
    case night
    case action

    /// この通知から始めるセッション。`userInfo` に入れる値。
    ///
    /// 行動時刻通知は「朝の宣言を再生して状態を聞く」ので昼と同じ `NoonFlow` に入る（実装計画 §7.2）。
    public var sessionType: SessionType {
        switch self {
        case .morning: .morning
        case .noon, .action: .noon
        case .night: .night
        }
    }
}

/// 通知の本数モード（retention-strategy R2）。
///
/// 既定は「朝の固定 1 本 + 行動時刻 1 本」。昼と夜の固定通知は設定で足す。
public enum NotificationMode: String, Sendable, Codable, Hashable, CaseIterable {
    /// 既定。朝の固定通知 + 行動時刻の通知。
    case twice
    /// 朝・昼・夜の固定通知 + 行動時刻の通知。
    case thrice

    /// このモードで毎日出す固定通知の枠。
    public var fixedSlots: [NotificationSlot] {
        switch self {
        case .twice: [.morning]
        case .thrice: [.morning, .noon, .night]
        }
    }

    /// 1 日あたりの固定通知の本数。行動時刻通知は当日分しか決まらないので数えない。
    public var fixedNotificationsPerDay: Int {
        fixedSlots.count
    }
}

/// 通知設定。
public struct NotificationSettings: Sendable, Codable, Hashable {
    public var morning: TimeOfDay
    public var noon: TimeOfDay
    public var night: TimeOfDay
    public var mode: NotificationMode
    /// 週末（土日）に固定通知を出すか。`false` が「週末オフ」（retention-strategy R2）。
    public var weekendEnabled: Bool

    public init(
        morning: TimeOfDay,
        noon: TimeOfDay,
        night: TimeOfDay,
        mode: NotificationMode = .twice,
        weekendEnabled: Bool = true
    ) {
        self.morning = morning
        self.noon = noon
        self.night = night
        self.mode = mode
        self.weekendEnabled = weekendEnabled
    }

    /// 枠に対応する固定時刻。`action` は設定ではなく本人の宣言で決まるので nil。
    public func time(for slot: NotificationSlot) -> TimeOfDay? {
        switch slot {
        case .morning: morning
        case .noon: noon
        case .night: night
        case .action: nil
        }
    }
}

// MARK: - 入力

/// 当日の Commitment の状態。
///
/// - 宣言前: `plannedAt == nil`、`outcome == .pending`
/// - 宣言後: `plannedAt != nil`、`outcome == .pending`
/// - 昼の確認後: `outcome` が `.done` / `.partial` / `.notYet`
public struct DayCommitment: Sendable, Codable, Hashable {
    /// 本人が決めた行動時刻。朝の M4 が終わるまで nil。
    public var plannedAt: Date?
    /// 宣言の結果。
    public var outcome: CommitmentOutcome

    public init(plannedAt: Date? = nil, outcome: CommitmentOutcome = .pending) {
        self.plannedAt = plannedAt
        self.outcome = outcome
    }

    /// まだ何も宣言していない状態。
    public static let noCommitment = DayCommitment()
}

// MARK: - 出力

/// 登録する非繰り返しトリガー 1 本ぶん。
public struct NotificationRegistration: Sendable, Hashable {
    /// `<枠>-yyyyMMdd`。例: `morning-20260904`、`action-20260904`。
    public let identifier: String
    /// 発火日時。
    public let fireDate: Date
    /// どの枠か。
    public let slot: NotificationSlot
    /// 本文のキー。文言は `NotificationCopy` が持つ。
    public let copyKey: NotificationCopyKey

    /// `userInfo` に入れるセッション種別。通知タップでこのフローが自動で始まる。
    public var sessionType: SessionType {
        slot.sessionType
    }

    public init(identifier: String, fireDate: Date, slot: NotificationSlot, copyKey: NotificationCopyKey) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.slot = slot
        self.copyKey = copyKey
    }
}

/// 通知の登録計画（実装計画 §7.4、retention-strategy R2・R3）。
///
/// 繰り返しトリガーは使わず、1 日ぶんずつ日時を確定させた非繰り返しトリガーを先読みで並べる。
/// 当日の Commitment の状態で昼と行動時刻の扱いが変わるため、繰り返しトリガーでは表現できない。
///
/// この型は純計算しか行わない。`UNUserNotificationCenter` への登録は App 側の
/// `NotificationScheduler`（task_009 のアプリ部分）が担当する。
public struct NotificationPlan: Sendable, Hashable {
    /// 登録する通知。発火日時の昇順。
    public let registrations: [NotificationRegistration]
    /// この計画で当日ぶんを意図的に取り消す識別子（昼のスキップ規則、`done` / `partial` による取り消し）。
    public let cancelledIdentifiers: [String]

    public init(registrations: [NotificationRegistration], cancelledIdentifiers: [String]) {
        self.registrations = registrations
        self.cancelledIdentifiers = cancelledIdentifiers
    }

    // MARK: - 予算

    /// 一度に保留させる通知の上限。iOS の保留通知上限（64 本）に対して余裕を取った値。
    public static let pendingBudget = 50

    /// 先読みする最長日数。これ以上先の時刻設定は変更されている可能性が高いので延ばさない。
    public static let maxHorizonDays = 30

    /// 先読みする日数。`1 日あたりの固定通知本数 × 日数 ≤ pendingBudget` に収まる最長。
    ///
    /// - 2 回モード（固定 1 本 / 日）: 30 日（`maxHorizonDays` で頭打ち）
    /// - 3 回モード（固定 3 本 / 日）: 16 日（`50 / 3` の切り捨て）
    public static func planningDayCount(for mode: NotificationMode) -> Int {
        min(maxHorizonDays, pendingBudget / mode.fixedNotificationsPerDay)
    }

    /// 固定の昼通知と行動時刻通知が「重なっている」とみなす間隔（実装計画 §7.4）。
    public static let noonOverlapWindow: TimeInterval = 30 * 60

    // MARK: - 識別子

    /// 識別子に使う日付印（`yyyyMMdd`）。
    public static func dayStamp(for day: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// `<枠>-yyyyMMdd` 形式の識別子。
    public static func identifier(for slot: NotificationSlot, day: Date, calendar: Calendar) -> String {
        "\(slot.rawValue)-\(dayStamp(for: day, calendar: calendar))"
    }

    // MARK: - 計算

    /// 通知の登録計画を作る。
    ///
    /// - Parameters:
    ///   - now: 計画を立てる時刻。これより後の時刻だけを登録する（過ぎた枠は翌日以降に繰り越す）。
    ///   - settings: 3 つの時刻・モード・週末の扱い。
    ///   - today: 当日の Commitment の状態。
    ///   - calendar: 日付の計算に使う暦。
    ///
    /// 規則:
    /// 1. 固定通知は `planningDayCount(for:)` 日ぶんを先読みし、`now` より後のものだけ登録する。
    /// 2. 週末オフのときは土日の固定通知を出さない。行動時刻通知は本人が決めた時刻なので出す。
    /// 3. 当日の固定の昼通知は、(a) 行動時刻と 30 分以内に重なるとき、
    ///    または (b) 計画時点でまだ行動時刻に達していないときは出さない（先に行動時刻通知が来る）。
    /// 4. 当日の `outcome` が `.done` / `.partial` なら、当日の昼通知と行動時刻通知を取り消す。
    /// 5. 行動時刻通知は `plannedAt` が入ってから（＝朝の宣言 M4 の後）登録する。
    public static func make(
        now: Date,
        settings: NotificationSettings,
        today: DayCommitment = .noCommitment,
        calendar: Calendar = .current
    ) -> NotificationPlan {
        let startOfToday = calendar.startOfDay(for: now)
        let todayNoonIdentifier = identifier(for: .noon, day: startOfToday, calendar: calendar)
        let todayActionIdentifier = identifier(for: .action, day: startOfToday, calendar: calendar)

        var registrations: [NotificationRegistration] = []
        var cancelled: [String] = []

        // 規則 4: 前に進めた日は、もう確認も催促もしない。
        let madeProgress = today.outcome.isProgress
        if madeProgress {
            cancelled.append(todayNoonIdentifier)
            cancelled.append(todayActionIdentifier)
        }

        // 規則 1・2・3: 固定通知。
        let dayCount = planningDayCount(for: settings.mode)
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            if !settings.weekendEnabled, calendar.isDateInWeekend(day) { continue }

            let isToday = offset == 0
            for slot in settings.mode.fixedSlots {
                guard let time = settings.time(for: slot),
                      let fireDate = date(on: day, at: time, calendar: calendar),
                      fireDate > now
                else { continue }

                if isToday, slot == .noon {
                    if madeProgress { continue }
                    if shouldSkipTodayNoon(noonFireDate: fireDate, now: now, plannedAt: today.plannedAt) {
                        if !cancelled.contains(todayNoonIdentifier) {
                            cancelled.append(todayNoonIdentifier)
                        }
                        continue
                    }
                }

                registrations.append(
                    NotificationRegistration(
                        identifier: identifier(for: slot, day: day, calendar: calendar),
                        fireDate: fireDate,
                        slot: slot,
                        copyKey: copyKey(for: slot, day: day, calendar: calendar)
                    )
                )
            }
        }

        // 規則 5: 行動時刻通知は当日ぶんだけ。
        if !madeProgress,
           let plannedAt = today.plannedAt,
           plannedAt > now,
           calendar.isDate(plannedAt, inSameDayAs: startOfToday) {
            registrations.append(
                NotificationRegistration(
                    identifier: todayActionIdentifier,
                    fireDate: plannedAt,
                    slot: .action,
                    copyKey: .action
                )
            )
        }

        registrations.sort { lhs, rhs in
            lhs.fireDate == rhs.fireDate ? lhs.identifier < rhs.identifier : lhs.fireDate < rhs.fireDate
        }
        return NotificationPlan(registrations: registrations, cancelledIdentifiers: cancelled)
    }

    // MARK: - 内部

    /// 当日の固定の昼通知を出さない条件（規則 3）。
    static func shouldSkipTodayNoon(noonFireDate: Date, now: Date, plannedAt: Date?) -> Bool {
        guard let plannedAt else { return false }
        // (a) 行動時刻通知と 30 分以内に重なる。
        if abs(noonFireDate.timeIntervalSince(plannedAt)) <= noonOverlapWindow { return true }
        // (b) まだ行動時刻に達していない。行動する前に「覚えてる？」とは聞かない。
        if now < plannedAt { return true }
        return false
    }

    private static func copyKey(for slot: NotificationSlot, day: Date, calendar: Calendar) -> NotificationCopyKey {
        switch slot {
        case .morning: .morning
        case .noon: NotificationCopy.noonKey(for: day, calendar: calendar)
        case .night: .night
        case .action: .action
        }
    }

    private static func date(on day: Date, at time: TimeOfDay, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }
}
