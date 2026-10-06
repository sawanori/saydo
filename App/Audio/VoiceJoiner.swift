import AVFoundation
import Foundation

enum VoiceJoinFault: Error, Sendable, Equatable {
    /// つなぐ元が 1 つも無い、または音声のトラックが無い。
    case noAudio
    /// 書き出しの準備ができなかった。
    case exportUnavailable
}

/// 録音をつないで 1 つの音声ファイルにする契約（実装計画 §17.4。約束とアクションの声）。
protocol VoiceJoining: Sendable {
    /// `sources` を順につなぎ、`destination` に m4a で書き出す。つないだ長さ（秒）を返す。
    func join(_ sources: [URL], into destination: URL) async throws -> TimeInterval
}

/// AVFoundation の合成と書き出しでつなぐ実装。
struct VoiceJoiner: VoiceJoining {

    init() {}

    func join(_ sources: [URL], into destination: URL) async throws -> TimeInterval {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VoiceJoinFault.exportUnavailable
        }

        var cursor = CMTime.zero
        for source in sources {
            let asset = AVURLAsset(url: source)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }
            let duration = try await asset.load(.duration)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: sourceTrack, at: cursor)
            cursor = cursor + duration
        }
        guard cursor > .zero else { throw VoiceJoinFault.noAudio }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw VoiceJoinFault.exportUnavailable
        }
        // 書き出しは既存のファイルを上書きしない。
        try? FileManager.default.removeItem(at: destination)
        try await export.export(to: destination, as: .m4a)
        return cursor.seconds
    }
}
