import Foundation
import SaydoCore
import SwiftData

/// 1 日 1 件の宣言（実装計画 §10）。
///
/// 「同じ `dayKey` にアクティブな `Commitment` は 1 件」はスキーマではなく
/// `Repository.createCommitment` が保証する（§10 の制約）。
@Model
final class Commitment {
    #Index<Commitment>([\.dayKey])

    @Attribute(.unique) var id: UUID
    /// `yyyy-MM-dd`。`DayKey.make(from:)` で作る。
    var dayKey: String
    /// 5 分以下の行動文。本人の言葉をそのまま入れる。
    var microActionText: String
    /// 見積もり時間（分）。
    var estimatedMinutes: Int
    /// 「もっと小さく」を下った回数。
    var shrinkCount: Int
    /// 行動する時刻。決めていなければ nil。
    var plannedAt: Date?
    /// 宣言音声の相対パス（`yyyy/MM/<uuid>.m4a`）。
    /// 宣言の `VoiceEntry.audioPath` と**同一のファイル**を指す（二重に録らない）。
    /// 声で宣言していない場合は nil。
    var declarationAudioPath: String?
    /// 宣言の文字起こし、または「話せない時」に本人が打った文。
    var declarationTranscript: String
    /// 声なしで宣言したか（マイク拒否・話せない場面。fix-decisions P2.3 / R1）。
    /// true のとき昼 N0 は TTS で読み上げず、本人の言葉を画面に出す。
    var isVoiceless: Bool
    /// `CommitmentOutcome` の rawValue。
    var outcomeRawValue: String
    /// `ReasonCategory` の rawValue。理由を聞かなかった経路（短縮版の朝フロー）では nil。
    var reasonRawValue: String?
    /// 夜に聞いた「少しでも前に進めたこと」。
    var progressNote: String?
    var createdAt: Date

    /// 逃げている対象。
    var avoidanceItem: AvoidanceItem?

    /// この宣言に紐づく音声。宣言を消しても音声の記録は残す。
    @Relationship(deleteRule: .nullify, inverse: \VoiceEntry.commitment)
    var voiceEntries: [VoiceEntry] = []

    init(
        id: UUID = UUID(),
        dayKey: String,
        microAction: MicroAction,
        plannedAt: Date? = nil,
        declarationAudioPath: String? = nil,
        declarationTranscript: String = "",
        isVoiceless: Bool = false,
        outcome: CommitmentOutcome = .pending,
        reason: ReasonCategory? = nil,
        progressNote: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.dayKey = dayKey
        self.microActionText = microAction.text
        self.estimatedMinutes = microAction.estimatedMinutes
        self.shrinkCount = microAction.shrinkCount
        self.plannedAt = plannedAt
        self.declarationAudioPath = declarationAudioPath
        self.declarationTranscript = declarationTranscript
        self.isVoiceless = isVoiceless
        self.outcomeRawValue = outcome.rawValue
        self.reasonRawValue = reason?.rawValue
        self.progressNote = progressNote
        self.createdAt = createdAt
    }

    var microAction: MicroAction {
        get {
            MicroAction(
                text: microActionText,
                estimatedMinutes: estimatedMinutes,
                shrinkCount: shrinkCount
            )
        }
        set {
            microActionText = newValue.text
            estimatedMinutes = newValue.estimatedMinutes
            shrinkCount = newValue.shrinkCount
        }
    }

    /// 未知の rawValue は `.pending` に寄せる。
    var outcome: CommitmentOutcome {
        get { CommitmentOutcome(rawValue: outcomeRawValue) ?? .pending }
        set { outcomeRawValue = newValue.rawValue }
    }

    var reason: ReasonCategory? {
        get { reasonRawValue.flatMap(ReasonCategory.init(rawValue:)) }
        set { reasonRawValue = newValue?.rawValue }
    }
}
