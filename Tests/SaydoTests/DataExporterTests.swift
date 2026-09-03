import Foundation
import XCTest
@testable import Saydo

/// `DataExporter` の純ロジック（`DataExportBuilder`）のテスト（task_019）。
///
/// SwiftData を起こさずに、JSON の中身と zip に並ぶファイルだけを確かめる。
/// `DataExporter` 本体（`@ModelActor`）の経路は `ModelContainer` が要るので、
/// ここでは扱わない（実機・シミュレータでの確認は `docs/backup-restore-check.md`）。
final class DataExporterTests: XCTestCase {

    // MARK: 準備

    /// この 1 件分の作業ディレクトリ。
    private var workRoot: URL!
    /// 音声の置き場所（本番の Application Support ではなく一時ディレクトリ）。
    private var audioStore: AudioFileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory
            .appending(path: "DataExporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workRoot = root
        audioStore = AudioFileStore(
            rootDirectory: root.appending(path: "Audio", directoryHint: .isDirectory)
        )
    }

    override func tearDownWithError() throws {
        if let workRoot {
            try? FileManager.default.removeItem(at: workRoot)
        }
        workRoot = nil
        audioStore = nil
        try super.tearDownWithError()
    }

    // MARK: JSON

    func testArchiveRoundTripsThroughJSON() throws {
        let archive = Self.makeArchive()

        let data = try ExportArchive.makeEncoder().encode(archive)
        let decoded = try ExportArchive.makeDecoder().decode(ExportArchive.self, from: data)

        XCTAssertEqual(decoded, archive)
    }

    func testManifestJSONCarriesEveryModelCollection() throws {
        let archive = Self.makeArchive()

        let data = try ExportArchive.makeEncoder().encode(archive)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        // 実装計画 §10 の 5 モデルが全部入っていること。
        XCTAssertEqual((object["avoidanceItems"] as? [Any])?.count, 1)
        XCTAssertEqual((object["commitments"] as? [Any])?.count, 1)
        XCTAssertEqual((object["voiceEntries"] as? [Any])?.count, 2)
        XCTAssertEqual((object["sessionLogs"] as? [Any])?.count, 1)
        XCTAssertEqual((object["carryovers"] as? [Any])?.count, 1)

        XCTAssertEqual(object["formatVersion"] as? Int, ExportArchive.currentFormatVersion)
        XCTAssertEqual(object["schemaVersion"] as? String, "1.0.0")
        XCTAssertEqual(object["appVersion"] as? String, "0.1.0")
        // 日付は ISO 8601 の文字列で出す（Mac で開いた人がそのまま読める）。
        XCTAssertEqual(object["exportedAt"] as? String, "2026-09-04T06:15:00Z")
    }

    func testManifestKeepsTheUsersOwnWordsVerbatim() throws {
        let archive = Self.makeArchive()

        let data = try ExportArchive.makeEncoder().encode(archive)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try XCTUnwrap(object["avoidanceItems"] as? [[String: Any]])

        // 本人の言葉を書き換えない（企画原則 §22-6）。
        XCTAssertEqual(items.first?["title"] as? String, "請求書の返信")
    }

    // MARK: 中身の並び

    func testBundleContainsManifestAndAudioFiles() throws {
        try writeAudioFixture(relativePath: "2026/09/aaa.m4a", byteCount: 61_440)
        try writeAudioFixture(relativePath: "2026/09/bbb.m4a", byteCount: 58_000)

        let builder = DataExportBuilder(audioStore: audioStore)
        let report = try builder.writeBundle(Self.makeArchive(), into: workRoot)

        XCTAssertEqual(report.includedAudioPaths, ["2026/09/aaa.m4a", "2026/09/bbb.m4a"])
        XCTAssertEqual(report.missingAudioPaths, [])
        XCTAssertEqual(report.audioByteCount, 119_440)

        XCTAssertEqual(
            Self.relativeFileList(under: report.bundleURL),
            [
                "Audio/2026/09/aaa.m4a",
                "Audio/2026/09/bbb.m4a",
                "saydo-export.json"
            ]
        )
    }

    /// 宣言音声は `Commitment.declarationAudioPath` と宣言の `VoiceEntry.audioPath` が
    /// 同一ファイルを指す（実装計画 §10）。zip に 2 回入れない。
    func testDeclarationAudioIsCopiedOnlyOnce() throws {
        try writeAudioFixture(relativePath: "2026/09/aaa.m4a", byteCount: 1_024)
        try writeAudioFixture(relativePath: "2026/09/bbb.m4a", byteCount: 1_024)

        let archive = Self.makeArchive()
        XCTAssertEqual(archive.commitments.first?.declarationAudioPath, "2026/09/aaa.m4a")
        XCTAssertEqual(archive.voiceEntries.first?.audioPath, "2026/09/aaa.m4a")

        let builder = DataExportBuilder(audioStore: audioStore)
        let report = try builder.writeBundle(archive, into: workRoot)

        XCTAssertEqual(report.includedAudioPaths.filter { $0 == "2026/09/aaa.m4a" }.count, 1)
    }

    /// ファイルが欠けていても書き出しは止めない。欠けたパスだけ報告する。
    func testMissingAudioIsReportedWithoutStoppingTheExport() throws {
        try writeAudioFixture(relativePath: "2026/09/aaa.m4a", byteCount: 1_024)

        let builder = DataExportBuilder(audioStore: audioStore)
        let report = try builder.writeBundle(Self.makeArchive(), into: workRoot)

        XCTAssertEqual(report.includedAudioPaths, ["2026/09/aaa.m4a"])
        XCTAssertEqual(report.missingAudioPaths, ["2026/09/bbb.m4a"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: report.manifestURL.path(percentEncoded: false)
            )
        )
    }

    /// 置き場所の外を指す相対パスは読みにいかない。
    func testPathOutsideTheAudioStoreIsNotCopied() throws {
        let outside = try XCTUnwrap(workRoot).appending(path: "outside.m4a", directoryHint: .notDirectory)
        try Data(repeating: 0x41, count: 16).write(to: outside)

        var archive = Self.makeArchive()
        archive.voiceEntries = [
            ExportedVoiceEntry(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!,
                recordedAt: Self.fixedDate,
                sessionType: "morning",
                kind: "declaration",
                audioPath: "../outside.m4a",
                transcript: "",
                durationSec: 1
            )
        ]
        archive.commitments = []

        let builder = DataExportBuilder(audioStore: audioStore)
        let report = try builder.writeBundle(archive, into: workRoot)

        XCTAssertEqual(report.includedAudioPaths, [])
        XCTAssertEqual(report.missingAudioPaths, ["../outside.m4a"])
        XCTAssertEqual(Self.relativeFileList(under: report.bundleURL), ["saydo-export.json"])
    }

    // MARK: zip

    func testZipContainsTheManifestAndTheAudioFile() throws {
        try writeAudioFixture(relativePath: "2026/09/aaa.m4a", byteCount: 2_048)
        try writeAudioFixture(relativePath: "2026/09/bbb.m4a", byteCount: 2_048)

        let builder = DataExportBuilder(audioStore: audioStore)
        let destination = try XCTUnwrap(workRoot)
            .appending(path: "out.zip", directoryHint: .notDirectory)
        let report = try builder.makeZipArchive(
            Self.makeArchive(),
            workingDirectory: try XCTUnwrap(workRoot).appending(path: "staging", directoryHint: .isDirectory),
            zipDestination: destination
        )

        XCTAssertEqual(report.zipURL, destination)
        XCTAssertGreaterThan(report.zipByteCount, 0)

        let bytes = try Data(contentsOf: destination)
        // zip のローカルファイルヘッダは "PK\u{03}\u{04}" で始まる。
        XCTAssertEqual(bytes.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))
        // ファイル名はヘッダに素で入るので、バイト列を探せば入っているか分かる。
        XCTAssertNotNil(bytes.range(of: Data("saydo-export/saydo-export.json".utf8)))
        XCTAssertNotNil(bytes.range(of: Data("saydo-export/Audio/2026/09/aaa.m4a".utf8)))
        XCTAssertNotNil(bytes.range(of: Data("saydo-export/Audio/2026/09/bbb.m4a".utf8)))

        // 作業用ディレクトリは残さない。
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(workRoot).appending(path: "staging").path(percentEncoded: false)
            )
        )
    }

    func testAverageAudioByteCountMatchesTheCapacityEstimate() throws {
        // 実装計画 §10 の見積もりは 15 秒でおよそ 60 KB/件。
        try writeAudioFixture(relativePath: "2026/09/aaa.m4a", byteCount: 61_440)
        try writeAudioFixture(relativePath: "2026/09/bbb.m4a", byteCount: 61_440)

        let builder = DataExportBuilder(audioStore: audioStore)
        let destination = try XCTUnwrap(workRoot).appending(path: "out.zip", directoryHint: .notDirectory)
        let report = try builder.makeZipArchive(
            Self.makeArchive(),
            workingDirectory: try XCTUnwrap(workRoot).appending(path: "staging", directoryHint: .isDirectory),
            zipDestination: destination
        )

        XCTAssertEqual(report.averageAudioByteCount, 61_440)
    }

    // MARK: ファイル名

    func testZipFileNameIsGregorianEvenOnAJapaneseCalendarDevice() {
        let name = DataExportBuilder.zipFileName(
            for: Self.fixedDate,
            timeZone: TimeZone(identifier: "UTC")!
        )

        // 和暦の端末でも `saydo-export-00080904-…` にならないこと。
        XCTAssertEqual(name, "saydo-export-20260904-061500.zip")
    }

    func testZipFileNameFollowsTheDeviceTimeZone() {
        let name = DataExportBuilder.zipFileName(
            for: Self.fixedDate,
            timeZone: TimeZone(identifier: "Asia/Tokyo")!
        )

        XCTAssertEqual(name, "saydo-export-20260904-151500.zip")
    }

    // MARK: - 素材

    /// 2026-09-04T06:15:00Z。
    private static let fixedDate = Date(timeIntervalSince1970: 1_788_502_500)

    private static func makeArchive() -> ExportArchive {
        let avoidanceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let commitmentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!

        return ExportArchive(
            exportedAt: fixedDate,
            appVersion: "0.1.0",
            avoidanceItems: [
                ExportedAvoidanceItem(
                    id: avoidanceID,
                    title: "請求書の返信",
                    domain: "money",
                    status: "open",
                    createdAt: fixedDate,
                    lastTouchedAt: fixedDate
                )
            ],
            commitments: [
                ExportedCommitment(
                    id: commitmentID,
                    dayKey: "2026-09-04",
                    microActionText: "メールを開くだけ",
                    estimatedMinutes: 5,
                    shrinkCount: 0,
                    plannedAt: fixedDate,
                    // 宣言音声は宣言の VoiceEntry と同じファイルを指す。
                    declarationAudioPath: "2026/09/aaa.m4a",
                    declarationTranscript: "メールを開くだけ、やる",
                    isVoiceless: false,
                    outcome: "pending",
                    reason: "awkward",
                    progressNote: nil,
                    createdAt: fixedDate,
                    avoidanceItemID: avoidanceID
                )
            ],
            voiceEntries: [
                ExportedVoiceEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!,
                    recordedAt: fixedDate,
                    sessionType: "morning",
                    kind: "declaration",
                    audioPath: "2026/09/aaa.m4a",
                    transcript: "メールを開くだけ、やる",
                    durationSec: 3.2,
                    commitmentID: commitmentID
                ),
                ExportedVoiceEntry(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!,
                    recordedAt: fixedDate,
                    sessionType: "night",
                    kind: "progress",
                    audioPath: "2026/09/bbb.m4a",
                    transcript: "開くところまではできた",
                    durationSec: 4.1,
                    commitmentID: commitmentID
                )
            ],
            sessionLogs: [
                ExportedSessionLog(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!,
                    sessionType: "morning",
                    startedAt: fixedDate,
                    endedAt: fixedDate,
                    completed: true,
                    tier: "B",
                    lastStep: "END",
                    guardrailReplacedCount: 0
                )
            ],
            carryovers: [
                ExportedCarryover(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                    forDayKey: "2026-09-05",
                    text: "続きを 1 行だけ書く",
                    sourceEntryID: UUID(uuidString: "00000000-0000-0000-0000-0000000000E2")!,
                    createdAt: fixedDate
                )
            ]
        )
    }

    /// `audioStore` の下にダミーの音声ファイルを置く。
    private func writeAudioFixture(relativePath: String, byteCount: Int) throws {
        let url = audioStore.url(forRelativePath: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: byteCount).write(to: url)
    }

    /// ディレクトリ以下の通常ファイルを相対パスの昇順で返す。
    private static func relativeFileList(under directory: URL) -> [String] {
        let base = directory.standardizedFileURL.path(percentEncoded: false)
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard let walker = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var found: [String] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard path.hasPrefix(prefix) else { continue }
            found.append(String(path.dropFirst(prefix.count)))
        }
        return found.sorted()
    }
}
