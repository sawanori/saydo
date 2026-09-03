import Foundation
import FoundationModels
import SaydoCore

// Foundation Models に生成させる型（実装計画 §9）。
//
// `@Guide` に文字数制約は書けない（fix-decisions P4.3）。ここで書けるのは
// 自然文の description と `.anyOf` / `.range` / `.count` などの構造的制約だけで、
// **文字数・動詞終わり・疑問形は SaydoCore の `Guardrails` が後段で強制する**。
//
// SaydoCore のドメイン型（`ReasonCategory` など）をそのまま `@Generable` にはしない。
// SaydoCore は FoundationModels に依存しない純 Swift パッケージであり、
// Tier B（Apple Intelligence 非対応機）でも動く必要があるため。
// ここでは生成専用の写し（`...Output`）を置き、`domainValue` で SaydoCore の型へ変換する。

/// 逃げたい理由の 7 分類（生成用）。`ReasonCategory` と 1 対 1 に対応する。
@Generable
public enum ReasonCategoryOutput: String, Sendable, Equatable, CaseIterable {
    case awkward
    case perfectionism
    case tedious
    case anxious
    case tooMuch
    case unclearStart
    case deadlineFear

    /// SaydoCore のドメイン型に変換する。
    public var domainValue: ReasonCategory {
        switch self {
        case .awkward: .awkward
        case .perfectionism: .perfectionism
        case .tedious: .tedious
        case .anxious: .anxious
        case .tooMuch: .tooMuch
        case .unclearStart: .unclearStart
        case .deadlineFear: .deadlineFear
        }
    }

    public init(_ category: ReasonCategory) {
        switch category {
        case .awkward: self = .awkward
        case .perfectionism: self = .perfectionism
        case .tedious: self = .tedious
        case .anxious: self = .anxious
        case .tooMuch: self = .tooMuch
        case .unclearStart: self = .unclearStart
        case .deadlineFear: self = .deadlineFear
        }
    }
}

/// 逃げている対象の分野（生成用）。`TaskDomain` と 1 対 1 に対応する。
@Generable
public enum TaskDomainOutput: String, Sendable, Equatable, CaseIterable {
    case reply
    case money
    case bigTask
    case sales
    case paperwork
    case health
    case other

    /// SaydoCore のドメイン型に変換する。
    public var domainValue: TaskDomain {
        switch self {
        case .reply: .reply
        case .money: .money
        case .bigTask: .bigTask
        case .sales: .sales
        case .paperwork: .paperwork
        case .health: .health
        case .other: .other
        }
    }
}

/// M1 の理由分類と追加質問（実装計画 §9 `classifyReason`）。
@Generable
public struct ReasonClassificationOutput: Sendable, Equatable {
    @Guide(description: "逃げたい理由の分類")
    public var category: ReasonCategoryOutput

    @Guide(description: "本人の言葉を受け止めて、もう一歩だけ具体にする短い日本語の質問。1 文だけ。")
    public var followUp: String

    /// SaydoCore のドメイン型に変換する。
    public var domainValue: ReasonClassification {
        ReasonClassification(category: category.domainValue, followUp: followUp)
    }
}

/// 5 分以下の行動 1 件（実装計画 §9 `proposeMicroActions` / `shrink`）。
@Generable
public struct MicroActionOutput: Sendable, Equatable {
    @Guide(description: "今日の最初の 5 分でできる、いちばん小さい行動を表す短い日本語の 1 文。動詞で終える。")
    public var text: String

    @Guide(description: "その行動にかかる分数", .range(1...5))
    public var estimatedMinutes: Int

    /// SaydoCore のドメイン型に変換する。
    public func domainValue(shrinkCount: Int = 0) -> MicroAction {
        MicroAction(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedMinutes: estimatedMinutes,
            shrinkCount: shrinkCount)
    }
}

/// M2 の行動案 3 件（実装計画 §7.2 M2）。
@Generable
public struct MicroActionProposal: Sendable, Equatable {
    @Guide(description: "小さい行動の案", .count(3))
    public var actions: [MicroActionOutput]
}

/// M1 の追加質問だけを返す型（実装計画 §9 `followUpQuestion`）。
///
/// 素の `String` 生成にすると複数文・前置き付きの応答になりやすく、
/// `Guardrails.Form.question`（60 文字以内・「？」終わり）をほぼ確実に落とす。
/// 1 フィールドの構造化出力にして 1 文に閉じ込める。
@Generable
public struct FollowUpQuestionOutput: Sendable, Equatable {
    @Guide(description: "なぜ気が進まないのかを聞く、短い日本語の質問。1 文だけ。")
    public var question: String
}

/// 週次の振り返り 1 文（実装計画 §9 `weeklyReflection`）。
///
/// `FollowUpQuestionOutput` と同じ理由で 1 フィールドの構造化出力にする。
@Generable
public struct ReflectionOutput: Sendable, Equatable {
    @Guide(description: "何から、なぜ逃げているかに本人が気づける日本語の平叙文。1 文だけ。数を表す語は書かない。")
    public var sentence: String
}
