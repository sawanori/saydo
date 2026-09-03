/// 会話の 1 ステップ。実装計画 §7.2 の M0〜M4 / N0〜N3 / E0〜E1 に対応する。
///
/// `FlowMachine`（task_005）はこの列挙のうち `steps(for:)` が返す並びを順に進む。
public enum FlowStep: String, Sendable, Codable, Hashable, CaseIterable {
    // 朝（MorningFlow）
    /// M0 今日いちばん逃げたいことを聞く
    case morningAvoidance
    /// M1 逃げたい理由を確かめる
    case morningReason
    /// M2 5 分以下の行動に落とす
    case morningMicroAction
    /// M3 行動する時刻を決める
    case morningPlannedTime
    /// M4 本人の声で宣言する
    case morningDeclaration

    // 昼（NoonFlow）
    /// N0 朝の宣言を本人に返す
    case noonPlayback
    /// N1 できたかどうかを聞く
    case noonStatus
    /// N2 何が止めているかを聞く
    case noonBlocker
    /// N3 行動をさらに小さくする
    case noonShrink

    // 夜（NightFlow）
    /// E0 少しでも前に進めたことを聞く
    case nightProgress
    /// E1 明日どうするかを聞き、翌朝へ引き継ぐ
    case nightTomorrow

    /// 会話の終わり
    case finished

    /// 計画書と会話設計で使う短い記号（M0 / N1 / E0 / END）。
    public var code: String {
        switch self {
        case .morningAvoidance: "M0"
        case .morningReason: "M1"
        case .morningMicroAction: "M2"
        case .morningPlannedTime: "M3"
        case .morningDeclaration: "M4"
        case .noonPlayback: "N0"
        case .noonStatus: "N1"
        case .noonBlocker: "N2"
        case .noonShrink: "N3"
        case .nightProgress: "E0"
        case .nightTomorrow: "E1"
        case .finished: "END"
        }
    }

    public var displayName: String {
        switch self {
        case .morningAvoidance: "逃げたいこと"
        case .morningReason: "逃げたい理由"
        case .morningMicroAction: "5 分以下の行動"
        case .morningPlannedTime: "行動する時刻"
        case .morningDeclaration: "声の宣言"
        case .noonPlayback: "朝のあなたから"
        case .noonStatus: "できたかどうか"
        case .noonBlocker: "止めているもの"
        case .noonShrink: "もっと小さく"
        case .nightProgress: "今日の前進"
        case .nightTomorrow: "明日のこと"
        case .finished: "終わり"
        }
    }

    /// このステップが属するセッション。`finished` はどのセッションにも属さない。
    public var sessionType: SessionType? {
        switch self {
        case .morningAvoidance, .morningReason, .morningMicroAction, .morningPlannedTime, .morningDeclaration:
            .morning
        case .noonPlayback, .noonStatus, .noonBlocker, .noonShrink:
            .noon
        case .nightProgress, .nightTomorrow:
            .night
        case .finished:
            nil
        }
    }

    /// セッションごとの標準の並び。
    ///
    /// `adhoc` は入口の状態（当日の Commitment の有無や `CommitmentOutcome`）で
    /// 朝の短縮版か昼のどちらを開くかが変わるため、ここでは空を返す。
    /// 判定は `FlowMachine`（task_005）が行う。
    public static func steps(for sessionType: SessionType) -> [FlowStep] {
        switch sessionType {
        case .morning:
            [.morningAvoidance, .morningReason, .morningMicroAction, .morningPlannedTime, .morningDeclaration]
        case .noon:
            [.noonPlayback, .noonStatus, .noonBlocker, .noonShrink]
        case .night:
            [.nightProgress, .nightTomorrow]
        case .adhoc:
            []
        }
    }
}
