import Foundation

/// 端末内の音声ファイル置き場（実装計画 §7.1 / §10）。
///
/// - 置き場所: `Application Support/Saydo/Audio/yyyy/MM/<uuid>.m4a`
/// - ファイル保護: `completeUntilFirstUserAuthentication`。
///   通知タップ直後（端末ロック中）に宣言音声を再生する必要があるため、
///   `complete` ではなくこの水準にする（実装計画 §7.1）。
/// - iCloud バックアップからは**除外しない**（実装計画 §6-4）。
///
/// モデルが持つのは相対パスだけ。絶対パスを持たないのは、再インストールや復元で
/// アプリコンテナの UUID が変わり、保存済みの絶対パスが必ず外れるため。
struct AudioFileStore: Sendable {
    enum StoreError: Error, Equatable {
        /// 相対パスが `yyyy/MM/<name>` の形になっていない、または `..` を含む。
        case invalidRelativePath(String)
    }

    /// 拡張子（AAC 32 kbps モノラル、実装計画 §7.3）。
    static let fileExtension = "m4a"

    /// `Application Support/Saydo/Audio`。
    let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    /// 本番の置き場所。ディレクトリが無ければ作る。
    static func applicationSupport() throws -> AudioFileStore {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appending(path: "Saydo", directoryHint: .isDirectory)
            .appending(path: "Audio", directoryHint: .isDirectory)
        let store = AudioFileStore(rootDirectory: root)
        try store.createDirectoryIfNeeded(at: root)
        return store
    }

    // MARK: - パス

    /// 保存先の相対パス（`yyyy/MM/<uuid>.m4a`）を組み立てる。
    func relativePath(for id: UUID, recordedAt: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: recordedAt)
        return String(
            format: "%04d/%02d/%@.%@",
            parts.year ?? 0,
            parts.month ?? 0,
            id.uuidString.lowercased(),
            Self.fileExtension
        )
    }

    /// 相対パスから絶対 URL を作る。
    func url(forRelativePath relativePath: String) -> URL {
        rootDirectory.appending(path: relativePath, directoryHint: .notDirectory)
    }

    /// 新しい音声 1 件分の置き場所を確保する（親ディレクトリまで作る）。
    /// 書き込み自体は呼び出し側（task_007 の `VoiceCapture`）が行う。
    func allocate(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        calendar: Calendar = .current
    ) throws -> (relativePath: String, url: URL) {
        let relative = relativePath(for: id, recordedAt: recordedAt, calendar: calendar)
        let fileURL = url(forRelativePath: relative)
        try createDirectoryIfNeeded(at: fileURL.deletingLastPathComponent())
        return (relative, fileURL)
    }

    // MARK: - 読み書き

    func fileExists(atRelativePath relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forRelativePath: relativePath).path(percentEncoded: false))
    }

    /// 書き込み後に呼ぶ。ファイル保護属性を付ける。
    func applyProtection(toRelativePath relativePath: String) throws {
        try applyProtection(to: url(forRelativePath: relativePath))
    }

    /// 1 件削除する。存在しない場合は何もしない。
    /// 置き場所の外を指す相対パス（`..` を含むなど）は `invalidRelativePath` で拒否する。
    func delete(relativePath: String) throws {
        let fileURL = try validatedURL(forRelativePath: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    /// 置き場所にある音声ファイルの相対パスを全部返す。
    func allRelativePaths() throws -> [String] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: rootDirectory.path(percentEncoded: false)) else { return [] }
        guard let walker = manager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPath = rootDirectory.standardizedFileURL.path(percentEncoded: false)
        var found: [String] = []
        for case let fileURL as URL in walker {
            guard fileURL.pathExtension.lowercased() == Self.fileExtension else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let absolute = fileURL.standardizedFileURL.path(percentEncoded: false)
            guard absolute.hasPrefix(rootPath) else { continue }
            var relative = String(absolute.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            found.append(relative)
        }
        return found.sorted()
    }

    /// `livePaths` に無いファイルを消す（孤児掃除）。消した相対パスを返す。
    ///
    /// `livePaths` には `VoiceEntry.audioPath` だけを渡す。宣言音声は
    /// `Commitment.declarationAudioPath` と宣言の `VoiceEntry.audioPath` が
    /// 同一ファイルを指す不変条件があるので、`VoiceEntry` 側だけで足りる。
    ///
    /// 録音中のファイルを消さないよう、**起動時に 1 回だけ**呼ぶ（実装計画 §10）。
    @discardableResult
    func removeOrphans(keeping livePaths: Set<String>) throws -> [String] {
        var removed: [String] = []
        for relative in try allRelativePaths() where !livePaths.contains(relative) {
            try delete(relativePath: relative)
            removed.append(relative)
        }
        return removed
    }

    // MARK: - 内部

    /// 置き場所の内側を指していることを確かめた URL を返す。
    private func validatedURL(forRelativePath relativePath: String) throws -> URL {
        let fileURL = url(forRelativePath: relativePath)
        let rootPath = rootDirectory.standardizedFileURL.path(percentEncoded: false)
        let filePath = fileURL.standardizedFileURL.path(percentEncoded: false)
        guard filePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw StoreError.invalidRelativePath(relativePath)
        }
        return fileURL
    }

    private func createDirectoryIfNeeded(at directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: attributes
        )
    }

    /// ファイル保護は iOS の機能。macOS でテストを回すときは何もしない。
    private func applyProtection(to fileURL: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path(percentEncoded: false)
        )
        #endif
    }
}
