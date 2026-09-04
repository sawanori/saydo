import Foundation

/// 通知本文の識別キー。`NotificationPlan` は文言そのものではなくこのキーを運ぶ。
///
/// 文言の出典は企画メモ §15（通知設計）と `docs/retention-strategy.md` §3。
public enum NotificationCopyKey: String, Sendable, Codable, Hashable, CaseIterable {
    /// 朝の固定通知（企画メモ §15）。
    case morning
    /// 昼の固定通知その 1（企画メモ §15）。
    case noonRemember
    /// 昼の固定通知その 2（実装計画 §7.4 の「日替わりで交互」のもう一方）。
    case noonAvoiding
    /// 夜の固定通知（企画メモ §15）。
    case night
    /// 行動時刻の通知。本人の宣言音声を再生する（企画メモ §15・§20）。
    case action
    /// 宣言を後回しにしたときの催促。1 日 1 回だけ（retention-strategy R1）。
    case declarationReminder
}

/// 通知の全文言。責める語彙をひとつも置かない（企画メモ §9・§22-1、実装計画 §7.5）。
///
/// 文言はこのファイルにだけ置く（CLAUDE.md §1）。`NotificationScheduler` と `AppRouter` は
/// `NotificationCopyKey` を受け取り、ここで文字列に変換する。
public enum NotificationCopy {

    // MARK: - 本文

    /// 通知本文。タイトルは持たない（通知のヘッダにアプリ名が出るため、1 行だけを見せる）。
    public static func body(for key: NotificationCopyKey) -> String {
        switch key {
        case .morning:
            "今日、何から逃げそう？"
        case .noonRemember:
            "朝、自分で言ったこと覚えてる？"
        case .noonAvoiding:
            "例のやつ、まだ避けてる？"
        case .night:
            "今日、逃げなかったことをひとつ声に出して。"
        case .action:
            "朝のあなたからです。"
        case .declarationReminder:
            "30 秒だけ、声で約束して"
        }
    }

    // MARK: - 昼の日替わり

    /// 昼の固定通知は 2 種を日替わりで交互に出す（実装計画 §7.4）。
    ///
    /// 暦日の通し番号の偶奇で決めるので、同じ日には何度計算しても同じ文言になり、
    /// 連続する 2 日で必ず入れ替わる。
    public static func noonKey(for day: Date, calendar: Calendar = .current) -> NotificationCopyKey {
        dayNumber(for: day, calendar: calendar).isMultiple(of: 2) ? .noonRemember : .noonAvoiding
    }

    /// 暦日の通し番号。基準日は 2001-01-01。
    ///
    /// `Calendar.ordinality(of: .day, in: .era, for:)` は暦のタイムゾーンを反映せず、
    /// JST の同じ日でも 09:00 をまたぐと値が変わるため使わない。
    static func dayNumber(for day: Date, calendar: Calendar) -> Int {
        let reference = calendar.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))
        let target = calendar.startOfDay(for: day)
        return calendar.dateComponents([.day], from: reference, to: target).day ?? 0
    }

    // MARK: - 通知アクション

    /// 通知を長押しして 1 タップで休むためのアクション（retention-strategy R3）。
    ///
    /// 休みは記録上の失敗として扱わず、Voice Timeline にも出さない。
    public static let restTodayActionIdentifier = "saydo.notification.action.restToday"

    /// 上記アクションのボタン文言。
    public static let restTodayActionTitle = "今日は休む"

    /// 通知を長押しして、同じ通知を後ろへずらすためのアクション（実装計画 §7.4、設計判断 D6）。
    ///
    /// 会話は始めず、同じ内容を 60 分後に 1 件だけ登録し直す（同日 2 回まで）。
    /// 先延ばしを記録上の失敗として扱わない点は「今日は休む」と同じ（企画原則 §22-1）。
    public static let busyNowActionIdentifier = "saydo.notification.action.busyNow"

    /// 上記アクションのボタン文言。
    public static let busyNowActionTitle = "今は話せない"

    /// 通知カテゴリの識別子。固定通知・行動時刻通知の両方にこのカテゴリを付ける。
    public static let categoryIdentifier = "saydo.notification.category.session"

    /// 通知に付けるアクションのボタン文言（通知に並ぶ順）。
    ///
    /// 順序は「今は話せない」→「今日は休む」。軽い方を先に置き、
    /// 1 日を手放す選択を後ろにする。
    public static var actionTitles: [String] {
        [busyNowActionTitle, restTodayActionTitle]
    }

    // MARK: - 検査用

    /// ユーザーの目に触れる文言の全て。禁止句テストの母集団に使う。
    public static var allTexts: [String] {
        NotificationCopyKey.allCases.map { body(for: $0) } + actionTitles
    }
}
