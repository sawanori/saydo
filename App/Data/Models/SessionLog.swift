import Foundation
import SaydoCore
import SwiftData

/// 会話の実装 Tier（実装計画 §7.2）。A = Foundation Models、B = テンプレート。
enum DialogueTier: String, Sendable, Codable, Hashable, CaseIterable {
    case a = "A"
    case b = "B"
}

/// 1 回の会話の記録（実装計画 §10、fix-decisions P1.3 で task_008 が書き込む）。
///
/// 品質改善の材料であって、本人に見せる「実績」ではない（企画原則 §22-8）。
@Model
final class SessionLog {
    @Attribute(.unique) var id: UUID
    /// `SessionType` の rawValue。
    var sessionTypeRawValue: String
    var startedAt: Date
    var endedAt: Date?
    var completed: Bool
    /// `DialogueTier` の rawValue。
    var tierRawValue: String
    /// 最後に到達した `FlowStep` の rawValue。
    var lastStepRawValue: String?
    /// Guardrails でテンプレートに差し替えた回数（実装計画 §7.5）。
    var guardrailReplacedCount: Int

    init(
        id: UUID = UUID(),
        sessionType: SessionType,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        completed: Bool = false,
        tier: DialogueTier = .b,
        lastStep: FlowStep? = nil,
        guardrailReplacedCount: Int = 0
    ) {
        self.id = id
        self.sessionTypeRawValue = sessionType.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completed = completed
        self.tierRawValue = tier.rawValue
        self.lastStepRawValue = lastStep?.rawValue
        self.guardrailReplacedCount = guardrailReplacedCount
    }

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRawValue) ?? .adhoc }
        set { sessionTypeRawValue = newValue.rawValue }
    }

    var tier: DialogueTier {
        get { DialogueTier(rawValue: tierRawValue) ?? .b }
        set { tierRawValue = newValue.rawValue }
    }

    var lastStep: FlowStep? {
        get { lastStepRawValue.flatMap(FlowStep.init(rawValue:)) }
        set { lastStepRawValue = newValue?.rawValue }
    }
}
