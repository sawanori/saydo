import Foundation

/// 「責めない」を機械的に保証する後段検査（実装計画 §7.5）。
///
/// **適用範囲は生成文だけ**。LLM 出力・テンプレート文言・通知文言に適用し、
/// ユーザーの文字起こしには一切適用しない。本人が「またサボった」と言うのは自由であり、
/// それを弾いてはいけない（実装計画 §7.5）。この型には文字起こしを受け取る API を置かない。
public enum Guardrails {

    /// 文の種別。形式規則（文字数・語尾）は種別ごとに変わる。
    public enum Form: String, Sendable, Equatable, Codable, CaseIterable {
        /// 質問。60 文字以内で「？」で終わる。
        case question
        /// 行動文。40 文字以内で動詞で終わる。
        case action
        /// 平叙文。形式規則は課さない（禁止句と URL・英語のみの検査は受ける）。
        case statement
    }

    public enum Violation: Sendable, Equatable, Codable {
        /// 責める句を含む。
        case bannedPhrase(String)
        /// 文字数超過。
        case tooLong(limit: Int, actual: Int)
        /// 質問なのに「？」で終わっていない。
        case notQuestion
        /// 行動文なのに動詞で終わっていない。
        case notVerbEnding
        /// 空文字。
        case empty
        /// 日本語を含まない（英語のみの出力を拒否する）。
        case noJapanese
        /// URL を含む。
        case containsLink
    }

    /// 質問の上限文字数。
    public static let questionLimit = 60
    /// 行動文の上限文字数。
    public static let actionLimit = 40

    /// 句パターンとして弾く語。単語の部分一致ではないので、
    /// 「連続して5分」のような無害な文は落ちない（実装計画 §7.5）。
    public static let bannedPhrases: [String] = [
        "未達成",
        "サボ",
        "怠け",
        "言い訳",
        "甘え",
        "なぜやらない",
        "また逃げ",
    ]

    /// 「失敗」「ダメ」は語そのものではなく **断定形だけ** を対象にする（実装計画 §7.5）。
    public static let assertivePhrases: [String] = [
        "失敗です",
        "失敗した",
        "失敗だ",
        "失敗でした",
        "ダメです",
        "ダメだ",
        "ダメでした",
        "ダメだった",
        "だめです",
        "だめだ",
        "だめでした",
        "だめだった",
    ]

    /// 「N 日連続」の N として認める文字。
    private static let counterCharacters: Set<Character> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "０", "１", "２", "３", "４", "５", "６", "７", "８", "９",
        "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "何",
    ]

    /// 動詞の終止形・丁寧形の語尾（う段）。
    private static let verbEndings: Set<Character> = [
        "う", "く", "ぐ", "す", "ず", "つ", "づ", "ぬ", "ふ", "ぶ", "ぷ", "む", "る",
    ]

    /// 生成文を検査して違反を列挙する。違反が無ければ空配列。
    public static func check(_ text: String, form: Form) -> [Violation] {
        var violations: [Violation] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return [.empty] }

        for phrase in bannedPhrases where trimmed.contains(phrase) {
            violations.append(.bannedPhrase(phrase))
        }
        for phrase in assertivePhrases where trimmed.contains(phrase) {
            violations.append(.bannedPhrase(phrase))
        }
        if containsStreakPhrase(trimmed) {
            violations.append(.bannedPhrase(streakSuffix))
        }
        if containsLink(trimmed) {
            violations.append(.containsLink)
        }
        if !containsJapanese(trimmed) {
            violations.append(.noJapanese)
        }

        switch form {
        case .question:
            if trimmed.count > questionLimit {
                violations.append(.tooLong(limit: questionLimit, actual: trimmed.count))
            }
            if let last = trimmed.last, last != "？" && last != "?" {
                violations.append(.notQuestion)
            }
        case .action:
            if trimmed.count > actionLimit {
                violations.append(.tooLong(limit: actionLimit, actual: trimmed.count))
            }
            if !endsWithVerb(trimmed) {
                violations.append(.notVerbEnding)
            }
        case .statement:
            break
        }

        return violations
    }

    /// 検査を通るかどうか。
    public static func isClean(_ text: String, form: Form) -> Bool {
        check(text, form: form).isEmpty
    }

    /// 生成文が違反したらテンプレート文に置換する（実装計画 §7.5「違反時」）。
    ///
    /// `replaced` が true になった回数を `SessionLog.guardrailReplacedCount` に積む。
    public static func sanitize(
        _ generated: String,
        form: Form,
        fallback: String
    ) -> (text: String, replaced: Bool) {
        if isClean(generated, form: form) {
            return (generated.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }
        return (fallback, true)
    }

    /// 「N 日連続」（数字 + 日連続）を含むか。
    public static func containsStreakPhrase(_ text: String) -> Bool {
        let characters = Array(text)
        let suffix = Array(streakSuffix)
        guard characters.count > suffix.count else { return false }
        for index in 0...(characters.count - suffix.count) where Array(characters[index..<(index + suffix.count)]) == suffix {
            guard index > 0 else { continue }
            if counterCharacters.contains(characters[index - 1]) { return true }
        }
        return false
    }

    /// 動詞（う段）で終わるか。
    public static func endsWithVerb(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return verbEndings.contains(last)
    }

    private static let streakSuffix = "日連続"

    private static func containsLink(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("http://") || lowered.contains("https://") || lowered.contains("www.")
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value)   // ひらがな
                || (0x30A0...0x30FF).contains(scalar.value) // カタカナ
                || (0x4E00...0x9FFF).contains(scalar.value) // 漢字
                || (0x3000...0x303F).contains(scalar.value) // 句読点
                || (0xFF00...0xFFEF).contains(scalar.value) // 全角記号
        }
    }
}
