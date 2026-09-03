import Foundation
import XCTest

@testable import Saydo

final class AudioFileStoreTests: XCTestCase {
    private var root: URL!
    private var store: AudioFileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = AudioFileStore(rootDirectory: root)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        store = nil
        root = nil
        try super.tearDownWithError()
    }

    // MARK: パス

    func testRelativePathUsesYearMonthAndUUID() throws {
        let id = UUID()
        let date = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 8))
        )

        let relative = store.relativePath(for: id, recordedAt: date)

        XCTAssertEqual(relative, "2026/03/\(id.uuidString.lowercased()).m4a")
    }

    func testURLForRelativePathIsUnderRoot() {
        let url = store.url(forRelativePath: "2026/03/a.m4a")

        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "03")
        XCTAssertTrue(
            url.path(percentEncoded: false)
                .hasPrefix(root.standardizedFileURL.path(percentEncoded: false))
        )
    }

    // MARK: 確保・削除

    func testAllocateCreatesParentDirectories() throws {
        let date = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31))
        )

        let allocated = try store.allocate(recordedAt: date)

        var isDirectory: ObjCBool = false
        let parent = allocated.url.deletingLastPathComponent().path(percentEncoded: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(allocated.relativePath.hasPrefix("2026/12/"))
        XCTAssertFalse(store.fileExists(atRelativePath: allocated.relativePath))
    }

    func testDeleteRemovesTheFileAndIsSafeWhenMissing() throws {
        let allocated = try store.allocate()
        try Data([0x01, 0x02]).write(to: allocated.url)
        XCTAssertTrue(store.fileExists(atRelativePath: allocated.relativePath))

        try store.delete(relativePath: allocated.relativePath)
        XCTAssertFalse(store.fileExists(atRelativePath: allocated.relativePath))

        // 2 回目は何もしない（例外を投げない）。
        try store.delete(relativePath: allocated.relativePath)
    }

    func testDeleteRejectsPathsOutsideTheRoot() {
        XCTAssertThrowsError(try store.delete(relativePath: "../escaped.m4a")) { error in
            XCTAssertEqual(
                error as? AudioFileStore.StoreError,
                .invalidRelativePath("../escaped.m4a")
            )
        }
    }

    // MARK: 一覧・孤児掃除

    func testAllRelativePathsFindsOnlyAudioFiles() throws {
        let audio = try store.allocate()
        try Data([0x00]).write(to: audio.url)
        let note = audio.url.deletingLastPathComponent().appending(path: "note.txt")
        try Data([0x00]).write(to: note)

        let found = try store.allRelativePaths()

        XCTAssertEqual(found, [audio.relativePath])
    }

    func testRemoveOrphansKeepsLivePathsAndDeletesTheRest() throws {
        let live = try store.allocate()
        try Data([0x00]).write(to: live.url)
        let orphan = try store.allocate()
        try Data([0x00]).write(to: orphan.url)

        let removed = try store.removeOrphans(keeping: [live.relativePath])

        XCTAssertEqual(removed, [orphan.relativePath])
        XCTAssertTrue(store.fileExists(atRelativePath: live.relativePath))
        XCTAssertFalse(store.fileExists(atRelativePath: orphan.relativePath))
    }

    func testRemoveOrphansOnMissingRootIsEmpty() throws {
        let missing = AudioFileStore(
            rootDirectory: root.appending(path: "does-not-exist", directoryHint: .isDirectory)
        )

        XCTAssertEqual(try missing.removeOrphans(keeping: []), [])
    }
}
