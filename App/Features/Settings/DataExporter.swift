import Foundation
import SaydoCore
import SwiftData

// MARK: - 書き出す中身（純粋な値型）

/// `AvoidanceItem` 1 件の写し。
///
/// `@Model` のインスタンスはそのまま `Codable` にできないので値型へ写す。
/// 列挙は rawValue の文字列で持つ。zip を開くのは人間なので、数値より読める。
/// 名前を `Exported…` にしているのは、`Repository` が既に
/// `CommitmentSnapshot` / `VoiceEntrySnapshot` / `CarryoverSnapshot` を
/// 別の目的（画面へ返す値）で使っているため。
struct ExportedAvoidanceItem: Codable, Sendable, Equatable {
    var id: UUID
    var title: String
    var domain: String
    var status: String
    var createdAt: Date
    var lastTouchedAt: Date
}

/// `Commitment` 1 件の写し。
struct ExportedCommitment: Codable, Sendable, Equatable {
    var id: UUID
    var dayKey: String
    var microActionText: String
    var estimatedMinutes: Int
    var shrinkCount: Int
    var plannedAt: Date?
    var declarationAudioPath: String?
    var declarationTranscript: String
    var isVoiceless: Bool
    var outcome: String
    var reason: String?
    var progressNote: String?
    var createdAt: Date
    /// 逃げている対象。関係は ID で表す（JSON に入れ子を作らない）。
    var avoidanceItemID: UUID?
}

/// `VoiceEntry` 1 件の写し。
struct ExportedVoiceEntry: Codable, Sendable, Equatable {
    var id: UUID
    var recordedAt: Date
    var sessionType: String
    var kind: String
    /// zip の `Audio/` 以下の相対パスと同じ（`yyyy/MM/<uuid>.m4a`）。
    var audioPath: String?
    var transcript: String
    var durationSec: Double
    var commitmentID: UUID?
}

/// `SessionLog` 1 件の写し。
struct ExportedSessionLog: Codable, Sendable, Equatable {
    var id: UUID
    var sessionType: String
    var startedAt: Date
    var endedAt: Date?
    var completed: Bool
    var tier: String
    var lastStep: String?
    var guardrailReplacedCount: Int
}

/// `Carryover` 1 件の写し。
struct ExportedCarryover: Codable, Sendable, Equatable {
    var id: UUID
    var forDayKey: String
    var text: String
    var sourceEntryID: UUID?
    var createdAt: Date
}

/// 書き出し 1 回分の全レコード。zip の中の `saydo-export.json` はこの型そのもの。
struct ExportArchive: Codable, Sendable, Equatable {
    /// 書き出し形式の版。読み込み側（未実装。task_019 の non_scope）が形の違いを見分けるために持つ。
    var formatVersion: Int
    /// SwiftData スキーマの版（`SaydoSchemaV1.versionIdentifier`）。
    var schemaVersion: String
    var exportedAt: Date
    var appVersion: String
    var avoidanceItems: [ExportedAvoidanceItem]
    var commitments: [ExportedCommitment]
    var voiceEntries: [ExportedVoiceEntry]
    var sessionLogs: [ExportedSessionLog]
    var carryovers: [ExportedCarryover]

    static let currentFormatVersion = 1

    init(
        formatVersion: Int = ExportArchive.currentFormatVersion,
        schemaVersion: String = ExportArchive.schemaVersionString,
        exportedAt: Date,
        appVersion: String,
        avoidanceItems: [ExportedAvoidanceItem] = [],
        commitments: [ExportedCommitment] = [],
        voiceEntries: [ExportedVoiceEntry] = [],
        sessionLogs: [ExportedSessionLog] = [],
        carryovers: [ExportedCarryover] = []
    ) {
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.avoidanceItems = avoidanceItems
        self.commitments = commitments
        self.voiceEntries = voiceEntries
        self.sessionLogs = sessionLogs
        self.carryovers = carryovers
    }

    /// `SaydoSchemaV1` の版を `1.0.0` の形で返す。
    static var schemaVersionString: String {
        let version = SaydoSchemaV1.versionIdentifier
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    /// この書き出しに要る音声の相対パス（重複を除いて昇順）。
    ///
    /// 宣言音声は `Commitment.declarationAudioPath` と宣言の `VoiceEntry.audioPath` が
    /// 同一ファイルを指す（実装計画 §10）ので、両方から集めて重複を落とす。
    /// 同じファイルを zip に 2 回入れない。
    var audioRelativePaths: [String] {
        var paths = Set(voiceEntries.compactMap(\.audioPath))
        paths.formUnion(commitments.compactMap(\.declarationAudioPath))
        return paths.sorted()
    }

    /// 日付は ISO 8601、キーは昇順。差分を見るのが人間なので整形して書く。
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - 純ロジック（テストが直に呼ぶ）

/// 書き出しの組み立て。SwiftData も UI も触らない。
///
/// `DataExporter`（`@ModelActor`）から切り離してあるのは、
/// 「JSON に何が入るか」「zip に何が並ぶか」をストア無しで確かめられるようにするため。
struct DataExportBuilder: Sendable {
    enum ExportError: Error, Equatable {
        /// `NSFileCoordinator` が zip を作れなかった。
        case zipFailed(String)
        /// 呼び出しは成功したのに zip の実体が無い。
        case zipMissing
    }

    /// zip を展開すると出てくるフォルダ名。
    static let bundleDirectoryName = "saydo-export"
    /// 全レコードの JSON。
    static let manifestFileName = "saydo-export.json"
    /// 音声のフォルダ。中は `AudioFileStore` と同じ `yyyy/MM/<uuid>.m4a`。
    static let audioDirectoryName = "Audio"

    /// `saydo-export/` を作った結果。
    struct BundleReport: Sendable, Equatable {
        var bundleURL: URL
        var manifestURL: URL
        /// zip に入れた音声の相対パス（`yyyy/MM/<uuid>.m4a`）。
        var includedAudioPaths: [String]
        /// レコードは指しているが実体が無かった相対パス。書き出しは止めない。
        var missingAudioPaths: [String]
        /// 音声の合計バイト数。
        var audioByteCount: Int64
    }

    /// 書き出し 1 回の結果。
    struct Report: Sendable, Equatable {
        /// できあがった zip。ShareLink に渡す（UI は task_019 の別担当）。
        var zipURL: URL
        var includedAudioPaths: [String]
        var missingAudioPaths: [String]
        var audioByteCount: Int64
        var zipByteCount: Int64

        /// 音声 1 件あたりの平均バイト数。0 件なら nil。
        /// 実装計画 §10 の見積もり（約 60 KB/件）との突き合わせに使う。
        var averageAudioByteCount: Int64? {
            guard !includedAudioPaths.isEmpty else { return nil }
            return audioByteCount / Int64(includedAudioPaths.count)
        }
    }

    /// 音声ファイルの置き場所。
    let audioStore: AudioFileStore

    init(audioStore: AudioFileStore) {
        self.audioStore = audioStore
    }

    // MARK: 中身を並べる

    /// `parentDirectory` の下に `saydo-export/` を作り、JSON と音声を入れる。
    /// zip にする前の状態。テストはここだけを見ればファイル一覧を確かめられる。
    @discardableResult
    func writeBundle(_ archive: ExportArchive, into parentDirectory: URL) throws -> BundleReport {
        let manager = FileManager.default
        let bundleURL = parentDirectory.appending(
            path: Self.bundleDirectoryName,
            directoryHint: .isDirectory
        )
        if manager.fileExists(atPath: bundleURL.path(percentEncoded: false)) {
            try manager.removeItem(at: bundleURL)
        }
        try manager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let manifestURL = bundleURL.appending(
            path: Self.manifestFileName,
            directoryHint: .notDirectory
        )
        let json = try ExportArchive.makeEncoder().encode(archive)
        try json.write(to: manifestURL, options: [.atomic])

        let audioRoot = bundleURL.appending(
            path: Self.audioDirectoryName,
            directoryHint: .isDirectory
        )
        var included: [String] = []
        var missing: [String] = []
        var audioByteCount: Int64 = 0

        for relativePath in archive.audioRelativePaths {
            guard let source = sourceURL(forRelativePath: relativePath),
                  manager.fileExists(atPath: source.path(percentEncoded: false)) else {
                missing.append(relativePath)
                continue
            }
            let destination = audioRoot.appending(path: relativePath, directoryHint: .notDirectory)
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try manager.copyItem(at: source, to: destination)
            audioByteCount += Self.byteCount(of: destination)
            included.append(relativePath)
        }

        return BundleReport(
            bundleURL: bundleURL,
            manifestURL: manifestURL,
            includedAudioPaths: included,
            missingAudioPaths: missing,
            audioByteCount: audioByteCount
        )
    }

    /// JSON と音声を並べて zip にする。作業用ディレクトリは最後に消す。
    ///
    /// - Parameters:
    ///   - archive: 書き出す全レコード。
    ///   - workingDirectory: 作業用の親（この中に `saydo-export/` を作る）。
    ///   - zipDestination: できあがりの zip。既にあれば上書きする。
    func makeZipArchive(
        _ archive: ExportArchive,
        workingDirectory: URL,
        zipDestination: URL
    ) throws -> Report {
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let bundle = try writeBundle(archive, into: workingDirectory)
        let zipURL = try Self.makeZip(ofDirectoryAt: bundle.bundleURL, to: zipDestination)

        return Report(
            zipURL: zipURL,
            includedAudioPaths: bundle.includedAudioPaths,
            missingAudioPaths: bundle.missingAudioPaths,
            audioByteCount: bundle.audioByteCount,
            zipByteCount: Self.byteCount(of: zipURL)
        )
    }

    // MARK: zip

    /// ディレクトリを zip にする。
    ///
    /// `NSFileCoordinator` の `.forUploading` にディレクトリを渡すと、そのディレクトリを
    /// 根に持つ zip を作り、一時 URL をブロックへ渡す。ブロックを抜けると一時ファイルは
    /// 消えるので、中で `destination` へ複製する。
    ///
    /// 追加のライブラリを入れずに zip を作れるのはこの経路だけ。`Compression` は
    /// ストリーム圧縮であって zip 書庫を作らず、`AppleArchive` が作るのは `.aar` で、
    /// どちらも Mac の Finder でそのまま開けない。
    ///
    /// macOS 26.0 で挙動を確認済み（`saydo-export/…` の相対パスを保った zip になる）。
    /// iOS シミュレータ・実機での確認は `docs/backup-restore-check.md` の記入欄で行う。
    static func makeZip(ofDirectoryAt directory: URL, to destination: URL) throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destination)
        }

        var coordinatorError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
            } catch {
                copyError = error
            }
        }

        if let coordinatorError {
            throw ExportError.zipFailed(coordinatorError.localizedDescription)
        }
        if let copyError {
            throw copyError
        }
        guard FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            throw ExportError.zipMissing
        }
        return destination
    }

    // MARK: 名前とサイズ

    /// 書き出しファイル名（`saydo-export-20260904-060000.zip`）。
    ///
    /// 暦は西暦に固定し、時刻帯だけ端末に合わせる。`Calendar.current` を使わないのは、
    /// 端末の暦設定が和暦だと `dateComponents` の `.year` が元号の年になり
    /// （令和 8 年なら 8）、`saydo-export-00080904-…` という名前になってしまうため。
    /// `DateFormatter` を使わないのも同じ理由（ロケール依存を持ち込まない）。
    static func zipFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        return String(
            format: "saydo-export-%04d%02d%02d-%02d%02d%02d.zip",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }

    /// 1 ファイルのバイト数。読めなければ 0。
    static func byteCount(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: 内部

    /// 置き場所の内側を指していることを確かめた URL。外を指すなら nil。
    ///
    /// レコードの相対パスは自分で作ったものだが、`..` を含む値が
    /// 何かの拍子に入っていたときに置き場所の外を読まないための堰。
    private func sourceURL(forRelativePath relativePath: String) -> URL? {
        let fileURL = audioStore.url(forRelativePath: relativePath)
        let rootPath = audioStore.rootDirectory.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard fileURL.standardizedFileURL.path(percentEncoded: false).hasPrefix(prefix) else {
            return nil
        }
        return fileURL
    }
}

// MARK: - SwiftData から読む

/// 設定画面の「データを書き出す」（実装計画 §11、task_019）。
///
/// `Repository` と同じく `@ModelActor` にして `ModelContext` をアクターへ閉じる。
/// 読むだけで書かないので `Repository` とは別のアクターにしてある
/// （`Repository` の既存メソッドを増やさないため）。
@ModelActor
actor DataExporter {
    /// テストは一時ディレクトリの `AudioFileStore` を差し込む。
    private var injectedAudioFileStore: AudioFileStore?

    func configure(audioFileStore: AudioFileStore) {
        injectedAudioFileStore = audioFileStore
    }

    private func audioFileStore() throws -> AudioFileStore {
        if let injectedAudioFileStore { return injectedAudioFileStore }
        let store = try AudioFileStore.applicationSupport()
        injectedAudioFileStore = store
        return store
    }

    /// `CFBundleShortVersionString`。取れなければ `0`。
    static func bundleShortVersion(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// 全レコードを読んで書き出しの中身にする。作成順に並べる。
    func makeArchive(
        exportedAt: Date = .now,
        appVersion: String = DataExporter.bundleShortVersion()
    ) throws -> ExportArchive {
        let avoidanceItems = try modelContext.fetch(
            FetchDescriptor<AvoidanceItem>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )
        let commitments = try modelContext.fetch(
            FetchDescriptor<Commitment>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )
        let voiceEntries = try modelContext.fetch(
            FetchDescriptor<VoiceEntry>(sortBy: [SortDescriptor(\.recordedAt, order: .forward)])
        )
        let sessionLogs = try modelContext.fetch(
            FetchDescriptor<SessionLog>(sortBy: [SortDescriptor(\.startedAt, order: .forward)])
        )
        let carryovers = try modelContext.fetch(
            FetchDescriptor<Carryover>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )

        return ExportArchive(
            exportedAt: exportedAt,
            appVersion: appVersion,
            avoidanceItems: avoidanceItems.map { item in
                ExportedAvoidanceItem(
                    id: item.id,
                    title: item.title,
                    domain: item.domainRawValue,
                    status: item.statusRawValue,
                    createdAt: item.createdAt,
                    lastTouchedAt: item.lastTouchedAt
                )
            },
            commitments: commitments.map { commitment in
                ExportedCommitment(
                    id: commitment.id,
                    dayKey: commitment.dayKey,
                    microActionText: commitment.microActionText,
                    estimatedMinutes: commitment.estimatedMinutes,
                    shrinkCount: commitment.shrinkCount,
                    plannedAt: commitment.plannedAt,
                    declarationAudioPath: commitment.declarationAudioPath,
                    declarationTranscript: commitment.declarationTranscript,
                    isVoiceless: commitment.isVoiceless,
                    outcome: commitment.outcomeRawValue,
                    reason: commitment.reasonRawValue,
                    progressNote: commitment.progressNote,
                    createdAt: commitment.createdAt,
                    avoidanceItemID: commitment.avoidanceItem?.id
                )
            },
            voiceEntries: voiceEntries.map { entry in
                ExportedVoiceEntry(
                    id: entry.id,
                    recordedAt: entry.recordedAt,
                    sessionType: entry.sessionTypeRawValue,
                    kind: entry.kindRawValue,
                    audioPath: entry.audioPath,
                    transcript: entry.transcript,
                    durationSec: entry.durationSec,
                    commitmentID: entry.commitment?.id
                )
            },
            sessionLogs: sessionLogs.map { log in
                ExportedSessionLog(
                    id: log.id,
                    sessionType: log.sessionTypeRawValue,
                    startedAt: log.startedAt,
                    endedAt: log.endedAt,
                    completed: log.completed,
                    tier: log.tierRawValue,
                    lastStep: log.lastStepRawValue,
                    guardrailReplacedCount: log.guardrailReplacedCount
                )
            },
            carryovers: carryovers.map { carryover in
                ExportedCarryover(
                    id: carryover.id,
                    forDayKey: carryover.forDayKey,
                    text: carryover.text,
                    sourceEntryID: carryover.sourceEntryID,
                    createdAt: carryover.createdAt
                )
            }
        )
    }

    /// 書き出しを実行して zip の URL を返す。
    ///
    /// 置き場所は既定で `tmp/SaydoExport/`。ShareLink に渡したあとで
    /// 消えても構わない場所に置く（バックアップの対象にしない）。
    @discardableResult
    func export(
        exportedAt: Date = .now,
        appVersion: String = DataExporter.bundleShortVersion(),
        into parentDirectory: URL? = nil,
        timeZone: TimeZone = .current
    ) throws -> DataExportBuilder.Report {
        let archive = try makeArchive(exportedAt: exportedAt, appVersion: appVersion)
        let builder = DataExportBuilder(audioStore: try audioFileStore())

        let parent = parentDirectory ?? FileManager.default.temporaryDirectory
            .appending(path: "SaydoExport", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let working = parent.appending(
            path: "staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let zipDestination = parent.appending(
            path: DataExportBuilder.zipFileName(for: exportedAt, timeZone: timeZone),
            directoryHint: .notDirectory
        )
        return try builder.makeZipArchive(
            archive,
            workingDirectory: working,
            zipDestination: zipDestination
        )
    }
}
