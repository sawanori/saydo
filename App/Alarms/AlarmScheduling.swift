import Foundation
import SaydoCore

/// アラームの登録結果。
enum AlarmScheduleOutcome: Sendable, Equatable {
    /// 登録できた本数。
    case scheduled(count: Int)
    /// アラームの権限が無い。
    case notAuthorized
    /// 登録に失敗した。
    case failed
}

/// その回が何のために鳴るか。
enum AlarmPurpose: Sendable, Equatable {
    /// 約束の結果を聞く（開くと答える画面）。
    case chase
    /// 約束がまだの朝に、約束を促す（開くと約束する画面）。必ず既定の音で鳴らす。
    case prompt
}

/// 1 回分の登録の依頼（実装計画 §17.9）。
struct AlarmRoundRequest: Sendable, Equatable {
    var round: AlarmRound
    /// 1 本目の発火時刻。
    var start: Date
    /// 本と本の間隔（秒）。
    var interval: TimeInterval = AlarmPlan.defaultInterval
    /// 本人の声（`AudioFileStore` の相対パス）。nil なら既定の音で鳴らす。
    var voiceRelativePath: String?
    var purpose: AlarmPurpose = .chase
    /// アラームの題。結果を聞く回では、その日の「最初にやること」の文字（実装計画 §17.10 の 1）。
    /// nil なら固定の題（約束を促す回は常に固定の題）。
    var title: String?
}

/// 約束の後追いに使うアラームの入口（実装計画 §17.4 / §17.9）。
///
/// 実装は `AlarmScheduler`（AlarmKit）。画面とテストはこのプロトコルだけを見る。
/// 識別子は `SaydoCore.AlarmPlan` が 日付 + 回 + 連番 から決めるので、取り消しは日付と回だけで行える。
protocol AlarmScheduling: Sendable {
    /// アラームの権限を求める。許可されたら true。
    func requestAuthorization() async -> Bool

    /// `day` の回をまとめて登録する。その日に登録済みのアラームは、先にすべて取り消す
    /// （`rounds` が空なら、取り消すだけになる）。権限が無ければ何もせず `.notAuthorized` を返す
    /// （ここでは権限を求めない。起動や前面復帰のたびに呼ばれるため）。
    ///
    /// - Parameter day: 識別子に使う日（約束の日）。
    func scheduleRounds(_ rounds: [AlarmRoundRequest], on day: Date) async -> AlarmScheduleOutcome

    /// `day` の 1 回分だけを取り消す。ほかの回は残る。
    func cancelRound(_ round: AlarmRound, on day: Date) async

    /// `day` のアラームをすべて取り消す。
    func cancelDay(_ day: Date) async

    /// このアプリが登録したアラームをすべて取り消す（旧い識別子で登録したものも含む）。
    func cancelAll() async
}
