import Foundation

/// タイムラインの 1 日分（実装計画 §8、retention-strategy R4）。
struct DaySection: Identifiable, Hashable, Sendable {
    /// その日の開始時刻。同じ日のセクションは 1 つだけ作る。
    let date: Date
    /// その日の記録。時刻の昇順（朝 → 昼 → 夜の順に読める）。
    let entries: [VoiceEntrySnapshot]

    var id: Date { date }
}

/// タイムラインの並べ替えだけを担う純関数。SwiftData も SwiftUI も要らないので単体で試せる。
///
/// **記録がある日だけ**を返す（retention-strategy R4）。記録が無い日と
/// 「今日は休む」を選んだ日は `VoiceEntry` が 1 件も無いため、ここに日が現れない。
/// 「今日は休む」が何も作らないことは `AppDelegate.handle(_:)` に書いてある通りで、
/// 当日の残りの保留通知を取り消すだけ・`Commitment` を作らない（実装計画 §7.4 / R3）。
/// つまり除外用の分岐はここに要らず、データが無いという事実がそのまま表示に出る。
enum TimelineGrouping {
    /// `recordedAt` で日ごとに束ね、新しい日から並べる。
    static func sections(
        from entries: [VoiceEntrySnapshot],
        calendar: Calendar = .current
    ) -> [DaySection] {
        var buckets: [Date: [VoiceEntrySnapshot]] = [:]
        for entry in entries {
            buckets[calendar.startOfDay(for: entry.recordedAt), default: []].append(entry)
        }
        return buckets
            .map { day, dayEntries in
                DaySection(date: day, entries: dayEntries.sorted { $0.recordedAt < $1.recordedAt })
            }
            .sorted { $0.date > $1.date }
    }
}
