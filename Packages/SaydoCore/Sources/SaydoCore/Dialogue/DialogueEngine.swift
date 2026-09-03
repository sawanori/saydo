import Foundation

/// 会話の「穴埋め」を担う契約（実装計画 §9）。
///
/// 実装は 2 つ。`TemplateDialogueEngine`（Tier B、task_005b）と
/// `FoundationModelsDialogueEngine`（Tier A、task_014）。
/// `FlowMachine` はこのプロトコルを呼ばない。呼び出しと結果の差し戻しは
/// アプリ側が行い、結果は `FlowEvent` として状態機械に戻す。
/// 失敗・タイムアウト・ガードレール違反はテンプレート出力に置換し、会話は止めない。
public protocol DialogueEngine: Sendable {
    /// M1 の追加質問 1 文。Tier B は空文字を返してよい（選択肢で聞くため）。
    func followUpQuestion(avoidance: String) async throws -> String

    /// 理由の分類と、その場で返す追加質問 1 文。
    func classifyReason(avoidance: String, answer: String) async throws -> ReasonClassification

    /// 5 分以下の行動を 3 件。
    func proposeMicroActions(avoidance: String, reason: ReasonCategory) async throws -> [MicroAction]

    /// 止めているものを踏まえて行動を 1 段小さくする。
    func shrink(action: MicroAction, blocker: String) async throws -> MicroAction

    /// 逃げている対象の分野。
    func classifyDomain(avoidance: String) async throws -> TaskDomain

    /// 週次の振り返り 1 文。達成度の評価・激励・目標設定は書かない。
    func weeklyReflection(stats: WeeklyStats) async throws -> String
}
