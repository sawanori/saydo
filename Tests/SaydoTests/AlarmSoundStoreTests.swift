import AVFoundation
import Foundation
import XCTest

@testable import Saydo

/// テスト用の録音（AAC の .m4a）を作る。`VoiceCapture` と同じ入れ物と符号化にする。
enum AlarmTestAudio {
    static func writeVoice(to url: URL, seconds: Double, sampleRate: Double = 48_000) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 48_000
        let total = Int(seconds * sampleRate)
        var written = 0
        while written < total {
            let count = min(Int(chunk), total - written)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk))
            buffer.frameLength = AVAudioFrameCount(count)
            let samples = try XCTUnwrap(buffer.floatChannelData)[0]
            for index in 0..<count {
                samples[index] = 0.3 * sinf(2 * .pi * 440 * Float(written + index) / Float(sampleRate))
            }
            try file.write(from: buffer)
            written += count
        }
        file.close()
    }
}

final class AlarmSoundStoreTests: XCTestCase {
    private var root: URL!
    private var audioFiles: AudioFileStore!
    private var soundsDirectory: URL!
    private var store: AlarmSoundStore!

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoAlarmSoundStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        audioFiles = AudioFileStore(rootDirectory: root.appending(path: "Audio", directoryHint: .isDirectory))
        soundsDirectory = root.appending(path: "Library", directoryHint: .isDirectory)
            .appending(path: "Sounds", directoryHint: .isDirectory)
        store = AlarmSoundStore(soundsDirectory: soundsDirectory, audioFileStore: audioFiles)
    }

    override func tearDownWithError() throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        store = nil
        audioFiles = nil
        soundsDirectory = nil
        root = nil
        try super.tearDownWithError()
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 16) throws -> Date {
        try XCTUnwrap(tokyo.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func makeVoice(seconds: Double, sampleRate: Double = 48_000) throws -> String {
        let allocation = try audioFiles.allocate(recordedAt: try day(2026, 10, 6), calendar: tokyo)
        try AlarmTestAudio.writeVoice(to: allocation.url, seconds: seconds, sampleRate: sampleRate)
        return allocation.relativePath
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: 書き出し

    func testExportWritesACafIntoTheSoundsDirectory() throws {
        let path = try makeVoice(seconds: 4)
        let start = try day(2026, 10, 6)

        let name = try XCTUnwrap(store.export(relativePath: path, for: start, calendar: tokyo))

        XCTAssertEqual(name, "saydo-alarm-20261006.caf")
        XCTAssertEqual(name, store.fileName(for: start, calendar: tokyo))
        let written = soundsDirectory.appending(path: name)
        XCTAssertTrue(exists(written))
        XCTAssertEqual(written.deletingLastPathComponent().lastPathComponent, "Sounds")

        // 実機で鳴ることを確かめた形式（IMA4 / 44.1 kHz / 1ch）。
        let file = try AVAudioFile(forReading: written)
        XCTAssertEqual(file.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatAppleIMA4)
        XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertEqual(seconds, 4, accuracy: 0.2)

        // 書きかけのファイルを残さない。
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: soundsDirectory.path(percentEncoded: false))
        XCTAssertEqual(leftovers, [name])
    }

    func testExportCutsEverythingBeyondThirtySeconds() throws {
        let path = try makeVoice(seconds: 36)

        let name = try XCTUnwrap(store.export(relativePath: path, for: try day(2026, 10, 6), calendar: tokyo))

        let file = try AVAudioFile(forReading: soundsDirectory.appending(path: name))
        let seconds = Double(file.length) / file.fileFormat.sampleRate
        XCTAssertLessThanOrEqual(seconds, AlarmSoundStore.maximumDuration)
        XCTAssertGreaterThan(seconds, AlarmSoundStore.maximumDuration - 0.5)

        // AVAudioPlayer が報告する長さでも 30 秒を超えない。
        let player = try AVAudioPlayer(contentsOf: soundsDirectory.appending(path: name))
        XCTAssertLessThanOrEqual(player.duration, AlarmSoundStore.maximumDuration)
    }

    func testExportResamplesAVoiceRecordedAtAnotherRate() throws {
        let path = try makeVoice(seconds: 3, sampleRate: 24_000)

        let name = try XCTUnwrap(store.export(relativePath: path, for: try day(2026, 10, 6), calendar: tokyo))

        let file = try AVAudioFile(forReading: soundsDirectory.appending(path: name))
        XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 3, accuracy: 0.2)
    }

    func testExportReplacesTheSameDaysFile() throws {
        let start = try day(2026, 10, 6)
        let long = try makeVoice(seconds: 6)
        let short = try makeVoice(seconds: 2)

        XCTAssertNotNil(store.export(relativePath: long, for: start, calendar: tokyo))
        let name = try XCTUnwrap(store.export(relativePath: short, for: start, calendar: tokyo))

        let file = try AVAudioFile(forReading: soundsDirectory.appending(path: name))
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 2, accuracy: 0.2)
    }

    // MARK: 失敗

    func testExportReturnsNilWhenTheVoiceIsMissing() throws {
        XCTAssertNil(store.export(relativePath: "2026/10/missing.m4a", for: try day(2026, 10, 6), calendar: tokyo))
        XCTAssertFalse(exists(store.url(for: try day(2026, 10, 6), calendar: tokyo)))
    }

    func testExportReturnsNilWhenTheVoiceIsNotAudio() throws {
        let allocation = try audioFiles.allocate(recordedAt: try day(2026, 10, 6), calendar: tokyo)
        try Data("not audio".utf8).write(to: allocation.url)

        XCTAssertNil(store.export(relativePath: allocation.relativePath, for: try day(2026, 10, 6), calendar: tokyo))

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: soundsDirectory.path(percentEncoded: false))) ?? []
        XCTAssertEqual(leftovers, [])
    }

    // MARK: 名前と削除

    func testFileNameIsDecidedByTheDay() throws {
        XCTAssertEqual(store.fileName(for: try day(2026, 10, 6, hour: 0), calendar: tokyo), "saydo-alarm-20261006.caf")
        XCTAssertEqual(store.fileName(for: try day(2026, 10, 6, hour: 23), calendar: tokyo), "saydo-alarm-20261006.caf")
        XCTAssertEqual(store.fileName(for: try day(2026, 10, 7, hour: 0), calendar: tokyo), "saydo-alarm-20261007.caf")
    }

    func testRemoveDeletesOnlyThatDaysFile() throws {
        let path = try makeVoice(seconds: 2)
        let first = try day(2026, 10, 6)
        let second = try day(2026, 10, 7)
        XCTAssertNotNil(store.export(relativePath: path, for: first, calendar: tokyo))
        XCTAssertNotNil(store.export(relativePath: path, for: second, calendar: tokyo))

        store.remove(for: first, calendar: tokyo)

        XCTAssertFalse(exists(store.url(for: first, calendar: tokyo)))
        XCTAssertTrue(exists(store.url(for: second, calendar: tokyo)))

        // 無い日の削除は何もしない。
        store.remove(for: first, calendar: tokyo)
    }
}
