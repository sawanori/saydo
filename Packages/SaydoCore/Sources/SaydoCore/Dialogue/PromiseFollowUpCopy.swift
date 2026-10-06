import Foundation

/// 答える画面とアラームのボタンの文言（実装計画 §17.3、task_055）。
///
/// `PromiseCopy` の続き。`PromiseCopy.allLines` に連結してあるので、`Guardrails` の検査は同じ経路を通る。
extension PromiseCopy {

    // MARK: - アラームのボタン

    /// アラームの「開く」。アプリを前面に出すだけで、連鎖は取り消さない。
    public static let alarmOpenButton = "開く"

    /// アラームの「とめる」。その 1 回だけを止める（iOS 26.0 でだけアプリの文言が使われる）。
    public static let alarmStopButton = "とめる"

    // MARK: - 答える画面

    /// 約束の文字の上のラベル。
    public static let followUpPromiseLabel = "約束"

    /// 最初のアクションの文字の上のラベル。
    public static let followUpActionLabel = "最初にやること"

    /// 本人の声を再生するボタン。
    public static let followUpPlayVoice = "自分の声を聞く"

    /// 再生を止めるボタン。
    public static let followUpStopVoice = "声を止める"

    /// 画面を閉じるボタン。
    public static let followUpClose = "閉じる"

    /// 結果を保存できなかったときの 1 行。アラームは取り消していない。
    public static let followUpSaveFailed = "うまく保存できませんでした。もう一度、押してみてください。"

    // MARK: - 今日の画面（task_056）

    /// 約束が無い日の主ボタン。約束する画面を開く。
    public static let todayPromiseButton = "約束する"

    /// 答えがまだの日の主ボタン。答える画面を開く。
    public static let todayAnswerButton = "答える"

    /// 追い始める前の日の 1 行。例「16時から追いかけます」。
    public static func chaseStarts(at date: Date, calendar: Calendar = .current) -> String {
        chaseStarts(timePhrase: timePhrase(for: date, calendar: calendar))
    }

    /// 追い始める前の日の 1 行（時刻の句を直接渡す）。
    public static func chaseStarts(timePhrase: String) -> String {
        "\(timePhrase)から追いかけます"
    }

    /// 追い始めた後で、答えがまだの日の 1 行。例「16時から追いかけています」。
    public static func chasing(since date: Date, calendar: Calendar = .current) -> String {
        chasing(timePhrase: timePhrase(for: date, calendar: calendar))
    }

    /// 追い始めた後で、答えがまだの日の 1 行（時刻の句を直接渡す）。
    public static func chasing(timePhrase: String) -> String {
        "\(timePhrase)から追いかけています"
    }

    /// 追い始める時刻を選び直すボタン。
    public static let changeTimeButton = "時間を変える"

    /// 時刻の選び直しをやめるボタン。
    public static let changeTimeCancel = "このままにする"

    /// 時刻を選び直したが、アラームを登録できなかったときの 1 行。
    public static let changeTimeUnavailable = "今回はアラームを登録し直せませんでした。時刻は元のままです。"

    /// 結果の 1 行。答えた言葉をそのまま出す。`pending` は答えていないので nil。
    public static func resultLabel(for outcome: CommitmentOutcome) -> String? {
        switch outcome {
        case .done: doneButton
        case .partial: partialButton
        case .notYet: notTodayButton
        case .pending: nil
        }
    }

    /// このファイルの全文言。
    public static let followUpLines: [CopyLine] = [
        CopyLine(alarmOpenButton, .statement),
        CopyLine(alarmStopButton, .statement),
        CopyLine(followUpPromiseLabel, .statement),
        CopyLine(followUpActionLabel, .statement),
        CopyLine(followUpPlayVoice, .statement),
        CopyLine(followUpStopVoice, .statement),
        CopyLine(followUpClose, .statement),
        CopyLine(followUpSaveFailed, .statement),
        CopyLine(todayPromiseButton, .statement),
        CopyLine(todayAnswerButton, .statement),
        CopyLine(changeTimeButton, .statement),
        CopyLine(changeTimeCancel, .statement),
        CopyLine(changeTimeUnavailable, .statement),
    ]
        + ["16時", "16時30分"].map { CopyLine(chaseStarts(timePhrase: $0), .statement) }
        + ["16時", "16時30分"].map { CopyLine(chasing(timePhrase: $0), .statement) }
}
