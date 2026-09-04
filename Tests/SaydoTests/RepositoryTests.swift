import Foundation
import SaydoCore
import XCTest

@testable import Saydo

final class RepositoryTests: XCTestCase {
    private var root: URL!
    private var store: AudioFileStore!
    private var repository: Repository!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoRepositoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = AudioFileStore(rootDirectory: root)
        repository = Repository(modelContainer: try SaydoModelContainer.make(inMemory: true))
        await repository.configure(audioFileStore: store)
    }

    override func tearDown() async throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        repository = nil
        store = nil
        root = nil
        try await super.tearDown()
    }

    // MARK: 補助

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) throws -> Date {
        try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
        )
    }

    private func draft(
        avoidance: String = "invoice",
        domain: TaskDomain = .money,
        reason: ReasonCategory? = .tedious,
        text: String = "open the file",
        at createdAt: Date,
        plannedAt: Date? = nil,
        plannedPlace: String? = nil,
        audioPath: String? = nil,
        isVoiceless: Bool = false
    ) -> CommitmentDraft {
        CommitmentDraft(
            avoidanceTitle: avoidance,
            domain: domain,
            reason: reason,
            microAction: MicroAction(text: text, estimatedMinutes: 5),
            plannedAt: plannedAt,
            plannedPlace: plannedPlace,
            declarationAudioPath: audioPath,
            declarationTranscript: audioPath == nil ? "" : "I will open the file",
            declarationDurationSec: audioPath == nil ? 0 : 12,
            isVoiceless: isVoiceless,
            createdAt: createdAt
        )
    }

    // MARK: 1 日 1 件

    func testCreateCommitmentStoresTheDayKeyAndAvoidanceItem() async throws {
        let day = try date(2026, 3, 9)

        let created = try await repository.createCommitment(draft(at: day))

        XCTAssertEqual(created.dayKey, "2026-03-09")
        XCTAssertEqual(created.avoidanceTitle, "invoice")
        XCTAssertEqual(created.domain, .money)
        XCTAssertEqual(created.reason, .tedious)
        XCTAssertEqual(created.outcome, .pending)
        XCTAssertEqual(created.microAction.shrinkCount, 0)
        XCTAssertNotNil(created.avoidanceID)
    }

    /// task_011: 「今日は捨てる」で dropped にした対象は翌日に同じ言葉で言っても使い回されず、
    /// 「明日に回す」で carriedOver にした対象は使い回される（生きている対象だけを再利用する）。
    func testAvoidanceStatusDecidesWhetherTheItemIsReusedTomorrow() async throws {
        let day1 = try date(2026, 3, 9)
        let day2 = try date(2026, 3, 10)
        let day3 = try date(2026, 3, 11)

        let first = try await repository.createCommitment(draft(at: day1))
        try await repository.updateAvoidanceStatus(commitmentID: first.id, status: .carriedOver, at: day1)
        let second = try await repository.createCommitment(draft(at: day2))
        XCTAssertEqual(second.avoidanceID, first.avoidanceID)

        try await repository.updateAvoidanceStatus(commitmentID: second.id, status: .dropped, at: day2)
        let third = try await repository.createCommitment(draft(at: day3))
        XCTAssertNotEqual(third.avoidanceID, first.avoidanceID)
    }

    /// done_definition: 同じ dayKey で 2 件目の Commitment を作ると拒否される。
    func testSecondCommitmentOnTheSameDayIsRejected() async throws {
        let morning = try date(2026, 3, 9, 8)
        let evening = try date(2026, 3, 9, 20)
        _ = try await repository.createCommitment(draft(at: morning))

        do {
            _ = try await repository.createCommitment(draft(avoidance: "another", at: evening))
            XCTFail("expected RepositoryError.commitmentAlreadyExists")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .commitmentAlreadyExists(dayKey: "2026-03-09"))
        }

        let today = try await repository.todayCommitment(on: evening)
        XCTAssertEqual(today?.avoidanceTitle, "invoice")
    }

    func testCommitmentOnTheNextDayIsAllowed() async throws {
        _ = try await repository.createCommitment(draft(at: try date(2026, 3, 9)))
        let second = try await repository.createCommitment(draft(at: try date(2026, 3, 10)))

        XCTAssertEqual(second.dayKey, "2026-03-10")
    }

    func testTodayCommitmentIsNilWithoutOne() async throws {
        let result = try await repository.todayCommitment(on: try date(2026, 3, 9))

        XCTAssertNil(result)
    }

    /// 統合判断 D1: M3 の「何時に、どこで？」の後半を保存し、読み戻せる（retention R11）。
    func testPlannedTimeAndPlaceAreStoredAndReadBack() async throws {
        let day = try date(2026, 3, 9)
        let plannedAt = try date(2026, 3, 9, 14)

        let created = try await repository.createCommitment(
            draft(at: day, plannedAt: plannedAt, plannedPlace: "机")
        )
        let reloaded = try await repository.todayCommitment(on: day)

        XCTAssertEqual(created.plannedAt, plannedAt)
        XCTAssertEqual(created.plannedPlace, "机")
        XCTAssertEqual(reloaded?.plannedAt, plannedAt)
        XCTAssertEqual(reloaded?.plannedPlace, "机")
    }

    /// 場所を聞けなかった日は nil のまま残る。
    func testPlannedPlaceStaysNilWhenItWasNotAsked() async throws {
        let day = try date(2026, 3, 10)

        let created = try await repository.createCommitment(draft(at: day))
        let reloaded = try await repository.todayCommitment(on: day)

        XCTAssertNil(created.plannedPlace)
        XCTAssertNil(reloaded?.plannedPlace)
    }

    // MARK: 宣言音声

    func testDeclarationAudioIsAlsoStoredAsAVoiceEntryWithTheSameFile() async throws {
        let day = try date(2026, 3, 9)
        let allocated = try store.allocate(recordedAt: day)
        try Data([0x00]).write(to: allocated.url)

        let created = try await repository.createCommitment(
            draft(at: day, audioPath: allocated.relativePath)
        )
        let entries = try await repository.entries(for: day)

        XCTAssertEqual(created.declarationAudioPath, allocated.relativePath)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.kind, .declaration)
        XCTAssertEqual(entries.first?.audioPath, allocated.relativePath)
        XCTAssertEqual(entries.first?.commitmentID, created.id)
        XCTAssertFalse(created.isVoiceless)
    }

    func testVoicelessCommitmentHasNoAudioAndNoVoiceEntry() async throws {
        let day = try date(2026, 3, 9)

        let created = try await repository.createCommitment(
            draft(at: day, audioPath: nil, isVoiceless: true)
        )
        let entries = try await repository.entries(for: day)

        XCTAssertTrue(created.isVoiceless)
        XCTAssertNil(created.declarationAudioPath)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: 更新

    func testUpdateOutcomeStoresOutcomeAndProgressNote() async throws {
        let day = try date(2026, 3, 9)
        let created = try await repository.createCommitment(draft(at: day))

        let updated = try await repository.updateOutcome(
            commitmentID: created.id,
            outcome: .partial,
            progressNote: "opened it",
            at: day
        )

        XCTAssertEqual(updated.outcome, .partial)
        XCTAssertTrue(updated.outcome.isProgress)
        XCTAssertEqual(updated.progressNote, "opened it")
    }

    func testShrinkIncrementsShrinkCountAndReplacesTheText() async throws {
        let day = try date(2026, 3, 9)
        let created = try await repository.createCommitment(draft(at: day))

        let first = try await repository.shrink(commitmentID: created.id, to: "just open it", estimatedMinutes: 2)
        let second = try await repository.shrink(commitmentID: created.id, to: "put it on the desk", estimatedMinutes: 1)

        XCTAssertEqual(first.microAction.shrinkCount, 1)
        XCTAssertEqual(second.microAction.shrinkCount, 2)
        XCTAssertEqual(second.microAction.text, "put it on the desk")
        XCTAssertEqual(second.microAction.estimatedMinutes, 1)
    }

    func testUpdatingAnUnknownCommitmentThrows() async throws {
        let unknown = UUID()

        do {
            _ = try await repository.updateOutcome(commitmentID: unknown, outcome: .done)
            XCTFail("expected RepositoryError.commitmentNotFound")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .commitmentNotFound(id: unknown))
        }
    }

    // MARK: 音声の一覧と削除

    func testEntriesForDayAreFilteredAndSortedAscending() async throws {
        let day = try date(2026, 3, 9)
        let later = try date(2026, 3, 9, 20)
        let nextDay = try date(2026, 3, 10)

        _ = try await repository.appendVoiceEntry(
            VoiceEntryDraft(recordedAt: later, sessionType: .night, kind: .progress, transcript: "b")
        )
        _ = try await repository.appendVoiceEntry(
            VoiceEntryDraft(recordedAt: day, sessionType: .morning, kind: .avoidance, transcript: "a")
        )
        _ = try await repository.appendVoiceEntry(
            VoiceEntryDraft(recordedAt: nextDay, sessionType: .morning, kind: .avoidance, transcript: "c")
        )

        let entries = try await repository.entries(for: day)

        XCTAssertEqual(entries.map(\.transcript), ["a", "b"])
    }

    /// done_definition: VoiceEntry 削除で音声ファイルが消える。
    func testDeletingAVoiceEntryDeletesItsAudioFile() async throws {
        let day = try date(2026, 3, 9)
        let allocated = try store.allocate(recordedAt: day)
        try Data([0x00, 0x01]).write(to: allocated.url)
        let entry = try await repository.appendVoiceEntry(
            VoiceEntryDraft(
                recordedAt: day,
                sessionType: .morning,
                kind: .avoidance,
                audioPath: allocated.relativePath,
                transcript: "a"
            )
        )
        XCTAssertTrue(store.fileExists(atRelativePath: allocated.relativePath))

        try await repository.deleteVoiceEntry(id: entry.id)

        XCTAssertFalse(store.fileExists(atRelativePath: allocated.relativePath))
        let remaining = try await repository.entries(for: day)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeletingTheDeclarationEntryAlsoClearsTheCommitmentReference() async throws {
        let day = try date(2026, 3, 9)
        let allocated = try store.allocate(recordedAt: day)
        try Data([0x00]).write(to: allocated.url)
        let created = try await repository.createCommitment(
            draft(at: day, audioPath: allocated.relativePath)
        )
        let declarationEntries = try await repository.entries(for: day)
        let entry = try XCTUnwrap(declarationEntries.first)

        try await repository.deleteVoiceEntry(id: entry.id)

        let reloaded = try await repository.commitment(id: created.id)
        XCTAssertNil(reloaded?.declarationAudioPath)
        XCTAssertFalse(store.fileExists(atRelativePath: allocated.relativePath))
    }

    func testSweepRemovesOnlyFilesWithoutAVoiceEntry() async throws {
        let day = try date(2026, 3, 9)
        let kept = try store.allocate(recordedAt: day)
        try Data([0x00]).write(to: kept.url)
        let orphan = try store.allocate(recordedAt: day)
        try Data([0x00]).write(to: orphan.url)
        _ = try await repository.appendVoiceEntry(
            VoiceEntryDraft(
                recordedAt: day,
                sessionType: .morning,
                kind: .avoidance,
                audioPath: kept.relativePath
            )
        )

        let removed = try await repository.sweepOrphanAudioFiles()

        XCTAssertEqual(removed, [orphan.relativePath])
        XCTAssertTrue(store.fileExists(atRelativePath: kept.relativePath))
        XCTAssertFalse(store.fileExists(atRelativePath: orphan.relativePath))
    }

    func testLastEntryDateReturnsTheNewestRecording() async throws {
        let noEntryYet = try await repository.lastEntryDate()
        XCTAssertNil(noEntryYet)
        let older = try date(2026, 3, 9)
        let newer = try date(2026, 3, 12, 21)
        _ = try await repository.appendVoiceEntry(
            VoiceEntryDraft(recordedAt: older, sessionType: .morning, kind: .avoidance)
        )
        _ = try await repository.appendVoiceEntry(
            VoiceEntryDraft(recordedAt: newer, sessionType: .night, kind: .progress)
        )

        let latest = try await repository.lastEntryDate()
        XCTAssertEqual(latest, newer)
    }

    // MARK: 引き継ぎ

    func testCarryoverIsReadBackForTheTargetDayAndOverwritten() async throws {
        let tomorrow = try date(2026, 3, 10)
        _ = try await repository.saveCarryover(forDay: tomorrow, text: "the invoice again", at: try date(2026, 3, 9, 21))
        _ = try await repository.saveCarryover(forDay: tomorrow, text: "the invoice, smaller", at: try date(2026, 3, 9, 22))

        let carryover = try await repository.carryover(for: tomorrow)

        XCTAssertEqual(carryover?.forDayKey, "2026-03-10")
        XCTAssertEqual(carryover?.text, "the invoice, smaller")
        let otherDay = try await repository.carryover(for: try date(2026, 3, 11))
        XCTAssertNil(otherDay)
    }

    // MARK: 週次集計

    func testWeeklyStatsCountsDomainsAndRatiosReasonsOverCommitmentsThatHaveOne() async throws {
        let start = try date(2026, 3, 9, 0)
        let end = try date(2026, 3, 16, 0)
        _ = try await repository.createCommitment(
            draft(avoidance: "invoice", domain: .money, reason: .tedious, at: try date(2026, 3, 9))
        )
        _ = try await repository.createCommitment(
            draft(avoidance: "tax form", domain: .money, reason: .tedious, at: try date(2026, 3, 10))
        )
        _ = try await repository.createCommitment(
            draft(avoidance: "reply to Aki", domain: .reply, reason: .awkward, at: try date(2026, 3, 11))
        )
        // 短縮版の朝フロー（理由を聞かない）。分野は数えるが理由の母数には入れない。
        _ = try await repository.createCommitment(
            draft(avoidance: "gym", domain: .health, reason: nil, at: try date(2026, 3, 12))
        )
        // 集計の外。
        _ = try await repository.createCommitment(
            draft(avoidance: "old thing", domain: .paperwork, reason: .anxious, at: try date(2026, 3, 8))
        )

        let stats = try await repository.weeklyStats(from: start, to: end)

        XCTAssertEqual(stats.weekStart, start)
        XCTAssertEqual(stats.totalCount, 4)
        XCTAssertEqual(stats.domainCounts[.money], 2)
        XCTAssertEqual(stats.domainCounts[.reply], 1)
        XCTAssertEqual(stats.domainCounts[.health], 1)
        XCTAssertNil(stats.domainCounts[.paperwork])
        XCTAssertEqual(try XCTUnwrap(stats.reasonRatios[.tedious]), 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(stats.reasonRatios[.awkward]), 1.0 / 3.0, accuracy: 0.0001)
        XCTAssertNil(stats.reasonRatios[.anxious])
        XCTAssertEqual(stats.topDomains(limit: 1), [.money])
        XCTAssertEqual(stats.topReasons(limit: 1), [.tedious])
    }

    func testWeeklyStatsIsEmptyWithoutData() async throws {
        let stats = try await repository.weeklyStats(from: try date(2026, 3, 9), to: try date(2026, 3, 16))

        XCTAssertEqual(stats.totalCount, 0)
        XCTAssertTrue(stats.reasonRatios.isEmpty)
    }
}
