import Foundation

/// 1 日のうちの「回」（実装計画 §17.9 / §17.10）。1 つの約束を、朝・昼・晩の 3 回まで追う。
/// 約束の時点で 3 回とも過ぎていた日は、その日は追わない。
public enum AlarmRound: Int, Sendable, Hashable, CaseIterable, Codable, Comparable {
    case morning = 1
    case noon = 2
    case evening = 3

    public static func < (lhs: AlarmRound, rhs: AlarmRound) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// ある回と、その回を始める時刻。
public struct AlarmRoundStart: Sendable, Hashable {
    public let round: AlarmRound
    public let start: Date

    public init(round: AlarmRound, start: Date) {
        self.round = round
        self.start = start
    }
}

/// アラーム 1 本ぶん。識別子と発火時刻の組。
public struct AlarmSlot: Sendable, Hashable {
    /// 日付・回・連番から決まる識別子。同じ日・同じ回・同じ連番なら必ず同じ値になる。
    public let id: UUID
    /// どの回の本か。
    public let round: AlarmRound
    /// 0 から始まる、回の中の連番。
    public let index: Int
    /// 発火日時。
    public let fireDate: Date

    public init(id: UUID, round: AlarmRound, index: Int, fireDate: Date) {
        self.id = id
        self.round = round
        self.index = index
        self.fireDate = fireDate
    }
}

/// アラームの登録計画（実装計画 §17.4 / §17.9）。
///
/// 回の開始時刻から一定の間隔で、決まった本数のアラームを並べる。
/// 純計算だけを行い、AlarmKit への登録と取り消しはアプリ側の `AlarmScheduler` が担当する。
///
/// 識別子は「日付（`yyyyMMdd`）・回・連番」から決定的に作るので、登録した識別子は
/// 開始時刻を覚えていなくても再計算できる。取り消しは `identifiers(on:round:...)`（1 回分）か
/// `allIdentifiers(on:...)`（その日の全部）で行う。
///
/// 日付は **約束の日** で決める。
public enum AlarmPlan {

    /// 既定の間隔（3 分）。
    public static let defaultInterval: TimeInterval = 3 * 60

    /// 1 回あたりの既定の本数（40 本 = 2 時間）。
    public static let defaultCount = 40

    /// 連番に使えるのは 16 ビットまで。
    public static let maxCount = Int(UInt16.max) + 1

    // MARK: - どの回で追うか

    /// 約束した時刻から、その日に追う回を決める（実装計画 §17.9 の 4、§17.10 の 2）。
    ///
    /// 約束より後に始まる回だけを残す（約束より前の回、約束と同時刻の回は飛ばす）。
    /// 3 回とも過ぎていたら空（その日は追わない）。開始時刻の昇順で返す。
    public static func rounds(
        promisedAt: Date,
        morning: Date,
        noon: Date,
        evening: Date
    ) -> [AlarmRoundStart] {
        let fixed = [
            AlarmRoundStart(round: .morning, start: morning),
            AlarmRoundStart(round: .noon, start: noon),
            AlarmRoundStart(round: .evening, start: evening),
        ]
        return fixed
            .filter { $0.start > promisedAt }
            .sorted { $0.start < $1.start }
    }

    // MARK: - 本の並び

    /// 1 回分のアラームの列。発火時刻の昇順。
    ///
    /// - Parameters:
    ///   - day: 識別子に使う日（約束の日）。
    ///   - round: どの回か。
    ///   - start: 1 本目の発火時刻。
    ///   - interval: 本と本の間隔（秒）。既定は 3 分。
    ///   - count: 本数。既定は 40 本。0 以下なら空、`maxCount` を超える分は切り捨てる。
    ///   - calendar: 識別子に使う日付を決める暦。
    public static func slots(
        on day: Date,
        round: AlarmRound,
        start: Date,
        interval: TimeInterval = defaultInterval,
        count: Int = defaultCount,
        calendar: Calendar = .current
    ) -> [AlarmSlot] {
        (0..<clamp(count)).map { index in
            AlarmSlot(
                id: identifier(on: day, round: round, index: index, calendar: calendar),
                round: round,
                index: index,
                fireDate: start.addingTimeInterval(interval * Double(index))
            )
        }
    }

    /// その日の 1 回分の全識別子。開始時刻には依らず、日付・回・本数だけで決まる。
    public static func identifiers(
        on day: Date,
        round: AlarmRound,
        count: Int = defaultCount,
        calendar: Calendar = .current
    ) -> [UUID] {
        (0..<clamp(count)).map { identifier(on: day, round: round, index: $0, calendar: calendar) }
    }

    /// その日の全識別子（朝・昼・晩の 3 回と、旧い版が登録した追加の 1 回）。
    ///
    /// 追加の 1 回（`retiredExtraRoundByte`）は今の版では登録しないが、旧い版で登録した本が
    /// 端末に残っているかもしれないので、取り消しの対象には含める。
    public static func allIdentifiers(
        on day: Date,
        count: Int = defaultCount,
        calendar: Calendar = .current
    ) -> [UUID] {
        AlarmRound.allCases.flatMap { identifiers(on: day, round: $0, count: count, calendar: calendar) }
            + retiredExtraIdentifiers(on: day, count: count, calendar: calendar)
    }

    /// 旧い版（task_058）が「3 回とも過ぎた後の追加の 1 回」に使っていた回の印。
    public static let retiredExtraRoundByte: UInt8 = 4

    /// 旧い版が登録した、追加の 1 回の識別子。取り消しにだけ使う。
    public static func retiredExtraIdentifiers(
        on day: Date,
        count: Int = defaultCount,
        calendar: Calendar = .current
    ) -> [UUID] {
        (0..<clamp(count)).map {
            makeIdentifier(on: day, roundByte: retiredExtraRoundByte, index: $0, calendar: calendar)
        }
    }

    /// 日付・回・連番から決まる識別子（UUID バージョン 8、独自の決定的な値）。
    ///
    /// 並び（16 バイト）:
    /// - 0〜3: `yyyyMMdd` を 32 ビット整数にしたもの（ビッグエンディアン）
    /// - 4〜5: 連番（ビッグエンディアン）
    /// - 6: バージョン（8）  7: 回（1〜3。旧い識別子は 0、旧い追加の 1 回は 4）
    /// - 8: バリアント  9〜15: 固定の印（ASCII の `SAYDOAL`）
    public static func identifier(
        on day: Date,
        round: AlarmRound,
        index: Int,
        calendar: Calendar = .current
    ) -> UUID {
        makeIdentifier(on: day, roundByte: UInt8(truncatingIfNeeded: round.rawValue), index: index, calendar: calendar)
    }

    // MARK: - 旧い識別子（task_058 より前）

    /// 旧い版が使っていた本数（3 分おき 60 本）。
    public static let legacyCount = 60

    /// 旧い版（回を持たない、日付 + 連番）の、その日の全識別子。
    /// 開発中の端末に残っている旧いアラームを取り消すためだけに使う。
    public static func legacyIdentifiers(on day: Date, calendar: Calendar = .current) -> [UUID] {
        (0..<legacyCount).map { makeIdentifier(on: day, roundByte: 0, index: $0, calendar: calendar) }
    }

    // MARK: - 内部

    private static func makeIdentifier(on day: Date, roundByte: UInt8, index: Int, calendar: Calendar) -> UUID {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let stamp = UInt32(clamping: (components.year ?? 0) * 10_000 + (components.month ?? 0) * 100 + (components.day ?? 0))
        let sequence = UInt16(clamping: max(0, index))

        let marker: [UInt8] = Array("SAYDOAL".utf8)
        let bytes: [UInt8] = [
            UInt8(truncatingIfNeeded: stamp >> 24),
            UInt8(truncatingIfNeeded: stamp >> 16),
            UInt8(truncatingIfNeeded: stamp >> 8),
            UInt8(truncatingIfNeeded: stamp),
            UInt8(truncatingIfNeeded: sequence >> 8),
            UInt8(truncatingIfNeeded: sequence),
            0x80, roundByte,
            0x80,
        ] + marker
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func clamp(_ count: Int) -> Int {
        min(max(0, count), maxCount)
    }
}
