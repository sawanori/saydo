import Foundation
import SaydoCore
import SwiftData

/// 逃げている対象の状態。
enum AvoidanceStatus: String, Sendable, Codable, Hashable, CaseIterable {
    /// 現役
    case open
    /// 翌日へ引き継いだ
    case carriedOver
    /// 捨てた
    case dropped
    /// 終わった
    case done
}

/// 逃げている対象（実装計画 §10）。`title` は本人の言葉をそのまま入れる（企画原則 §22-6）。
@Model
final class AvoidanceItem {
    @Attribute(.unique) var id: UUID
    /// 本人の言葉。
    var title: String
    /// `TaskDomain` の rawValue。列挙のまま持たず String で持つのは、
    /// `#Predicate` と `SortDescriptor` が String なら確実に動くため。
    var domainRawValue: String
    /// `AvoidanceStatus` の rawValue。
    var statusRawValue: String
    var createdAt: Date
    var lastTouchedAt: Date

    /// この対象に紐づく宣言。対象を消しても宣言の記録は残す（企画原則 §22-9）。
    @Relationship(deleteRule: .nullify, inverse: \Commitment.avoidanceItem)
    var commitments: [Commitment] = []

    init(
        id: UUID = UUID(),
        title: String,
        domain: TaskDomain = .other,
        status: AvoidanceStatus = .open,
        createdAt: Date = .now,
        lastTouchedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.domainRawValue = domain.rawValue
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.lastTouchedAt = lastTouchedAt ?? createdAt
    }

    /// 未知の rawValue は `.other` に寄せる（古いストアを読んでも落とさない）。
    var domain: TaskDomain {
        get { TaskDomain(rawValue: domainRawValue) ?? .other }
        set { domainRawValue = newValue.rawValue }
    }

    /// 未知の rawValue は `.open` に寄せる。
    var status: AvoidanceStatus {
        get { AvoidanceStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }
}
