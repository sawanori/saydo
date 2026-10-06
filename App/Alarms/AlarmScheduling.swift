import Foundation

/// 連鎖アラームの登録結果。
enum AlarmScheduleOutcome: Sendable, Equatable {
    /// 登録できた本数。
    case scheduled(count: Int)
    /// アラームの権限が無い。
    case notAuthorized
    /// 登録に失敗した。
    case failed
}

/// 約束の後追いに使う連鎖アラームの入口（実装計画 §17.4）。
///
/// 実装は `AlarmScheduler`（AlarmKit）。画面とテストはこのプロトコルだけを見る。
/// 発火時刻と識別子は `SaydoCore.AlarmPlan` で決まるので、取り消しは日付だけで行える。
protocol AlarmScheduling: Sendable {
    /// アラームの権限を求める。許可されたら true。
    func requestAuthorization() async -> Bool

    /// `start` から `AlarmPlan` の既定（3 分おき 60 本）で連鎖を登録する。
    /// 同じ日の連鎖が残っていれば、先に取り消してから登録し直す。
    ///
    /// - Parameter voiceRelativePath: 本人の声（`AudioFileStore` の相対パス）。nil なら既定の音で鳴らす。
    func scheduleChain(start: Date, voiceRelativePath: String?) async -> AlarmScheduleOutcome

    /// `day` に始まる連鎖をすべて取り消す。
    func cancelChain(startedOn day: Date) async
}
