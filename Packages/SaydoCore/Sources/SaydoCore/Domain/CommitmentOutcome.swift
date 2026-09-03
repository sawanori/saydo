/// 宣言（Commitment）の結果。
///
/// 企画原則 §22-7「未達成より『少し進んだ』を評価する」に従い、
/// `partial` は前進として扱う（`isProgress` が true）。`notYet` を責める表示に使わない。
public enum CommitmentOutcome: String, Sendable, Codable, Hashable, CaseIterable {
    /// まだ聞いていない
    case pending
    /// やった
    case done
    /// 少しやった
    case partial
    /// まだ
    case notYet

    public var displayName: String {
        switch self {
        case .pending: "未確認"
        case .done: "やった"
        case .partial: "少しやった"
        case .notYet: "まだ"
        }
    }

    /// 前進として扱うかどうか（`done` と `partial`）。
    public var isProgress: Bool {
        switch self {
        case .done, .partial: true
        case .pending, .notYet: false
        }
    }
}
