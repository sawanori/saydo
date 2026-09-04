import Foundation

/// 「今日」画面だけで使う文言（docs/design/Today.dc.html）。
///
/// 会話の発話は `DialogueCopy` が持つ。ここにあるのはラベルとボタンの言葉だけ。
/// 「未達成」「連続」など責める語彙は置かない（企画原則 §22-1、実装計画 §7.5）。
/// 一覧・チェックボックス・進捗率の語彙も置かない（§22-8）。
enum TodayCopy {
    /// 宣言カードの上に置く小さなラベル。
    static let promiseSectionLabel = "今日の約束"
    /// 宣言カードの中の行動時刻ラベル。
    static let actionTimeLabel = "行動時刻"
    /// 宣言音声の再生ボタン（読み上げ用のラベル）。
    static let playDeclaration = "宣言を聞く"
    /// 画面下の大きなボタン。宣言前は朝フロー、宣言後は手動チェックインを開く。
    static let speakNow = "今話す"
    /// 夜まで終えた日の静かな表示。
    static let dayFinished = "今日はここまで"
    /// まだ今日の宣言が無い日に、宣言カードの代わりに置く 1 行。
    static let noPromiseYet = "今日の約束は、まだこれから。"
    /// 通知が届かなくなっているときの掲示。事実だけを書く。
    static let notificationsStopped = "通知が届かない設定になっています。"
    /// 設定アプリを開く導線。
    static let openSystemSettings = "設定を開く"
    /// 画面右上の設定。
    static let settings = "設定"

    /// 行動時刻と場所（「14:00・机で」）。場所が無ければ時刻だけ。
    static func plannedLabel(time: String, place: String?) -> String {
        guard let place, !place.isEmpty else { return time }
        return "\(time)・\(place)で"
    }
}
