import Foundation
import SaydoCore

/// Foundation Models に渡す指示文と入力文（実装計画 §9「プロンプト予算」）。
///
/// 予算は **指示 600 文字以内・入力 400 文字以内・出力 200 トークン以内**。
/// セッション上限 4,096 トークンに対して十分な余裕を取る。
/// 指示文の長さは `PromptBuilderTests` が固定しているので、書き足すときはテストも見ること。
///
/// 指示文には「60 文字以内」「動詞で終える」といった形式規則も書くが、
/// **それは守らせるための誘導であって保証ではない**。保証は
/// SaydoCore の `Guardrails` による後段検査と、違反時のテンプレート置換で行う。
///
/// - Note: `FoundationModels` にも同名の `PromptBuilder`（`@resultBuilder`）がある。
///   両方を `import` したファイルでは `SaydoAI.PromptBuilder` と修飾する必要がある。
public enum PromptBuilder {

    /// 指示文の上限（文字）。
    public static let instructionLimit = 600
    /// 入力文の上限（文字）。
    public static let inputLimit = 400
    /// 出力の上限（トークン）。
    ///
    /// 実測（macOS 26.5 / M4）: この上限を付けないと生成が暴走して
    /// `exceededContextWindowSize`（4,096 トークン到達）まで 53〜56 秒走る呼び出しが
    /// 24 回中 6 回発生した。上限 200 では 30 回中 0 回が 6 秒を超え、最長 3.95 秒だった。
    /// 6 秒タイムアウト（実装計画 §7.2）を成立させるために必須。
    public static let responseTokenLimit = 200

    /// `DialogueEngine` のどのメソッドの指示かを表す。
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case followUpQuestion
        case classifyReason
        case proposeMicroActions
        case shrink
        case classifyDomain
        case weeklyReflection
    }

    /// 全ステップ共通の禁止句の言い渡し。Guardrails の禁止句と対応させる。
    private static let banned = "「未達成」「◯日連続」「サボ」「怠け」「言い訳」「甘え」「なぜやらない」「また逃げ」は使いません。"

    /// 全ステップ共通の立ち位置。
    private static let persona = """
    あなたは先延ばしに寄り添う伴走者です。教師でも上司でもありません。
    利用者を責めず、評価せず、やわらかい日本語だけで話します。
    """

    /// 指示文（600 文字以内）。
    public static func instructions(for kind: Kind) -> String {
        switch kind {
        case .followUpQuestion:
            """
            \(persona)
            入力は利用者が今日いちばん逃げたいことです。
            なぜ気が進まないのかを、本人が答えやすい形で 1 つだけ聞きます。
            question は 60 文字以内の日本語で、必ず「？」で終えます。
            解決策・助言・励まし・前置き・複数の質問は書きません。
            \(banned)
            """

        case .classifyReason:
            """
            \(persona)
            入力は「逃げたいこと」と、なぜ嫌かという本人の答えです。
            category は次の対応で選びます。awkward=気まずい、perfectionism=完璧にやりたい、tedious=面倒、anxious=不安・怖い、tooMuch=量が多い、unclearStart=何から始めるかわからない、deadlineFear=期限が怖い。
            followUp は本人の言葉を受け止めて、もう一歩だけ具体にする質問を 1 つだけ書きます。60 文字以内の日本語で、必ず「？」で終えます。
            \(banned)
            """

        case .proposeMicroActions:
            """
            \(persona)
            入力は「逃げたいこと」と「逃げたい理由」です。
            その人が今日の最初の 5 分でできる、いちばん小さい行動を 3 つ出します。
            text は 40 文字以内の日本語で、動詞で終えます。例「メールを開く」「相手の名前を検索する」「必要な書類を机に置く」。
            タスク全体を終わらせる案は出しません。準備や着手だけで十分です。
            estimatedMinutes は 1 から 5 の分数です。
            \(banned)
            """

        case .shrink:
            """
            \(persona)
            入力は、いま決まっている行動と、それを止めているものです。
            止めているものがあっても今できる大きさまで、その行動を小さくします。
            text は 40 文字以内の日本語で、動詞で終えます。準備や着手だけで十分です。
            入力にある行動と同じ文は返しません。もっと手前の一歩にします。
            estimatedMinutes は 1 から 5 の分数です。
            \(banned)
            """

        case .classifyDomain:
            """
            あなたは先延ばしの記録を分類する係です。
            入力の「逃げたいこと」を次の 1 つに分類します。
            reply=人への返信や連絡、money=お金や税金や経費、bigTask=大きなタスクや制作、sales=営業や新規の売り込み、paperwork=書類の作成や手続き、health=健康や通院や運動、other=どれにも当てはまらないもの。
            説明は書かず、分類だけを返します。
            """

        case .weeklyReflection:
            """
            あなたは先延ばしの記録を読み解く係です。評価も採点もしません。
            入力は 1 週間の集計だけで、本人の発話は含まれません。
            本人が「自分は何から、なぜ逃げるのか」に気づける 1 文を書きます。
            sentence は 80 文字以内の日本語の平叙文 1 文だけ。
            数・割合・件数・日数は書きません。アラビア数字も漢数字も使いません。
            達成度の評価・励まし・助言・来週の目標は書きません。
            \(banned)
            """
        }
    }

    /// 全指示文。テストと開発者向け表示で使う。
    public static var allInstructions: [(kind: Kind, text: String)] {
        Kind.allCases.map { (kind: $0, text: instructions(for: $0)) }
    }

    // MARK: - 入力（各 400 文字以内）

    /// M1 の追加質問の入力。
    public static func followUpInput(avoidance: String) -> String {
        clamp("逃げたいこと: \(oneLine(avoidance))")
    }

    /// M1 の理由分類の入力。
    public static func reasonInput(avoidance: String, answer: String) -> String {
        clamp("""
        逃げたいこと: \(oneLine(avoidance))
        本人の答え: \(oneLine(answer))
        """)
    }

    /// M2 の行動案 3 件の入力。
    public static func microActionsInput(avoidance: String, reason: ReasonCategory) -> String {
        clamp("""
        逃げたいこと: \(oneLine(avoidance))
        逃げたい理由: \(reason.displayName)
        """)
    }

    /// N3 の再縮小の入力。
    public static func shrinkInput(action: MicroAction, blocker: String) -> String {
        clamp("""
        いまの行動: \(oneLine(action.text))
        止めているもの: \(oneLine(blocker))
        """)
    }

    /// 分野分類の入力。
    public static func domainInput(avoidance: String) -> String {
        clamp("逃げたいこと: \(oneLine(avoidance))")
    }

    /// 週次振り返りの入力。
    ///
    /// 実装計画 §7.6 / fix-decisions P2.2 のとおり、渡すのは分野と理由の集計だけ。
    /// 本人の発話原文・宣言の結果内訳・平均縮小回数は渡さない。
    /// **件数と割合は数字のまま渡さず、多い順の並びに畳んでから渡す。**
    /// 出力に数字を書かせないため（§7.5 の振り返り 1 文の形式規則）と、トークン節約のため。
    public static func reflectionInput(stats: WeeklyStats) -> String {
        let domains = stats.topDomains(limit: 3).map(\.displayName)
        let reasons = stats.topReasons(limit: 3).map(\.displayName)
        let domainLine = domains.isEmpty ? "記録なし" : domains.joined(separator: "、")
        let reasonLine = reasons.isEmpty ? "記録なし" : reasons.joined(separator: "、")
        return clamp("""
        逃げた対象の分野（多い順）: \(domainLine)
        逃げたい理由（多い順）: \(reasonLine)
        """)
    }

    // MARK: - 整形

    /// 改行と連続空白を潰して 1 行にする。プロンプトの構造を利用者の発話で壊されないため。
    static func oneLine(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 入力を上限文字数に収める。
    static func clamp(_ text: String, to limit: Int = inputLimit) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }
}
