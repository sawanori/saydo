import Foundation

/// アラーム 1 本ぶん。識別子と発火時刻の組。
public struct AlarmSlot: Sendable, Hashable {
    /// 日付と連番から決まる識別子。同じ日・同じ連番なら必ず同じ値になる。
    public let id: UUID
    /// 0 から始まる連番。
    public let index: Int
    /// 発火日時。
    public let fireDate: Date

    public init(id: UUID, index: Int, fireDate: Date) {
        self.id = id
        self.index = index
        self.fireDate = fireDate
    }
}

/// アラームの登録計画（実装計画 §17.4）。
///
/// 追い始める時刻から一定の間隔で、決まった本数のアラームを並べる。
/// 純計算だけを行い、AlarmKit への登録と取り消しはアプリ側の `AlarmScheduler` が担当する。
///
/// 識別子は「日付（`yyyyMMdd`）と連番」から決定的に作るので、登録した識別子は
/// 開始時刻を覚えていなくても再計算できる。取り消しは `identifiers(on:count:calendar:)` で
/// 「その日の全識別子」を求めて行う。
///
/// 日付は **開始時刻の日** で決める。3 時間の連鎖が日付をまたいでも、識別子は開始日のものに揃う。
public enum AlarmPlan {

    /// 既定の間隔（3 分）。
    public static let defaultInterval: TimeInterval = 3 * 60

    /// 既定の本数（60 本 = 3 時間）。
    public static let defaultCount = 60

    /// 連番に使えるのは 16 ビットまで。
    public static let maxCount = Int(UInt16.max) + 1

    /// 開始時刻から並べたアラームの列。発火時刻の昇順。
    ///
    /// - Parameters:
    ///   - start: 1 本目の発火時刻。
    ///   - interval: 本と本の間隔（秒）。既定は 3 分。
    ///   - count: 本数。既定は 60 本。0 以下なら空、`maxCount` を超える分は切り捨てる。
    ///   - calendar: 識別子に使う日付を決める暦。
    public static func slots(
        start: Date,
        interval: TimeInterval = defaultInterval,
        count: Int = defaultCount,
        calendar: Calendar = .current
    ) -> [AlarmSlot] {
        let total = clamp(count)
        return (0..<total).map { index in
            AlarmSlot(
                id: identifier(on: start, index: index, calendar: calendar),
                index: index,
                fireDate: start.addingTimeInterval(interval * Double(index))
            )
        }
    }

    /// その日の全識別子。開始時刻には依らず、日付と本数だけで決まる。
    ///
    /// 同じ日・同じ本数なら `slots(start:interval:count:calendar:)` の識別子と一致する。
    public static func identifiers(
        on day: Date,
        count: Int = defaultCount,
        calendar: Calendar = .current
    ) -> [UUID] {
        (0..<clamp(count)).map { identifier(on: day, index: $0, calendar: calendar) }
    }

    /// 日付と連番から決まる識別子（UUID バージョン 8、独自の決定的な値）。
    ///
    /// 並び（16 バイト）:
    /// - 0〜3: `yyyyMMdd` を 32 ビット整数にしたもの（ビッグエンディアン）
    /// - 4〜5: 連番（ビッグエンディアン）
    /// - 6: バージョン（8）  7: 0
    /// - 8: バリアント  9〜15: 固定の印（ASCII の `SAYDOAL`）
    public static func identifier(on day: Date, index: Int, calendar: Calendar = .current) -> UUID {
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
            0x80, 0x00,
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
