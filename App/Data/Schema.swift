import Foundation
import SwiftData

/// SwiftData のスキーマ V1（実装計画 §10）。
///
/// V1 のモデルは名前空間に入れずトップレベルに置く。将来 V2 を足すときは
/// `enum SaydoSchemaV2: VersionedSchema` を追加し、V1 のモデルを
/// `extension SaydoSchemaV1 { @Model final class ... }` へ移して
/// `typealias` で現行版を指す（Apple のサンプルと同じ手順）。
/// V1 しか無い現時点で名前空間を入れても得は無く、読み書きが増えるだけなので入れない。
enum SaydoSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AvoidanceItem.self,
            Commitment.self,
            VoiceEntry.self,
            SessionLog.self,
            Carryover.self
        ]
    }
}

/// 移行計画。V1 のみなので stage は空。
enum SaydoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SaydoSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// `ModelContainer` の生成口。テストは `inMemory: true` を使う。
enum SaydoModelContainer {
    static var schema: Schema { Schema(versionedSchema: SaydoSchemaV1.self) }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: SaydoMigrationPlan.self,
            configurations: configuration
        )
    }
}

/// `Commitment.dayKey` / `Carryover.forDayKey` に使う日付キー（`yyyy-MM-dd`）。
///
/// `DateFormatter` を使わないのは、ロケールと暦の設定に依らず必ず西暦の
/// `yyyy-MM-dd` を返したいため（端末が和暦設定でもキーが変わってはいけない）。
/// 通知識別子（`morning-yyyyMMdd`、fix-decisions P4.5）は区切り文字が異なるので、
/// 生成は task_009 の `NotificationScheduler` が `compact` で行う。
enum DayKey {
    /// 渡された暦の時間帯だけを引き継いだ西暦の暦。
    ///
    /// `Calendar.current` は端末が和暦設定だと `.year` に元号年を返す
    /// （2026-09-04 → 0008-09-04）。キーは端末設定で変わってはいけないので、
    /// 年月日の取り出しと組み立ては必ず西暦で行う。日の境界は利用者の設定に従うため、
    /// タイムゾーンは渡された暦のものをそのまま使う。
    private static func gregorian(_ calendar: Calendar) -> Calendar {
        if calendar.identifier == .gregorian { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = calendar.locale
        return gregorian
    }

    /// その日の `yyyy-MM-dd`。
    static func make(from date: Date, calendar: Calendar = .current) -> String {
        let parts = gregorian(calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 通知識別子用の `yyyyMMdd`。
    static func compact(from date: Date, calendar: Calendar = .current) -> String {
        make(from: date, calendar: calendar).replacingOccurrences(of: "-", with: "")
    }

    /// キーの表す日の 0 時。解釈できないキーは nil。
    static func startOfDay(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return gregorian(calendar).date(from: DateComponents(year: year, month: month, day: day))
    }
}
