import Foundation

/// 「今日」画面だけで使う文言（実装計画 §17.3「今日」）。
///
/// ここにあるのはラベルと掲示の言葉だけ。約束・アクションのラベル、主ボタン、追う時刻の 1 行、
/// 結果の言葉は `PromiseCopy` が持つ（Guardrails の検査に入っている）。
/// 「未達成」「連続」など責める語彙は置かない（企画原則 §22-1）。
/// 一覧・チェックボックス・進捗率の語彙も置かない（§22-8）。
enum TodayCopy {
    /// 約束のカードの上に置く小さなラベル。
    static let promiseSectionLabel = "今日の約束"
    /// カードの中の、追う時刻のラベル。
    static let chaseTimeLabel = "追いかける時刻"
    /// カードの中の、結果のラベル。
    static let resultLabel = "結果"
    /// 約束の声の再生ボタン（読み上げ用のラベル）。
    static let playDeclaration = "約束の声を聞く"
    /// 再生中の同じボタン（読み上げ用のラベル）。
    static let stopDeclaration = "声を止める"
    /// 答えた日の静かな表示。
    static let dayFinished = "今日はここまで"
    /// まだ今日の約束が無い日に、カードの代わりに置く 1 行。
    static let noPromiseYet = "今日の約束は、まだこれから。"
    /// 画面右上の設定。
    static let settings = "設定"
}
