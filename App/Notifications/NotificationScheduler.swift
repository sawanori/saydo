import Foundation
import OSLog
import UserNotifications

import SaydoCore

// MARK: - 識別子

/// 通知識別子の規約（実装計画 §7.4）。
///
/// `<枠>-yyyyMMdd`、「今は話せない」の再登録は `<枠>-yyyyMMdd-snooze<n>`。
/// 組み立ては `NotificationPlan.identifier(for:day:calendar:)` と
/// `NotificationPlan.snoozeIdentifier(base:attempt:)` が持つ。
/// ここには「この識別子は SAYDO が管理しているか」の判定だけを置く。
/// アクター隔離を持たせない（保留通知のコールバックは MainActor 外で走るため）。
public enum NotificationIdentifier {

    /// SAYDO が登録・取り消しの対象にする接頭辞（`morning-` / `noon-` / `night-` / `action-`）。
    public static let managedPrefixes: [String] = NotificationSlot.allCases.map { "\($0.rawValue)-" }

    /// SAYDO が管理する識別子か。再登録の識別子も接頭辞は同じなので真になる。
    public static func isManaged(_ identifier: String) -> Bool {
        managedPrefixes.contains { identifier.hasPrefix($0) }
    }

    /// その日付印の通知か（`cancelRemainingToday` の判定に使う）。
    ///
    /// 再登録（`-snooze<n>`）は接尾辞を外してから比べる。
    /// 「今日は休む」と再計画で、ずらした通知も元の通知と一緒に消えるため。
    public static func matches(dayStamp: String, identifier: String) -> Bool {
        isManaged(identifier)
            && NotificationPlan.baseIdentifier(of: identifier).hasSuffix("-" + dayStamp)
    }
}

// MARK: - 保留通知の実測値

/// 実機で保留通知の上限を確かめるための実測値（task_009 の「pending 上限を確認する」）。
public struct PendingDiagnostics: Sendable, Hashable {

    /// SAYDO が管理する保留通知の本数。
    public let managedCount: Int
    /// SAYDO 以外を含む保留通知の総数。
    public let totalCount: Int
    /// 枠ごとの本数（キーは `NotificationSlot.rawValue`）。
    public let countsBySlot: [String: Int]
    /// いちばん近い発火日時。
    public let earliestFireDate: Date?
    /// いちばん先の発火日時。ここまで通知が途切れない。
    public let latestFireDate: Date?
    /// 繰り返しトリガーの本数。当日分だけを取り消せなくなるので 0 でなければならない（check_033）。
    public let repeatingCount: Int

    public init(
        managedCount: Int,
        totalCount: Int,
        countsBySlot: [String: Int],
        earliestFireDate: Date?,
        latestFireDate: Date?,
        repeatingCount: Int
    ) {
        self.managedCount = managedCount
        self.totalCount = totalCount
        self.countsBySlot = countsBySlot
        self.earliestFireDate = earliestFireDate
        self.latestFireDate = latestFireDate
        self.repeatingCount = repeatingCount
    }

    /// `UNNotificationRequest` の配列から数える。
    ///
    /// `UNNotificationRequest` を保持せず、その場で Sendable な値に落とす。
    init(requests: [UNNotificationRequest]) {
        let managed = requests.filter { NotificationIdentifier.isManaged($0.identifier) }
        let triggers = managed.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        let fireDates = triggers.compactMap { $0.nextTriggerDate() }.sorted()

        var counts: [String: Int] = [:]
        for slot in NotificationSlot.allCases {
            let prefix = "\(slot.rawValue)-"
            counts[slot.rawValue] = managed.filter { $0.identifier.hasPrefix(prefix) }.count
        }

        self.managedCount = managed.count
        self.totalCount = requests.count
        self.countsBySlot = counts
        self.earliestFireDate = fireDates.first
        self.latestFireDate = fireDates.last
        self.repeatingCount = triggers.filter(\.repeats).count
    }

    /// ログ 1 行にする（`docs/PROGRESS.md` に貼るための実測値）。数値だけで日本語を含めない。
    public var logLine: String {
        let slots = NotificationSlot.allCases
            .map { "\($0.rawValue)=\(countsBySlot[$0.rawValue] ?? 0)" }
            .joined(separator: " ")
        let earliest = earliestFireDate.map(Self.stamp) ?? "-"
        let latest = latestFireDate.map(Self.stamp) ?? "-"
        return "managed=\(managedCount) total=\(totalCount) repeating=\(repeatingCount) \(slots) first=\(earliest) last=\(latest)"
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - 許可状態

/// 通知が入口として生きているか（実装計画 §7.4 の「黙って壊れたままにしない」）。
public struct NotificationHealth: Sendable, Hashable {

    public let authorizationStatus: UNAuthorizationStatus
    public let pendingCount: Int

    public init(authorizationStatus: UNAuthorizationStatus, pendingCount: Int) {
        self.authorizationStatus = authorizationStatus
        self.pendingCount = pendingCount
    }

    /// 通知を出せる状態か。
    public var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Today 画面に再許可の導線を出すか。
    ///
    /// 許可が無い場合はもちろん、許可があっても保留が 0 本なら通知が止まっているので出す。
    public var needsAttention: Bool {
        !isAuthorized || pendingCount == 0
    }
}

// MARK: - スケジューラ

/// `UNUserNotificationCenter` のラッパ（実装計画 §7.4、task_009 のアプリ側）。
///
/// 計画そのものは `SaydoCore.NotificationPlan` が純計算で作る。この型は
/// 「計画どおりに保留通知を作り直す」「許可と保留の状態を読む」だけを担う。
///
/// 非同期 API はすべて完了ハンドラ版を `withCheckedContinuation` で包む。
/// `UNNotificationSettings` と `UNNotificationRequest` をアクター境界に渡さず、
/// Sendable な値だけを取り出すため（Swift 6 strict concurrency）。
@MainActor
public final class NotificationScheduler {

    public static let shared = NotificationScheduler()

    private let center: UNUserNotificationCenter
    private let calendar: Calendar
    private let logger: Logger

    public init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current,
        logger: Logger = Logger(subsystem: "com.nonturn.saydo", category: "notifications")
    ) {
        self.center = center
        self.calendar = calendar
        self.logger = logger
    }

    // MARK: - 権限とカテゴリ

    /// 通知カテゴリとアクションを登録する。起動直後に 1 回だけ呼ぶ。
    ///
    /// アクションは「今は話せない」（設計判断 D6）と「今日は休む」（retention-strategy R3）の 2 つ。
    /// 軽い方を先に置く。`.foreground` を付けないので、どちらを選んでもアプリは開かない。
    public func registerCategories() {
        let busyNow = UNNotificationAction(
            identifier: NotificationCopy.busyNowActionIdentifier,
            title: NotificationCopy.busyNowActionTitle,
            options: []
        )
        let restToday = UNNotificationAction(
            identifier: NotificationCopy.restTodayActionIdentifier,
            title: NotificationCopy.restTodayActionTitle,
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationCopy.categoryIdentifier,
            actions: [busyNow, restToday],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// 通知の許可を求める。バッジは求めない（数を見せると未処理の圧になるため。企画原則 §22-8）。
    public func requestAuthorization() async -> Bool {
        let logger = self.logger
        return await withCheckedContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    logger.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - 再計画

    /// 起動時と設定変更時の再計画。
    ///
    /// 既存の `morning-*` / `noon-*` / `night-*` / `action-*` をすべて取り消してから、
    /// 計画のぶんだけ登録し直す。
    @discardableResult
    public func reschedule(
        now: Date = Date(),
        settings: NotificationSettings,
        today: DayCommitment = .noCommitment,
        commitmentID: UUID? = nil
    ) async -> NotificationPlan {
        let plan = NotificationPlan.make(now: now, settings: settings, today: today, calendar: calendar)
        await apply(plan, commitmentID: commitmentID)
        return plan
    }

    /// 朝の宣言（M4）が終わった時点の再計画。
    ///
    /// 行動時刻通知（`action-yyyyMMdd`、`.timeSensitive`）が加わり、
    /// 30 分以内に重なる当日の昼通知は計画側で落ちる。
    @discardableResult
    public func rescheduleAfterDeclaration(
        plannedAt: Date,
        now: Date = Date(),
        settings: NotificationSettings,
        commitmentID: UUID?
    ) async -> NotificationPlan {
        await reschedule(
            now: now,
            settings: settings,
            today: DayCommitment(plannedAt: plannedAt, outcome: .pending),
            commitmentID: commitmentID
        )
    }

    /// 計画を保留通知へ反映する。
    public func apply(_ plan: NotificationPlan, commitmentID: UUID? = nil) async {
        await removeAllManagedPending()
        if !plan.cancelledIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: plan.cancelledIdentifiers)
        }
        for registration in plan.registrations {
            await add(registration, commitmentID: commitmentID)
        }
        logger.info("rescheduled: registrations=\(plan.registrations.count, privacy: .public) cancelled=\(plan.cancelledIdentifiers.count, privacy: .public)")
    }

    // MARK: - 取り消し

    /// SAYDO が管理する保留通知をすべて取り消す。
    public func removeAllManagedPending() async {
        let identifiers = await pendingIdentifiers().filter(NotificationIdentifier.isManaged)
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// 「今日は休む」（retention-strategy R3）。当日の残りの保留通知だけを取り消す。
    ///
    /// 翌日以降は非繰り返しトリガーの別識別子なので影響を受けない。
    /// 記録側（休みとして `SessionLog` に残す・`Commitment` を作らない）は呼び出し元の担当。
    @discardableResult
    public func cancelRemainingToday(now: Date = Date()) async -> [String] {
        let stamp = NotificationPlan.dayStamp(for: now, calendar: calendar)
        let identifiers = await pendingIdentifiers().filter {
            NotificationIdentifier.matches(dayStamp: stamp, identifier: $0)
        }
        guard !identifiers.isEmpty else { return [] }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        logger.info("rest today: cancelled=\(identifiers.count, privacy: .public)")
        return identifiers
    }

    /// 指定した識別子の保留通知を取り消す（前進が記録された当日の昼・行動時刻など）。
    public func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // MARK: - 「今は話せない」

    /// 「今は話せない」（設計判断 D6・実装計画 §7.4）。同じ通知を 60 分後に 1 件だけ登録し直す。
    ///
    /// - 内容（本文・`userInfo`・割り込みレベル）は元の通知と同じ。`apply` と同じ組み立てを通す。
    /// - 同日 3 回目は登録しない（`NotificationPlan.maxSnoozesPerDay`）。断らずに黙って何もしない。
    /// - `Commitment` には何も書かない。先延ばしは記録上の失敗ではない（企画原則 §22-1）。
    ///
    /// - Returns: 登録した識別子。上限に達していた場合と枠が読めない通知の場合は nil。
    @discardableResult
    public func snooze(_ link: DeepLink, now: Date = Date()) async -> String? {
        guard let slot = link.slot else { return nil }

        let base = NotificationPlan.identifier(for: slot, day: now, calendar: calendar)
        let pending = await pendingIdentifiers()
        guard let attempt = NotificationPlan.nextSnoozeAttempt(base: base, pending: pending) else {
            logger.info("snooze declined: base=\(base, privacy: .public)")
            return nil
        }

        let registration = NotificationRegistration(
            identifier: NotificationPlan.snoozeIdentifier(base: base, attempt: attempt),
            fireDate: now.addingTimeInterval(NotificationPlan.snoozeInterval),
            slot: slot,
            copyKey: link.copyKey ?? NotificationPlan.copyKey(for: slot, day: now, calendar: calendar)
        )
        await add(registration, commitmentID: link.commitmentID)
        logger.info("snooze registered: \(registration.identifier, privacy: .public)")
        return registration.identifier
    }

    // MARK: - 状態の読み取り

    /// 通知の許可状態。
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// 保留通知の識別子（SAYDO 以外も含む）。
    public func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    /// 保留通知の実測値。
    public func pendingDiagnostics() async -> PendingDiagnostics {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: PendingDiagnostics(requests: requests))
            }
        }
    }

    /// 起動ごとの健康診断。`needsAttention` が true なら Today 画面に再許可の導線を出す。
    public func health() async -> NotificationHealth {
        let status = await authorizationStatus()
        let identifiers = await pendingIdentifiers().filter(NotificationIdentifier.isManaged)
        return NotificationHealth(authorizationStatus: status, pendingCount: identifiers.count)
    }

    /// 実機で保留通知の上限を確かめるためのデバッグ出力。
    ///
    /// Console.app で `subsystem:com.nonturn.saydo category:notifications` を絞ると 1 行で見える。
    @discardableResult
    public func logPendingDiagnostics() async -> PendingDiagnostics {
        let diagnostics = await pendingDiagnostics()
        logger.debug("pending \(diagnostics.logLine, privacy: .public)")
        return diagnostics
    }

    // MARK: - 内部

    private func add(_ registration: NotificationRegistration, commitmentID: UUID?) async {
        let request = UNNotificationRequest(
            identifier: registration.identifier,
            content: content(for: registration, commitmentID: commitmentID),
            trigger: trigger(for: registration)
        )
        let logger = self.logger
        let identifier = registration.identifier
        await withCheckedContinuation { continuation in
            center.add(request) { error in
                if let error {
                    logger.error("add \(identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
                continuation.resume()
            }
        }
    }

    private func content(for registration: NotificationRegistration, commitmentID: UUID?) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        // タイトルは置かない。通知のヘッダにアプリ名が出るので、本文 1 行だけを見せる（§7.4）。
        content.body = NotificationCopy.body(for: registration.copyKey)
        content.sound = .default
        content.categoryIdentifier = NotificationCopy.categoryIdentifier
        content.userInfo = DeepLink.userInfo(for: registration, commitmentID: commitmentID)
        // 行動時刻だけは集中モード中でも届かせる。固定通知は通常の割り込みのまま（§7.4）。
        // Time Sensitive エンタイトルメントが無い状態では、この指定は無視されて .active 相当で届く。
        content.interruptionLevel = registration.slot == .action ? .timeSensitive : .active
        return content
    }

    /// 非繰り返しの `UNCalendarNotificationTrigger`。
    ///
    /// 繰り返しトリガーは使わない。当日分だけを取り消せず、
    /// 「今日は休む」と昼通知のスキップが表現できないため（§7.4）。
    private func trigger(for registration: NotificationRegistration) -> UNCalendarNotificationTrigger {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: registration.fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
