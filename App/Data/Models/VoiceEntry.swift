import Foundation
import SaydoCore
import SwiftData

/// 音声 1 件の種類（実装計画 §10、fix-decisions P2.1 で reason / status を追加済み）。
enum VoiceEntryKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// M0 逃げたいこと
    case avoidance
    /// M1 逃げたい理由
    case reason
    /// M4 宣言
    case declaration
    /// N1 できたかどうか
    case status
    /// N2 止めているもの
    case blocker
    /// E0 今日の前進
    case progress
    /// E1 明日のこと
    case tomorrow
}

/// 本人の声 1 件（実装計画 §10）。声そのものを記録として残す（企画原則 §22-9）。
@Model
final class VoiceEntry {
    #Index<VoiceEntry>([\.recordedAt])

    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    /// `SessionType` の rawValue。
    var sessionTypeRawValue: String
    /// `VoiceEntryKind` の rawValue。
    var kindRawValue: String
    /// 音声ファイルの相対パス（`yyyy/MM/<uuid>.m4a`）。
    /// 絶対パスを持たないのは、再インストールや復元でアプリコンテナの UUID が変わり、
    /// 保存済みの絶対パスが必ず外れるため。解決は `AudioFileStore.url(forRelativePath:)`。
    /// テキストだけで完走した場合は nil。
    var audioPath: String?
    var transcript: String
    var durationSec: Double

    /// 紐づく宣言。任意（実装計画 §10）。
    var commitment: Commitment?

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        sessionType: SessionType,
        kind: VoiceEntryKind,
        audioPath: String? = nil,
        transcript: String = "",
        durationSec: Double = 0
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.sessionTypeRawValue = sessionType.rawValue
        self.kindRawValue = kind.rawValue
        self.audioPath = audioPath
        self.transcript = transcript
        self.durationSec = durationSec
    }

    /// 未知の rawValue は `.adhoc` に寄せる。
    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRawValue) ?? .adhoc }
        set { sessionTypeRawValue = newValue.rawValue }
    }

    /// 未知の rawValue は `.avoidance` に寄せる。
    var kind: VoiceEntryKind {
        get { VoiceEntryKind(rawValue: kindRawValue) ?? .avoidance }
        set { kindRawValue = newValue.rawValue }
    }
}
