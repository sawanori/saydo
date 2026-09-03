/// 会話の現在地。`DialogueEngine`（task_005）に渡す入力をまとめた値。
///
/// 会話履歴そのものは持たない。Foundation Models のセッション上限（4,096 トークン）に対して
/// ステップごとの独立呼び出しに分解するため、必要な最小限だけを運ぶ（実装計画 §0.2-3）。
public struct DialogueContext: Sendable, Codable, Hashable {
    /// どのセッションか。
    public var sessionType: SessionType
    /// いまどのステップか。
    public var step: FlowStep
    /// 逃げたいこと（本人の言葉）。
    public var avoidance: String
    /// 確定した理由。未確定なら nil。
    public var reason: ReasonCategory?
    /// 分野。未判定なら nil。
    public var domain: TaskDomain?
    /// 確定した 5 分以下の行動。未確定なら nil。
    public var microAction: MicroAction?
    /// 昼に聞いた「何が止めているか」（本人の言葉）。
    public var blocker: String?
    /// 前夜からの引き継ぎ（本人の言葉）。
    public var carryover: String?
    /// 宣言の結果。
    public var outcome: CommitmentOutcome

    public init(
        sessionType: SessionType,
        step: FlowStep,
        avoidance: String = "",
        reason: ReasonCategory? = nil,
        domain: TaskDomain? = nil,
        microAction: MicroAction? = nil,
        blocker: String? = nil,
        carryover: String? = nil,
        outcome: CommitmentOutcome = .pending
    ) {
        self.sessionType = sessionType
        self.step = step
        self.avoidance = avoidance
        self.reason = reason
        self.domain = domain
        self.microAction = microAction
        self.blocker = blocker
        self.carryover = carryover
        self.outcome = outcome
    }
}
