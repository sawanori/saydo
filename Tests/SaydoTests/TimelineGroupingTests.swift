import Foundation
import SaydoCore
import XCTest

@testable import Saydo

/// `TimelineGrouping` は表示用の並べ替えだけを担う純関数（task_012）。
///
/// 題材は 3 日分。9 月 3 日は「今日は休む」を選んだ日で、`Commitment` も `VoiceEntry` も
/// 作られない（retention-strategy R3、`AppDelegate.handle(_:)`）。R4 の「空白日の
/// プレースホルダを置かない」が、除外の分岐ではなくデータの不在から自然に出ることを確かめる。
final class TimelineGroupingTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    // MARK: 補助

    private func date(day: Int, hour: Int, minute: Int) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
            )
        )
    }

    private func entry(
        at date: Date,
        // `SaydoCore` にも同名の型があるので、アプリ側の型を明示する。
        kind: Saydo.VoiceEntryKind = .avoidance,
        transcript: String = "",
        audioPath: String?
    ) -> VoiceEntrySnapshot {
        VoiceEntrySnapshot(
            id: UUID(),
            recordedAt: date,
            sessionType: .morning,
            kind: kind,
            audioPath: audioPath,
            transcript: transcript,
            durationSec: audioPath == nil ? 0 : 4.2,
            commitmentID: nil
        )
    }

    /// 入力は `@Query` と同じ `recordedAt` 降順。9/4 が 3 件、9/2 が 2 件、9/3 は 0 件。
    /// 9/4 13:04 はチップだけで答えた場面で `audioPath` が nil。
    private func fixture() throws -> [VoiceEntrySnapshot] {
        [
            entry(at: try date(day: 4, hour: 21, minute: 13), kind: .progress,
                  transcript: "でも金額だけは入れた。", audioPath: "2026/09/d3.m4a"),
            entry(at: try date(day: 4, hour: 13, minute: 4), kind: .status,
                  transcript: "まだ開いてない。", audioPath: nil),
            entry(at: try date(day: 4, hour: 8, minute: 12), kind: .avoidance,
                  transcript: "今日は見積書から逃げたい。", audioPath: "2026/09/d1.m4a"),
            entry(at: try date(day: 2, hour: 14, minute: 5), kind: .status,
                  transcript: "メールは開けた。", audioPath: "2026/09/b2.m4a"),
            entry(at: try date(day: 2, hour: 8, minute: 20), kind: .avoidance,
                  transcript: "クライアントへの返信が気まずい。", audioPath: "2026/09/b1.m4a"),
        ]
    }

    // MARK: テスト

    /// 記録がある日だけがセクションになる（3 日のうち 2 つ）。
    func testSectionsCoverOnlyRecordedDays() throws {
        let sections = TimelineGrouping.sections(from: try fixture(), calendar: calendar)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.entries.count), [3, 2])
    }

    /// 記録の無い 9 月 3 日のセクションは作らない（空白日のプレースホルダ禁止）。
    func testEmptyDayHasNoSection() throws {
        let sections = TimelineGrouping.sections(from: try fixture(), calendar: calendar)
        let restDay = calendar.startOfDay(for: try date(day: 3, hour: 12, minute: 0))

        XCTAssertFalse(sections.contains { $0.date == restDay })
        XCTAssertFalse(sections.contains { $0.entries.isEmpty })
    }

    /// セクションは新しい日から並ぶ。`id` は日の開始時刻。
    func testSectionsAreOrderedNewestDayFirst() throws {
        let sections = TimelineGrouping.sections(from: try fixture(), calendar: calendar)

        XCTAssertEqual(
            sections.map(\.date),
            [
                calendar.startOfDay(for: try date(day: 4, hour: 8, minute: 12)),
                calendar.startOfDay(for: try date(day: 2, hour: 8, minute: 20)),
            ]
        )
        XCTAssertEqual(sections.map(\.id), sections.map(\.date))
    }

    /// セクションの中は時刻の昇順（朝 → 昼 → 夜の順に読める）。
    func testEntriesWithinSectionAreOrderedByTime() throws {
        let sections = TimelineGrouping.sections(from: try fixture(), calendar: calendar)

        for section in sections {
            let times = section.entries.map(\.recordedAt)
            XCTAssertEqual(times, times.sorted())
        }
        XCTAssertEqual(
            sections[0].entries.map(\.recordedAt),
            [
                try date(day: 4, hour: 8, minute: 12),
                try date(day: 4, hour: 13, minute: 4),
                try date(day: 4, hour: 21, minute: 13),
            ]
        )
    }

    /// 音声を持たないエントリ（チップだけで答えた場面）も落とさずに並べる。
    func testEntriesWithoutAudioAreKept() throws {
        let sections = TimelineGrouping.sections(from: try fixture(), calendar: calendar)
        let silent = sections[0].entries.filter { $0.audioPath == nil }

        XCTAssertEqual(silent.count, 1)
        XCTAssertEqual(silent.first?.recordedAt, try date(day: 4, hour: 13, minute: 4))
        XCTAssertEqual(sections.flatMap(\.entries).count, 5)
    }

    // MARK: 約束する画面の声（task_056）

    private func promiseEntry(
        at date: Date,
        kind: Saydo.VoiceEntryKind,
        transcript: String,
        audioPath: String?,
        commitmentID: UUID
    ) -> VoiceEntrySnapshot {
        VoiceEntrySnapshot(
            id: UUID(),
            recordedAt: date,
            sessionType: .morning,
            kind: kind,
            audioPath: audioPath,
            transcript: transcript,
            durationSec: audioPath == nil ? 0 : 3,
            commitmentID: commitmentID
        )
    }

    /// 約束する画面は、約束・アクション・つないだ声の 3 件を残す。記録タブには、つないだ声 1 件だけを出す。
    func testPromiseDayShowsOnlyTheJoinedVoice() throws {
        let commitmentID = UUID()
        let entries = [
            promiseEntry(at: try date(day: 6, hour: 9, minute: 2), kind: .declaration,
                         transcript: "請求書を出す。ファイルを開く", audioPath: "2026/09/joined.m4a",
                         commitmentID: commitmentID),
            promiseEntry(at: try date(day: 6, hour: 9, minute: 1), kind: .declaration,
                         transcript: "ファイルを開く", audioPath: "2026/09/action.m4a",
                         commitmentID: commitmentID),
            promiseEntry(at: try date(day: 6, hour: 9, minute: 0), kind: .avoidance,
                         transcript: "請求書を出す", audioPath: "2026/09/promise.m4a",
                         commitmentID: commitmentID),
        ]

        let sections = TimelineGrouping.sections(from: entries, calendar: calendar)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].entries.map(\.audioPath), ["2026/09/joined.m4a"])
        XCTAssertEqual(sections[0].entries.first?.transcript, "請求書を出す。ファイルを開く")
    }

    /// 声が片方だけの日は、つないだ声がその録音と同じファイルを指す。同じ声を 2 回並べない。
    func testPromiseDayWithOneVoiceDoesNotRepeatTheSameFile() throws {
        let commitmentID = UUID()
        let entries = [
            promiseEntry(at: try date(day: 6, hour: 9, minute: 2), kind: .declaration,
                         transcript: "請求書を出す。ファイルを開く", audioPath: "2026/09/promise.m4a",
                         commitmentID: commitmentID),
            promiseEntry(at: try date(day: 6, hour: 9, minute: 1), kind: .declaration,
                         transcript: "ファイルを開く", audioPath: nil, commitmentID: commitmentID),
            promiseEntry(at: try date(day: 6, hour: 9, minute: 0), kind: .avoidance,
                         transcript: "請求書を出す", audioPath: "2026/09/promise.m4a",
                         commitmentID: commitmentID),
        ]

        let visible = TimelineGrouping.collapsingPromiseVoices(entries)

        XCTAssertEqual(visible.count, 1)
        XCTAssertEqual(visible.first?.transcript, "請求書を出す。ファイルを開く")
    }

    /// 文字だけの約束（つないだ声が無い）と、旧い会話の日（宣言は 1 件）は、何も隠さない。
    func testDaysWithASingleDeclarationAreLeftAsTheyAre() throws {
        let textOnly = UUID()
        let legacy = UUID()
        let entries = [
            promiseEntry(at: try date(day: 6, hour: 9, minute: 1), kind: .declaration,
                         transcript: "ファイルを開く", audioPath: nil, commitmentID: textOnly),
            promiseEntry(at: try date(day: 6, hour: 9, minute: 0), kind: .avoidance,
                         transcript: "請求書を出す", audioPath: nil, commitmentID: textOnly),
            promiseEntry(at: try date(day: 4, hour: 8, minute: 14), kind: .declaration,
                         transcript: "14時に机で開く", audioPath: "2026/09/d1.m4a", commitmentID: legacy),
            promiseEntry(at: try date(day: 4, hour: 8, minute: 12), kind: .avoidance,
                         transcript: "請求書", audioPath: "2026/09/a1.m4a", commitmentID: legacy),
            promiseEntry(at: try date(day: 4, hour: 13, minute: 4), kind: .status,
                         transcript: "まだ", audioPath: nil, commitmentID: legacy),
        ]

        XCTAssertEqual(TimelineGrouping.collapsingPromiseVoices(entries), entries)
    }

    /// 1 件も無ければセクションも無い（空状態は画面側の 1 文で受ける）。
    func testNoEntriesProducesNoSections() {
        XCTAssertTrue(TimelineGrouping.sections(from: [], calendar: calendar).isEmpty)
    }
}
