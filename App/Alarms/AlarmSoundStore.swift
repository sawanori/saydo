import AudioToolbox
import Foundation

/// アラームの音にする本人の声の置き場（実装計画 §17.3「追われる」）。
///
/// AlarmKit は `<container>/Library/Sounds/` にあるファイルを名前で鳴らす
/// （docs/spikes/alarm-spike.md §9 (4)。実機で確かめたのは IMA4 / CAF / 44.1 kHz / 1ch と、拡張子つきの名前）。
/// `AudioFileStore` の録音（AAC の .m4a）を同じ形式へ書き直し、30 秒を超える分は切る。
///
/// ファイル名は連鎖の開始日で決める（`saydo-alarm-yyyyMMdd.caf`）。取り消すときは日付だけで消せる。
struct AlarmSoundStore: Sendable {

    /// アラーム音の長さの上限（秒）。
    static let maximumDuration: TimeInterval = 30

    /// 書き出す形式（試作と同じ）。
    static let sampleRate: Double = 44_100
    static let fileExtension = "caf"

    /// IMA4 は 1 パケット 64 フレーム。端数のパケットは 64 フレームに切り上げて書かれるので、
    /// 上限は 64 の倍数に切り下げておく（30 秒ちょうどで切ると 30.0002 秒になる）。
    private static let framesPerPacket: Int64 = 64

    /// `Library/Sounds` にあたるディレクトリ。テストは一時ディレクトリを入れる。
    let soundsDirectory: URL
    /// 元の録音の置き場。
    let audioFileStore: AudioFileStore

    init(soundsDirectory: URL, audioFileStore: AudioFileStore) {
        self.soundsDirectory = soundsDirectory
        self.audioFileStore = audioFileStore
    }

    /// 本番の置き場（`<container>/Library/Sounds`）。
    static func librarySounds(audioFileStore: AudioFileStore) -> AlarmSoundStore {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return AlarmSoundStore(
            soundsDirectory: library.appending(path: "Sounds", directoryHint: .isDirectory),
            audioFileStore: audioFileStore
        )
    }

    // MARK: - 名前

    /// その日の連鎖に使うファイル名（拡張子つき）。AlarmKit にはこの名前を渡す。
    func fileName(for day: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(
            format: "saydo-alarm-%04d%02d%02d.%@",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            Self.fileExtension
        )
    }

    func url(for day: Date, calendar: Calendar = .current) -> URL {
        soundsDirectory.appending(path: fileName(for: day, calendar: calendar), directoryHint: .notDirectory)
    }

    // MARK: - 書き出しと削除

    /// 録音をアラーム音として書き出す。成功したらファイル名、できなければ nil（呼び出し側は既定の音にする）。
    func export(relativePath: String, for day: Date, calendar: Calendar = .current) -> String? {
        let source = audioFileStore.url(forRelativePath: relativePath)
        let manager = FileManager.default
        guard manager.fileExists(atPath: source.path(percentEncoded: false)) else { return nil }

        let destination = url(for: day, calendar: calendar)
        let working = soundsDirectory.appending(
            path: "saydo-alarm-\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        do {
            try manager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            guard Self.convert(from: source, to: working) else {
                try? manager.removeItem(at: working)
                return nil
            }
            if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: working, to: destination)
            return destination.lastPathComponent
        } catch {
            try? manager.removeItem(at: working)
            return nil
        }
    }

    /// その日のアラーム音を消す。無ければ何もしない。
    func remove(for day: Date, calendar: Calendar = .current) {
        try? FileManager.default.removeItem(at: url(for: day, calendar: calendar))
    }

    // MARK: - 変換

    /// `source` を IMA4 / CAF / 44.1 kHz / 1ch で `destination` に書く。上限を超える分は書かない。
    ///
    /// `ExtAudioFile` に読み側・書き側の両方で同じ PCM を「クライアント形式」として伝えると、
    /// 復号・サンプルレート変換・モノラル化・IMA4 への符号化をまとめて引き受けてくれる。
    private static func convert(from source: URL, to destination: URL) -> Bool {
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var fileFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatAppleIMA4,
            mFormatFlags: 0,
            mBytesPerPacket: 34,
            mFramesPerPacket: UInt32(framesPerPacket),
            mBytesPerFrame: 0,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 0,
            mReserved: 0
        )
        let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        var input: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(source as CFURL, &input) == noErr, let input else { return false }
        defer { ExtAudioFileDispose(input) }
        guard ExtAudioFileSetProperty(input, kExtAudioFileProperty_ClientDataFormat, formatSize, &clientFormat) == noErr
        else { return false }

        var output: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(
            destination as CFURL,
            kAudioFileCAFType,
            &fileFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &output
        ) == noErr, let output else { return false }
        var isClosed = false
        defer { if !isClosed { ExtAudioFileDispose(output) } }
        guard ExtAudioFileSetProperty(output, kExtAudioFileProperty_ClientDataFormat, formatSize, &clientFormat) == noErr
        else { return false }

        let limit = Int64(maximumDuration * sampleRate) / framesPerPacket * framesPerPacket
        let chunk = 8_192
        var samples = [Float](repeating: 0, count: chunk)
        var written: Int64 = 0

        while written < limit {
            let wanted = UInt32(min(Int64(chunk), limit - written))
            var frames = wanted
            let status: OSStatus = samples.withUnsafeMutableBytes { raw in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: wanted * 4,
                        mData: raw.baseAddress
                    )
                )
                let readStatus = ExtAudioFileRead(input, &frames, &list)
                guard readStatus == noErr, frames > 0 else { return readStatus }
                list.mBuffers.mDataByteSize = frames * 4
                return ExtAudioFileWrite(output, frames, &list)
            }
            guard status == noErr else { return false }
            if frames == 0 { break }
            written += Int64(frames)
        }

        // 閉じた時点で末尾のパケットとヘッダーが書かれる。
        isClosed = true
        guard ExtAudioFileDispose(output) == noErr else { return false }
        return written > 0
    }
}
