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
        for entry in collapsingPromiseVoices(entries) {
            buckets[calendar.startOfDay(for: entry.recordedAt), default: []].append(entry)
        }
        return buckets
            .map { day, dayEntries in
                DaySection(date: day, entries: dayEntries.sorted { $0.recordedAt < $1.recordedAt })
            }
            .sorted { $0.date > $1.date }
    }

    /// 約束する画面（実装計画 §17.3）が残す声を、1 つの約束につき 1 件にまとめる。
    ///
    /// task_059 以降の約束は、約束の録音を指す宣言の行が 1 件だけなので、何も隠れない。
    /// ここで束ねるのは、それより前の版（つないだ声を作っていた間）が残した行。
    /// 約束する画面は、約束の言葉（`.avoidance`）・アクションの言葉（`.declaration`）・
    /// 2 つをつないだ声（`.declaration`。`Repository.createCommitment` が作る）の 3 件を残す。
    /// そのまま並べると同じ声が 2 回出るので、同じ約束に宣言が 2 件以上ある日は、
    /// いちばん後に残した 1 件（つないだ声。文字は「約束。アクション」）だけを見せる。
    /// 旧い会話の宣言は 1 つの約束につき 1 件なので、ここでは何も隠れない。
    static func collapsingPromiseVoices(_ entries: [VoiceEntrySnapshot]) -> [VoiceEntrySnapshot] {
        var declarations: [UUID: [VoiceEntrySnapshot]] = [:]
        for entry in entries where entry.kind == .declaration {
            guard let commitmentID = entry.commitmentID else { continue }
            declarations[commitmentID, default: []].append(entry)
        }

        var joinedByCommitment: [UUID: VoiceEntrySnapshot] = [:]
        for (commitmentID, group) in declarations where group.count >= 2 {
            // 同じ時刻なら、声のある方・文字の長い方（つないだ文）を採る。
            joinedByCommitment[commitmentID] = group.max { lhs, rhs in
                if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
                if (lhs.audioPath != nil) != (rhs.audioPath != nil) { return lhs.audioPath == nil }
                return lhs.transcript.count < rhs.transcript.count
            }
        }
        guard !joinedByCommitment.isEmpty else { return entries }

        return entries.filter { entry in
            guard let commitmentID = entry.commitmentID,
                  let joined = joinedByCommitment[commitmentID] else { return true }
            if entry.id == joined.id { return true }
            let isPromisePart = entry.kind == .declaration || entry.kind == .avoidance
            return !(isPromisePart && entry.sessionType == joined.sessionType)
        }
    }
}
