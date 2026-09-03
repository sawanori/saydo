/// 1 日のどの区切りの会話かを表す。
///
/// - `morning` 朝: 逃げたいことを言い、理由を選び、5 分以下の行動に落とし、宣言する。
/// - `noon` 昼: 朝の宣言音声を本人に返し、状態を聞き、必要なら行動をさらに小さくする。
/// - `night` 夜: 前進を残し、翌日へ引き継ぐ。
/// - `adhoc` 手動: 通知以外から本人が開いたとき。実際に流すフローは実行時に決める。
public enum SessionType: String, Sendable, Codable, Hashable, CaseIterable {
    case morning
    case noon
    case night
    case adhoc

    public var displayName: String {
        switch self {
        case .morning: "朝"
        case .noon: "昼"
        case .night: "夜"
        case .adhoc: "手動"
        }
    }
}
