import Foundation
import SwiftData

/// 前夜から翌朝への引き継ぎ（実装計画 §7.2 E1 → M0）。
@Model
final class Carryover {
    @Attribute(.unique) var id: UUID
    /// 引き継ぐ先の日（`yyyy-MM-dd`）。
    var forDayKey: String
    /// 本人の言葉。
    var text: String
    /// もとになった `VoiceEntry.id`。
    var sourceEntryID: UUID?
    /// 同じ日に複数の引き継ぎができたとき、最新を選ぶために持つ。
    var createdAt: Date

    init(
        id: UUID = UUID(),
        forDayKey: String,
        text: String,
        sourceEntryID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.forDayKey = forDayKey
        self.text = text
        self.sourceEntryID = sourceEntryID
        self.createdAt = createdAt
    }
}
