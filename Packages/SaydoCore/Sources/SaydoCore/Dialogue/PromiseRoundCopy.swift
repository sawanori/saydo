import Foundation

/// 答える画面の 4 つの答え（実装計画 §17.9 の 3）。
///
/// 「まだ」と「今日はやめる」は、保存する結果はどちらも `notYet`。違いは後追いで、
/// 「まだ」はその回だけを止め、「今日はやめる」はその日の後追いをすべて終える。
public enum FollowUpAnswer: Sendable, Hashable, CaseIterable {
    /// やった。その日の後追いをすべて終える。
    case done
    /// 少しやった。その回だけを止め、次の回でまた追う。
    case partial
    /// まだ。その回だけを止め、次の回でまた追う。
    case notYet
    /// 今日はやめる。その日の後追いをすべて終える。
    case stopToday

    /// 保存する結果。
    public var outcome: CommitmentOutcome {
        switch self {
        case .done: .done
        case .partial: .partial
        case .notYet, .stopToday: .notYet
        }
    }

    /// その日の後追いをすべて終える答えか。
    public var endsTheDay: Bool {
        switch self {
        case .done, .stopToday: true
        case .partial, .notYet: false
        }
    }
}

/// 朝・昼・晩の 3 回で追う形（実装計画 §17.9、task_058）の文言。
///
/// `PromiseCopy` の続き。`PromiseCopy.allLines` に連結してあるので、`Guardrails` の検査は同じ経路を通る。
extension PromiseCopy {

    // MARK: - 約束する画面

    /// 時刻の句をつなぐ。「13時と21時」。
    public static func joinedTimePhrases(_ phrases: [String]) -> String {
        phrases.joined(separator: "と")
    }

    /// 完了の 1 行。これから追う回の時刻を言う。例「13時と21時に、あなたの声で追いかけます。」
    public static func completion(roundsAt dates: [Date], calendar: Calendar = .current) -> String {
        completion(roundPhrases: dates.map { timePhrase(for: $0, calendar: calendar) })
    }

    /// 完了の 1 行（時刻の句を直接渡す）。
    public static func completion(roundPhrases: [String]) -> String {
        "\(joinedTimePhrases(roundPhrases))に、あなたの声で追いかけます。"
    }

    /// 完了の 1 行（文字だけの約束。鳴るのは既定の音なので「あなたの声で」とは言わない）。
    public static func completionWithoutVoice(roundsAt dates: [Date], calendar: Calendar = .current) -> String {
        completionWithoutVoice(roundPhrases: dates.map { timePhrase(for: $0, calendar: calendar) })
    }

    /// 完了の 1 行（文字だけの約束。時刻の句を直接渡す）。
    public static func completionWithoutVoice(roundPhrases: [String]) -> String {
        "\(joinedTimePhrases(roundPhrases))に、アラームで追いかけます。"
    }

    // MARK: - 答える画面

    /// 「まだ」のボタン。その回だけを止め、次の回でまた追う。
    public static let notYetButton = "まだ"

    /// 「まだ」を押した後の 1 行（次の回が無い）。
    public static let notYetReply = "わかりました。今日の追いかけは、ここまでにします。"

    /// 「少しやった」を押した後の 1 行（次の回がある）。
    public static func partialReply(nextPhrase: String) -> String {
        "少し進めたなら、それは前進です。次は\(nextPhrase)に、また聞きます。"
    }

    /// 「まだ」を押した後の 1 行（次の回がある）。
    public static func notYetReply(nextPhrase: String) -> String {
        "わかりました。次は\(nextPhrase)に、また聞きます。"
    }

    /// 答えごとの、ボタンを押した後の 1 行。次の回があるなら「次は◯時に」と伝える。
    ///
    /// - Parameter nextRoundAt: 次に追う回の時刻。無ければ nil（その日の後追いは終わり）。
    public static func reply(for answer: FollowUpAnswer, nextRoundAt: Date?, calendar: Calendar = .current) -> String {
        reply(for: answer, nextPhrase: nextRoundAt.map { timePhrase(for: $0, calendar: calendar) })
    }

    /// 答えごとの、ボタンを押した後の 1 行（時刻の句を直接渡す）。
    public static func reply(for answer: FollowUpAnswer, nextPhrase: String?) -> String {
        switch answer {
        case .done:
            doneReply
        case .stopToday:
            notTodayReply
        case .partial:
            nextPhrase.map { partialReply(nextPhrase: $0) } ?? partialReply
        case .notYet:
            nextPhrase.map { notYetReply(nextPhrase: $0) } ?? notYetReply
        }
    }

    // MARK: - 今日の画面

    /// これから追う回がある日の 1 行。例「次は 13時に追いかけます」。
    public static func nextChase(at date: Date, calendar: Calendar = .current) -> String {
        nextChase(timePhrase: timePhrase(for: date, calendar: calendar))
    }

    /// これから追う回がある日の 1 行（時刻の句を直接渡す）。
    public static func nextChase(timePhrase: String) -> String {
        "次は \(timePhrase)に追いかけます"
    }

    // MARK: - アラーム

    /// 約束がまだの朝に鳴らすアラームの題。
    public static let alarmPromptTitle = "今日の約束をしよう"

    // MARK: - 検査用

    /// このファイルの全文言。時刻を差し込む行は例の時刻で埋めてある。
    public static let roundLines: [CopyLine] = [
        CopyLine(notYetButton, .statement),
        CopyLine(notYetReply, .statement),
        CopyLine(alarmPromptTitle, .statement),
    ]
        + [["21時"], ["13時", "21時"], ["8時", "13時", "21時"], ["22時30分"]].flatMap { phrases in
            [
                CopyLine(completion(roundPhrases: phrases), .statement),
                CopyLine(completionWithoutVoice(roundPhrases: phrases), .statement),
            ]
        }
        + ["21時", "13時30分"].flatMap { phrase in
            [
                CopyLine(partialReply(nextPhrase: phrase), .statement),
                CopyLine(notYetReply(nextPhrase: phrase), .statement),
                CopyLine(nextChase(timePhrase: phrase), .statement),
            ]
        }
}
