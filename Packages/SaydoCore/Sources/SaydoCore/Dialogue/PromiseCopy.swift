import Foundation

/// 約束の画面・答える画面・アラームの文言（実装計画 §17.3）。
///
/// 文言はすべてここに集め、View と ViewModel に直書きしない。責める響きにしない（企画原則 §22-1）。
/// 全文言は `allLines` に並べ、`Guardrails` で検査する。
public enum PromiseCopy {

    // MARK: - 約束する画面

    /// 1 つ目の質問。
    public static let promiseQuestion = "今日の約束は？"

    /// 2 つ目の質問。
    public static let firstActionQuestion = "そのために、最初にやることは？"

    /// 録音を始めるボタン。
    public static let pressToTalk = "押して話す"

    /// 押している間の表示。
    public static let whileHolding = "聞いています。離すと止まります。"

    /// 聞き取った 1 行の横の、録り直しのボタン。
    public static let redo = "言い直す"

    /// 約束を保存してアラームを登録するボタン。
    public static let commit = "約束する"

    /// 時刻のチップの見出し。
    public static let chipsPrompt = "いつから追いかけますか？"

    /// 文字で入力する道のボタン。
    public static let textInputButton = "文字で入力"

    /// 文字で入力する道の案内。マイクが使えない端末ではこれが主になる。
    public static let textInputGuide = "声が出せないときは、文字で答えられます。"

    /// チップの文言。
    public static func chipLabel(_ chip: PromiseChip) -> String {
        switch chip {
        case .inThirtyMinutes: "30分後"
        case .inOneHour: "1時間後"
        case .noon: "昼 12:00"
        case .evening: "夕方 18:00"
        }
    }

    /// 時刻の句。「16時」「16時30分」。秒は丸める。
    public static func timePhrase(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return minute == 0 ? "\(hour)時" : "\(hour)時\(minute)分"
    }

    /// 完了の 1 行。例「16時から、あなたの声で追いかけます。」
    public static func completion(startingAt date: Date, calendar: Calendar = .current) -> String {
        completion(timePhrase: timePhrase(for: date, calendar: calendar))
    }

    /// 完了の 1 行（時刻の句を直接渡す）。
    public static func completion(timePhrase: String) -> String {
        "\(timePhrase)から、あなたの声で追いかけます。"
    }

    /// 完了の 1 行（文字だけの約束。鳴るのは既定の音なので「あなたの声で」とは言わない）。
    public static func completionWithoutVoice(startingAt date: Date, calendar: Calendar = .current) -> String {
        completionWithoutVoice(timePhrase: timePhrase(for: date, calendar: calendar))
    }

    /// 完了の 1 行（文字だけの約束。時刻の句を直接渡す）。
    public static func completionWithoutVoice(timePhrase: String) -> String {
        "\(timePhrase)から、アラームで追いかけます。"
    }

    /// 完了の 1 行（アラームの権限が無い）。約束は残したことだけを伝える。
    public static let completionNotAuthorized = "約束は残しました。アラームは鳴りません。設定で許可すると、次から鳴らせます。"

    /// 完了の 1 行（アラームを登録できなかった）。約束は残したことだけを伝える。
    public static let completionAlarmUnavailable = "約束は残しました。今回はアラームを登録できませんでした。"

    /// 左上の、画面を閉じるボタン。
    public static let close = "閉じる"

    /// 文字の入力から、声に戻すボタン。
    public static let voiceInputButton = "声で答える"

    /// 押していた時間が短かったとき。
    public static let holdLonger = "もう一度、押したまま話してみてください。"

    /// 言葉を聞き取れなかったとき。
    public static let notHeard = "うまく聞き取れませんでした。もう一度、押したまま話してみてください。"

    /// 録音を始められなかったとき。その質問は文字で受ける。
    public static let captureUnavailable = "いまは録音を始められません。文字で答えられます。"

    /// 約束を保存できなかったとき。
    public static let saveUnavailable = "いまは保存できませんでした。もう一度「約束する」を押してみてください。"

    /// 押している間の経過秒数。
    public static func elapsed(seconds: Int) -> String {
        "\(seconds)秒"
    }

    /// 約束とアクションをつないだ文（`Commitment.declarationTranscript`）。「約束。アクション」の形にする。
    public static func declarationTranscript(promise: String, action: String) -> String {
        let period: Character = "。"
        let parts = [promise, action]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.last == period ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty }
        return parts.joined(separator: String(period))
    }

    // MARK: - 答える画面

    /// 答える画面の見出し。
    public static let followUpHeading = "今日の約束、どうでしたか？"

    /// 「やった」のボタン。
    public static let doneButton = "やった"

    /// 「少しやった」のボタン。
    public static let partialButton = "少しやった"

    /// 「今日はやめる」のボタン。
    public static let notTodayButton = "今日はやめる"

    /// 「やった」を押した後の 1 行。
    public static let doneReply = "やりましたね。追いかけるのは、ここまでにします。"

    /// 「少しやった」を押した後の 1 行。
    public static let partialReply = "少し進めたなら、それは前進です。追いかけるのは、ここまでにします。"

    /// 「今日はやめる」を押した後の 1 行。
    public static let notTodayReply = "今日はここまでで大丈夫です。追いかけるのは止めます。また明日、声を聞かせてください。"

    /// 結果ごとの、ボタンを押した後の 1 行。`pending` は答えていないので nil。
    public static func reply(for outcome: CommitmentOutcome) -> String? {
        switch outcome {
        case .done: doneReply
        case .partial: partialReply
        case .notYet: notTodayReply
        case .pending: nil
        }
    }

    // MARK: - アラーム

    /// アラームの題。
    public static let alarmTitle = "今日の約束"

    // MARK: - 検査用

    /// 全文言。`Guardrails` の検査と、文言の抜けの確認に使う。時刻を差し込む行は例の時刻で埋めてある。
    public static let allLines: [CopyLine] = [
        CopyLine(promiseQuestion, .question),
        CopyLine(firstActionQuestion, .question),
        CopyLine(pressToTalk, .statement),
        CopyLine(whileHolding, .statement),
        CopyLine(redo, .statement),
        CopyLine(commit, .statement),
        CopyLine(chipsPrompt, .question),
        CopyLine(textInputButton, .statement),
        CopyLine(textInputGuide, .statement),
        CopyLine(completionNotAuthorized, .statement),
        CopyLine(completionAlarmUnavailable, .statement),
        CopyLine(close, .statement),
        CopyLine(voiceInputButton, .statement),
        CopyLine(holdLonger, .statement),
        CopyLine(notHeard, .statement),
        CopyLine(captureUnavailable, .statement),
        CopyLine(saveUnavailable, .statement),
        CopyLine(elapsed(seconds: 3), .statement),
        CopyLine(followUpHeading, .question),
        CopyLine(doneButton, .statement),
        CopyLine(partialButton, .statement),
        CopyLine(notTodayButton, .statement),
        CopyLine(doneReply, .statement),
        CopyLine(partialReply, .statement),
        CopyLine(notTodayReply, .statement),
        CopyLine(alarmTitle, .statement),
    ]
        + PromiseChip.allCases.map { CopyLine(chipLabel($0), .statement) }
        + ["16時", "16時30分", "30分後", "夕方"].map { CopyLine(completion(timePhrase: $0), .statement) }
        + ["16時", "16時30分"].map { CopyLine(completionWithoutVoice(timePhrase: $0), .statement) }
        + followUpLines
}
