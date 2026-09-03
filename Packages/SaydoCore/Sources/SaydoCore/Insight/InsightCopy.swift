import Foundation

/// 週次分析で見せる文言（実装計画 §7.6、企画メモ §11）。
///
/// Tier B（AI なし）はここのテンプレートを選ぶ。Tier A は集計値だけを LLM に渡して
/// 1 文を生成し、Guardrails を通らなければここへ落とす。
/// 責める語彙をひとつも置かない（企画メモ §9・§22-1）。
public enum InsightCopy {

    // MARK: - データ不足

    /// 3 件に届いていないとき。空白や少なさに触れない。
    public static let notEnoughData = "まだ数日ぶんです。今日の分だけで大丈夫。"

    // MARK: - 初回インサイト（retention-strategy R9）

    /// 「3 回のうち 2 回が『人への返信』」のような 1 行。週次を待たずに Timeline 上部へ出す。
    public static func firstInsight(total: Int, count: Int, domain: TaskDomain) -> String {
        "\(total) 回のうち \(count) 回が『\(domain.displayName)』"
    }

    // MARK: - 週次の振り返り 1 文

    /// 上位の理由 × 分野の組み合わせ表。理由ごとの言い回しに分野名を差し込む。
    public static func reflection(reason: ReasonCategory, domain: TaskDomain) -> String {
        let name = domain.displayName
        switch reason {
        case .awkward:
            return "今週は『\(name)』のように、相手との気まずさが関わることから距離を置く日が多かったみたいです。"
        case .perfectionism:
            return "今週は『\(name)』のように、ちゃんとやりたい気持ちが強いことほど後ろに回っていたみたいです。"
        case .tedious:
            return "今週は『\(name)』のように、手数が多く感じることが後ろに回りがちだったみたいです。"
        case .anxious:
            return "今週は『\(name)』のように、先が見えないことに近づきにくい週だったみたいです。"
        case .tooMuch:
            return "今週は『\(name)』のように、量が大きく見えることとの間に距離ができていたみたいです。"
        case .unclearStart:
            return "今週は『\(name)』のように、入口がはっきりしないことで止まっていたみたいです。"
        case .deadlineFear:
            return "今週は『\(name)』のように、期限が近いものほど見ないでいた週だったみたいです。"
        }
    }

    /// 理由がまだ 1 件も記録されていないとき。分野だけで 1 文にする。
    public static func reflection(domain: TaskDomain) -> String {
        "今週は『\(domain.displayName)』から距離を置く日が多かったみたいです。"
    }

    // MARK: - 検査用

    /// ユーザーの目に触れる文言の全て。禁止句テストの母集団に使う。
    public static var allTexts: [String] {
        var texts = [notEnoughData]
        for domain in TaskDomain.allCases {
            texts.append(reflection(domain: domain))
            for reason in ReasonCategory.allCases {
                texts.append(reflection(reason: reason, domain: domain))
            }
            texts.append(firstInsight(total: 3, count: 2, domain: domain))
        }
        return texts
    }
}
