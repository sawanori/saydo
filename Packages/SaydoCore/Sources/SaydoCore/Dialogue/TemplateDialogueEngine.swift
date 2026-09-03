import Foundation

/// `DialogueEngine` の Tier B 実装（実装計画 §0.2 の対応表、§9）。
///
/// LLM を使わずに会話を成立させる。Apple Intelligence が使えない端末でも、
/// 体験の骨格（本人の言葉で言う → 5 分以下に落とす → 声で宣言する）は変わらない。
///
/// **自由発話から名詞を切り出さない。** M2 / N3 の行動文は
/// 「最初の5分でできる、いちばん小さいことは？」と本人に言わせ、その言葉をそのまま使う
/// （`microAction(fromUtterance:)`）。行動文の形式（40 文字以内・動詞終わり）だけを整える。
public struct TemplateDialogueEngine: DialogueEngine {

    /// 分類できなかったときのエラー。呼び出し側はこれを受けても会話を止めない。
    public enum Failure: Error, Sendable, Equatable {
        case reasonNotRecognized
    }

    /// 本人の言葉が名詞で終わっているときに足す語。名詞そのものは書き換えない。
    public static let actionSuffix = "に5分だけ手をつける"

    /// 理由のキーワード辞書。上から順に照合する。
    ///
    /// 並び順は「原因がはっきりしている分類を先に、感情だけの分類を後に」。
    /// 「期限が近くて怖い」は `deadlineFear`（期限）であって `anxious`（怖い）ではないため、
    /// `anxious` はいちばん最後に置く。
    public static let reasonKeywords: [(ReasonCategory, [String])] = [
        (.awkward, ["気まずい", "気まず", "顔を合わせ", "会いたくない", "話しかけにくい"]),
        (.deadlineFear, ["期限", "締切", "しめきり", "間に合わ", "納期"]),
        (.perfectionism, ["完璧", "ちゃんと", "きちんと", "完成度", "うまくやりたい"]),
        (.tooMuch, ["量が多い", "多すぎ", "終わらない", "山積み", "膨大"]),
        (.unclearStart, ["わからない", "分からない", "何から", "どこから", "見当がつかない"]),
        (.tedious, ["面倒", "めんどう", "めんどくさ", "だるい", "億劫"]),
        (.anxious, ["怖い", "こわい", "不安", "怒られ", "心配", "責められ"]),
    ]

    /// 分野のキーワード辞書。上から順に照合し、当たらなければ `.other`。
    public static let domainKeywords: [(TaskDomain, [String])] = [
        (.money, ["請求", "支払", "入金", "経費", "確定申告", "見積", "税", "領収書", "振込"]),
        (.reply, ["返信", "メール", "連絡", "電話", "返事", "チャット", "メッセージ"]),
        (.sales, ["営業", "商談", "提案", "テレアポ", "顧客", "アポ"]),
        (.paperwork, ["書類", "申請", "契約", "手続き", "提出", "記入", "書式"]),
        (.health, ["病院", "歯医者", "健康診断", "運動", "ジム", "薬"]),
        (.bigTask, ["企画", "資料作成", "プロジェクト", "設計", "大きい", "まとめる"]),
    ]

    public init() {}

    // MARK: - DialogueEngine

    /// Tier B は追加質問を作らない。M1 は選択肢で聞く。
    public func followUpQuestion(avoidance: String) async throws -> String {
        ""
    }

    public func classifyReason(avoidance: String, answer: String) async throws -> ReasonClassification {
        guard let category = Self.reason(in: answer) ?? Self.reason(in: avoidance) else {
            throw Failure.reasonNotRecognized
        }
        return ReasonClassification(category: category, followUp: "")
    }

    /// 一般形の例示を 3 件返す。**本人の逃げたいことから名詞を取り出して作らない。**
    public func proposeMicroActions(avoidance: String, reason: ReasonCategory) async throws -> [MicroAction] {
        DialogueCopy.exampleActionIDs
            .prefix(3)
            .compactMap(DialogueCopy.actionText)
            .map { MicroAction(text: $0, estimatedMinutes: 5, shrinkCount: 0) }
    }

    /// 段階表を 1 段下る。止めているものの内容では変えない（分野に依らない一般形のため）。
    public func shrink(action: MicroAction, blocker: String) async throws -> MicroAction {
        ShrinkLadder.next(after: action)
    }

    public func classifyDomain(avoidance: String) async throws -> TaskDomain {
        Self.domain(in: avoidance) ?? .other
    }

    /// 振り返り 1 文。達成度の評価・激励・目標設定は書かない。
    public func weeklyReflection(stats: WeeklyStats) async throws -> String {
        guard let domain = stats.topDomains(limit: 1).first else {
            return "まだ、見えてくるほどの記録がない。"
        }
        guard let reason = stats.topReasons(limit: 1).first else {
            return "この1週間、いちばん多いのは\(domain.displayName)。"
        }
        return "この1週間、いちばん多いのは\(domain.displayName)。理由は\(reason.displayName)が多い。"
    }

    // MARK: - 本人の言葉を行動文にする

    /// 本人の発話をそのまま行動文にする。名詞の切り出しはしない。
    ///
    /// - 動詞で終わっていて 40 文字以内なら、そのまま使う。
    /// - そうでなければ末尾に `actionSuffix` を足して動詞で終わらせる。長い場合は前を詰める。
    public func microAction(fromUtterance utterance: String, shrinkCount: Int = 0) -> MicroAction? {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }

        if Guardrails.endsWithVerb(trimmed), trimmed.count <= Guardrails.actionLimit {
            return MicroAction(text: trimmed, estimatedMinutes: 5, shrinkCount: shrinkCount)
        }

        let room = Guardrails.actionLimit - Self.actionSuffix.count
        let head = trimmed.count <= room ? trimmed : String(trimmed.prefix(room))
        return MicroAction(text: head + Self.actionSuffix, estimatedMinutes: 5, shrinkCount: shrinkCount)
    }

    // MARK: - キーワード照合

    public static func reason(in text: String) -> ReasonCategory? {
        for (category, words) in reasonKeywords where words.contains(where: { text.contains($0) }) {
            return category
        }
        return nil
    }

    public static func domain(in text: String) -> TaskDomain? {
        for (domain, words) in domainKeywords where words.contains(where: { text.contains($0) }) {
            return domain
        }
        return nil
    }
}
